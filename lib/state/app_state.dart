import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audio_service.dart';
import '../services/llama_service.dart';

class Checkpoint {
  final String id;
  final String title;
  final String? page;
  bool completed;
  final DateTime createdAt;
  DateTime? completedAt;
  Checkpoint({
    required this.id,
    required this.title,
    this.page,
    this.completed = false,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();
}


class Message {
  final String text;
  final String who;
  // `original` holds the original model response (if any).
  // `translated` holds the translated text (if any).
  final String? original;
  final String? translated;

  Message({required this.text, required this.who, this.original, this.translated});
}

class AppState extends ChangeNotifier {
  final AudioService audio = AudioService();
  LlamaService? llama;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  List<Message> messages = [];
  bool isListening = false;
  bool isLoading = false;

  String baseUrl = '';
  String apiKey = '';
  String preferredLanguage = 'English';

  List<Checkpoint> checkpoints = [];

  AppState() {
    _init();
    _loadCheckpoints();
  }
  Future<void> _loadCheckpoints() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('checkpoints') ?? [];
    checkpoints = raw.map((s) {
      final parts = s.split('|');
      return Checkpoint(
        id: parts[0],
        title: parts[1],
        page: parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null,
        completed: parts.length > 3 ? parts[3] == '1' : false,
        createdAt: parts.length > 4 ? DateTime.parse(parts[4]) : DateTime.now(),
        completedAt: parts.length > 5 && parts[5].isNotEmpty ? DateTime.parse(parts[5]) : null,
      );
    }).toList();
    notifyListeners();
  }

  Future<void> _saveCheckpoints() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = checkpoints
        .map((c) =>
            '${c.id}|${c.title}|${c.page ?? ''}|${c.completed ? '1' : '0'}|${c.createdAt.toIso8601String()}|${c.completedAt?.toIso8601String() ?? ''}')
        .toList();
    await prefs.setStringList('checkpoints', raw);
  }

  void addCheckpoint(String title, {String? page}) {
    final cp = Checkpoint(id: DateTime.now().millisecondsSinceEpoch.toString(), title: title, page: page);
    checkpoints.add(cp);
    _saveCheckpoints();
    notifyListeners();
  }

  void completeCheckpoint(String id) {
    final idx = checkpoints.indexWhere((c) => c.id == id);
    if (idx != -1) {
      checkpoints[idx].completed = true;
      checkpoints[idx].completedAt = DateTime.now();
      _saveCheckpoints();
      notifyListeners();
    }
  }

  Future<void> _init() async {
    await audio.init();
    try {
      final storedBase = await _secureStorage.read(key: 'llama_base_url');
      final storedKey = await _secureStorage.read(key: 'llama_api_key');
      final storedLang = await _secureStorage.read(key: 'preferred_language');
      if (storedBase != null || storedKey != null) {
        baseUrl = storedBase ?? '';
        apiKey = storedKey ?? '';
        if (baseUrl.isNotEmpty) {
          llama = LlamaService(baseUrl: baseUrl, apiKey: apiKey);
        }
        notifyListeners();
      }
      if (storedLang != null && storedLang.isNotEmpty) {
        preferredLanguage = storedLang;
        try {
          await audio.setLanguage(preferredLanguage);
        } catch (_) {}
        notifyListeners();
      }
    } catch (_) {}
  }

  void configureLlama({required String baseUrl, required String apiKey}) {
    this.baseUrl = baseUrl;
    this.apiKey = apiKey;
    llama = LlamaService(baseUrl: baseUrl, apiKey: apiKey);
    try {
      _secureStorage.write(key: 'llama_base_url', value: baseUrl);
      _secureStorage.write(key: 'llama_api_key', value: apiKey);
    } catch (_) {}
    notifyListeners();
  }

  void setPreferredLanguage(String lang) {
    preferredLanguage = lang;
    try {
      _secureStorage.write(key: 'preferred_language', value: lang);
    } catch (_) {}
    try {
      audio.setLanguage(lang);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> sendPrompt(String prompt) async {
    if (prompt.trim().isEmpty) return;
    messages.add(Message(text: prompt, who: 'You'));
    isLoading = true;
    notifyListeners();

    try {
      if (llama == null) {
        messages.add(Message(text: 'Configure Llama API first (Settings).', who: 'System'));
      } else {
        final resp = await llama!.sendPrompt(prompt);
        // If user prefers a language other than English, request a translation
        final target = preferredLanguage.trim();
        if (target.isNotEmpty && !target.toLowerCase().startsWith('english')) {
          try {
            final transPrompt = 'Translate the following text to $target preserving meaning and tone:\n\n$resp';
            final translated = await llama!.sendPrompt(transPrompt);
            // store both original and translated
            messages.add(Message(text: translated, who: 'Llama', original: resp, translated: translated));
          } catch (_) {
            // translation failed, add original as-is
            messages.add(Message(text: resp, who: 'Llama', original: resp));
          }
        } else {
          messages.add(Message(text: resp, who: 'Llama', original: resp));
        }
      }
    } catch (e) {
      messages.add(Message(text: 'Error: ${e.toString()}', who: 'System'));
    }

    isLoading = false;
    notifyListeners();
  }

  Future<void> speakText(String text) async {
    await audio.speak(text);
  }

  Future<void> startListening() async {
    if (!audio.isSttAvailable) return;
    isListening = true;
    notifyListeners();
    await audio.startListening((recognized) async {
      isListening = false;
      messages.add(Message(text: recognized, who: 'You'));
      notifyListeners();
      await sendPrompt(recognized);
    });
  }

  Future<void> stopListening() async {
    await audio.stopListening();
    isListening = false;
    notifyListeners();
  }

  /// Translate an existing message at [index] using the preferred language.
  /// Replaces the message with a new Message containing original + translated text.
  Future<void> translateMessage(int index) async {
    if (index < 0 || index >= messages.length) return;
    final msg = messages[index];
    final originalText = msg.original ?? msg.text;
    final target = preferredLanguage.trim();
    if (target.isEmpty || target.toLowerCase().startsWith('english')) return;

    isLoading = true;
    notifyListeners();
    try {
      if (llama == null) {
        messages.add(Message(text: 'Configure Llama API first (Settings).', who: 'System'));
      } else {
        final transPrompt = 'Translate the following text to $target preserving meaning and tone:\n\n$originalText';
        final translated = await llama!.sendPrompt(transPrompt);
        // replace message at index with translated version
        messages[index] = Message(text: translated, who: msg.who, original: originalText, translated: translated);
      }
    } catch (e) {
      messages.add(Message(text: 'Translation error: ${e.toString()}', who: 'System'));
    }
    isLoading = false;
    notifyListeners();
  }
}
