import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class AudioService {
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _sttAvailable = false;
  String _currentLocale = 'en-US';

  Future<void> init() async {
    // Initialize TTS - platform-specific voices may be available
    await _tts.setLanguage(_currentLocale);
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);

    _sttAvailable = await _stt.initialize();
  }

  /// Set language by display name (e.g. 'English', 'Afrikaans', 'isiZulu')
  Future<void> setLanguage(String languageName) async {
    final map = <String, String>{
      'English': 'en-US',
      'Afrikaans': 'af-ZA',
      'isiZulu': 'zu-ZA',
      'isiXhosa': 'xh-ZA',
      'Sesotho': 'st-ZA',
      'Setswana': 'tn-ZA',
      'Xitsonga': 'ts-ZA',
      'Tshivenda': 've-ZA',
      'isiNdebele': 'nd-ZA',
    };
    final locale = map[languageName] ?? languageName;
    _currentLocale = locale;
    try {
      await _tts.setLanguage(locale);
    } catch (_) {}
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  bool get isSttAvailable => _sttAvailable;

  Future<void> startListening(void Function(String recognized) onResult) async {
    if (!_sttAvailable) return;
    await _stt.listen(onResult: (result) {
      if (result.finalResult || result.recognizedWords.isNotEmpty) {
        onResult(result.recognizedWords);
      }
    }, localeId: _currentLocale);
  }

  Future<void> stopListening() async {
    if (!_sttAvailable) return;
    await _stt.stop();
  }
}
