import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'pages/map_page.dart';
import 'pages/timeline_page.dart';
import 'state/app_state.dart';
import 'state/login_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'Journey to Recovery',
        theme: ThemeData(
          brightness: Brightness.light,
          primarySwatch: Colors.green,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          scaffoldBackgroundColor: Colors.white,
          textTheme: ThemeData.light().textTheme.apply(bodyColor: Colors.black, displayColor: Colors.black),
        ),
        initialRoute: '/login',
        routes: {
          '/login': (context) => LoginPage(),
          '/home': (context) => HomePage(),
        }
      ),
    );
  }

  
}


// AppState moved to `lib/state/app_state.dart`

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  String _getEmergencyNumber() {
    try {
      final locale = WidgetsBinding.instance.platformDispatcher.locale;
      final country = locale.countryCode?.toUpperCase();
      switch (country) {
        case 'US':
        case 'CA':
          return '911';
        case 'AU':
          return '000';
        case 'IN':
          return '084 124';
        case 'ZA':
          return '10111';
        case 'BR':
          return '190';
        default:
          return '084 124';
      }
    } catch (_) {
      return '084 124';
    }
  }

  Future<void> _callEmergency(BuildContext context) async {
    final number = _getEmergencyNumber();
    final uri = Uri(scheme: 'tel', path: number);

    // Show a dialog with the emergency number before attempting to call
    if (!context.mounted) return;
    final shouldCall = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Emergency Call'),
            content: Text('Call emergency number: $number'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Call Now')),
            ],
          ),
        ) ?? false;

    if (!shouldCall) return;

    // Check mounted and capture messenger and app before awaiting to avoid using BuildContext across async gaps
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final app = Provider.of<AppState>(context, listen: false);

    // Try to get current location and reverse-geocode to text, then send to Llama and add to messages
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      String locText = 'Location: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
      try {
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          // Build full street address: try street, name, subLocality, locality, state, country
          final partsSet = {
            if (p.street != null && p.street!.isNotEmpty) p.street!.trim(),
            if (p.name != null && p.name!.isNotEmpty && (p.street == null || p.name != p.street)) p.name!.trim(),
            if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality!.trim(),
            if (p.locality != null && p.locality!.isNotEmpty) p.locality!.trim(),
            if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) p.administrativeArea!.trim(),
            if (p.country != null && p.country!.isNotEmpty) p.country!.trim(),
          };
          final parts = partsSet.toList();
          if (parts.isNotEmpty) locText = parts.join(', ');
        }
      } catch (_) {}

      // Add message and send to Llama (fire-and-forget)
      try {
        app.messages.add(Message(text: 'Emergency at: $locText', who: 'You'));
        app.sendPrompt('Emergency at: $locText');
      } catch (_) {}
    } catch (_) {
      // if location fails, continue to attempt call
    }

    try {
      final can = await canLaunchUrl(uri);
      if (!can) {
        messenger.showSnackBar(SnackBar(content: Text('Cannot place a call to $number on this device.')));
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to call $number: ${e.toString()}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppState>(context);

    final filtered = app.messages.where((m) {
      final q = _searchController.text.toLowerCase();
      if (q.isEmpty) return true;
      final textMatch = m.text.toLowerCase().contains(q) || m.who.toLowerCase().contains(q);
      final orig = (m.original ?? '').toLowerCase();
      final trans = (m.translated ?? '').toLowerCase();
      return textMatch || orig.contains(q) || trans.contains(q);
    }).toList();

    return Scaffold(
        appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.home),
          const SizedBox(width: 8),
          const Text('Journey to Recovery'),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _openSettings(context, app),
          )
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search messages...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
            ]),
          ),
        ),
      ),
      // Side dashboard (drawer)
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
              child: const Text('Dashboard', style: TextStyle(color: Colors.white, fontSize: 20)),
            ),
            ListTile(
              leading: const Icon(Icons.chat),
              title: const Text('Conversations'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.map),
              title: const Text('Map'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const MapPage()));
              },
            ),
            ExpansionTile(
              leading: const Icon(Icons.checklist),
              title: const Text('My Journey'),
              children: [
                ...app.checkpoints.map((cp) => ListTile(
                  leading: Icon(cp.completed ? Icons.check_circle : Icons.radio_button_unchecked, color: cp.completed ? Colors.green : null),
                  title: Text(cp.title),
                  trailing: cp.completed ? null : IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: () {
                      app.completeCheckpoint(cp.id);
                    },
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    if (cp.page == 'map') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const MapPage()));
                    }
                  },
                ))
              ],
            ),
            ListTile(
              leading: const Icon(Icons.timeline),
              title: const Text('Timeline'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const TimelinePage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('About'),
              onTap: () => showAboutDialog(context: context, applicationName: 'Journey to Recovery'),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              
              if (app.isLoading) LinearProgressIndicator(),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final m = filtered[index];
                    final isYou = m.who == 'You';
                    return Align(
                      alignment: isYou ? Alignment.centerRight : Alignment.centerLeft,
                      child: Card(
                        color: isYou ? const Color.fromRGBO(255, 255, 255, 0.12) : const Color.fromRGBO(255, 255, 255, 0.08),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.who, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(height: 6),
                              if (m.original != null && m.translated != null) ...[
                                Text(m.translated!, style: const TextStyle(fontSize: 16)),
                                const SizedBox(height: 8),
                                Text('Original:', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12, color: Colors.grey[700])),
                                Text(m.original!, style: const TextStyle(fontStyle: FontStyle.italic)),
                                Row(children: [
                                  IconButton(
                                    icon: const Icon(Icons.volume_up),
                                    onPressed: () => app.speakText(m.translated ?? m.text),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.translate),
                                    tooltip: 'Re-translate',
                                    onPressed: () {
                                      final realIndex = app.messages.indexOf(m);
                                      if (realIndex != -1) app.translateMessage(realIndex);
                                    },
                                  ),
                                ])
                              ] else ...[
                                Text(m.text),
                                Row(children: [
                                  IconButton(
                                    icon: const Icon(Icons.volume_up),
                                    onPressed: () => app.speakText(m.text),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.translate),
                                    tooltip: 'Translate',
                                    onPressed: () {
                                      final realIndex = app.messages.indexOf(m);
                                      if (realIndex != -1) app.translateMessage(realIndex);
                                    },
                                  ),
                                ])
                              ]
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    // Shortcuts: Help (panic) and Map quick-access
                    IconButton(
                      tooltip: 'Map',
                      icon: const Icon(Icons.map),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const MapPage()));
                      },
                    ),
                    IconButton(
                      tooltip: 'Help (panic)',
                      icon: const Icon(Icons.report_problem, color: Colors.redAccent),
                      onPressed: () => _callEmergency(context),
                    ),
                    IconButton(
                      icon: Icon(app.isListening ? Icons.mic_off : Icons.mic),
                      onPressed: () async {
                        if (app.isListening) {
                          await app.stopListening();
                        } else {
                          await app.startListening();
                        }
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        decoration: const InputDecoration(hintText: 'Enter text to send to Llama...'),
                        onSubmitted: (value) async {
                          await app.sendPrompt(value);
                          _inputController.clear();
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: () async {
                        final v = _inputController.text;
                        await app.sendPrompt(v);
                        _inputController.clear();
                      },
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Shortcuts',
                      icon: const Icon(Icons.more_vert),
                      onSelected: (v) {
                        if (v == 'help') {
                          _callEmergency(context);
                        } else if (v == 'map') {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const MapPage()));
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'help', child: Text('Call Help')),
                        PopupMenuItem(value: 'map', child: Text('Open Map')),
                      ],
                    ),
                  ]),
                ),
              ),
            ],
          ),
          // Floating action button for checkpoints
          Positioned(
            bottom: 24,
            right: 24,
            child: FloatingActionButton.extended(
              icon: const Icon(Icons.checklist),
              label: const Text('My Journey'),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) {
                    final cpTitleCtrl = TextEditingController();
                    return AlertDialog(
                      title: const Text('My Journey'),
                      content: SizedBox(
                        width: 300,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ...app.checkpoints.map((cp) => ListTile(
                              leading: Icon(cp.completed ? Icons.check_circle : Icons.radio_button_unchecked, color: cp.completed ? Colors.green : null),
                              title: Text(cp.title),
                              trailing: cp.completed ? null : IconButton(
                                icon: const Icon(Icons.check),
                                onPressed: () {
                                  app.completeCheckpoint(cp.id);
                                  Navigator.pop(ctx);
                                },
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                if (cp.page == 'map') {
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => const MapPage()));
                                }
                              },
                            )),
                            const Divider(),
                            TextField(
                              controller: cpTitleCtrl,
                              decoration: const InputDecoration(hintText: 'Add new journey milestone...'),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Close'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const TimelinePage()));
                          },
                          child: const Text('View Timeline'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            final title = cpTitleCtrl.text.trim();
                            if (title.isNotEmpty) {
                              app.addCheckpoint(title);
                              Navigator.pop(ctx);
                            }
                          },
                          child: const Text('Add'),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openSettings(BuildContext context, AppState app) {
    final baseCtrl = TextEditingController(text: app.baseUrl);
    final keyCtrl = TextEditingController(text: app.apiKey);
    String selectedLang = app.preferredLanguage;

    final languages = [
      'English',
      'Afrikaans',
      'isiZulu',
      'isiXhosa',
      'Sesotho',
      'Setswana',
      'Xitsonga',
      'Tshivenda',
      'isiNdebele',
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Groq API Settings'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: baseCtrl,
            decoration: const InputDecoration(
              labelText: 'Groq API Endpoint',
              hintText: 'https://api.groq.com/openai/v1/chat/completions',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: keyCtrl,
            decoration: const InputDecoration(labelText: 'Groq API Key'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: selectedLang,
            decoration: const InputDecoration(labelText: 'Preferred Language'),
            items: languages.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
            onChanged: (v) {
              if (v != null) selectedLang = v;
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'Get your Groq API key from https://console.groq.com/keys\n\n'
            'Groq offers fast LLaMA inference at no cost.',
            style: TextStyle(fontSize: 12),
          )
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              app.configureLlama(baseUrl: baseCtrl.text.trim(), apiKey: keyCtrl.text.trim());
              app.setPreferredLanguage(selectedLang);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          )
        ],
      ),
    );
  }

  
}
