import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/app_state.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  LatLng? _currentLocation;
  List<LatLng> _savedPins = [];

  static const _savedPinsKey = 'saved_pins';

  @override
  void initState() {
    super.initState();
    _loadSavedPins();
    // Try auto-center if permission already granted
    _tryAutoCenter();
  }

  Future<void> _loadSavedPins() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_savedPinsKey) ?? [];
    setState(() {
      _savedPins = raw.map((s) {
        final j = jsonDecode(s) as Map<String, dynamic>;
        return LatLng(j['lat'] as double, j['lng'] as double);
      }).toList();
    });
  }

  Future<void> _savePins() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _savedPins.map((p) => jsonEncode({'lat': p.latitude, 'lng': p.longitude})).toList();
    await prefs.setStringList(_savedPinsKey, raw);
  }

  Future<void> _tryAutoCenter() async {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
      await _determinePosition(silent: true);
    }
  }

  Future<void> _determinePosition({bool silent = false}) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      if (!silent) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled.')));
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        if (!silent) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are denied')));
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      if (!silent) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are permanently denied')));
      return;
    }

    final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    final latLng = LatLng(pos.latitude, pos.longitude);
    if (!mounted) return;
    setState(() {
      _currentLocation = latLng;
    });
    _mapController.move(latLng, 15.0);

    // Reverse-geocode to a full street address, falling back to coordinates.
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
    } catch (_) {
      // ignore geocoding failures, keep coordinates fallback
    }

    try {
      if (!mounted) return;
      final app = Provider.of<AppState>(context, listen: false);
      app.messages.add(Message(text: locText, who: 'You'));
      // send location to Llama asynchronously (fire-and-forget)
      app.sendPrompt(locText);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: Column(children: [
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: _currentLocation ?? LatLng(0, 0),
              zoom: _currentLocation == null ? 2.0 : 13.0,
              onLongPress: (tapPosition, latLng) {
                // add a saved pin
                setState(() {
                  _savedPins.add(latLng);
                });
                _savePins();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pin saved')));
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.flutter_application_1',
              ),
              if (_currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLocation!,
                      width: 80,
                      height: 80,
                      builder: (ctx) => const Icon(Icons.location_on, color: Colors.red, size: 40),
                    ),
                  ],
                ),
              if (_savedPins.isNotEmpty)
                MarkerLayer(
                  markers: _savedPins
                      .map((p) => Marker(
                            point: p,
                            width: 60,
                            height: 60,
                            builder: (ctx) => const Icon(Icons.push_pin, color: Colors.blue, size: 28),
                          ))
                      .toList(),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.my_location),
                label: const Text('Get Current Location'),
                onPressed: _determinePosition,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              child: const Text('Center'),
              onPressed: () {
                if (_currentLocation != null) {
                  _mapController.move(_currentLocation!, 15.0);
                }
              },
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              icon: const Icon(Icons.layers),
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'list_pins', child: Text('Saved Pins')),
                const PopupMenuItem(value: 'clear_pins', child: Text('Clear Saved Pins')),
              ],
              onSelected: (v) async {
                if (v == 'list_pins') {
                  if (_savedPins.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No saved pins')));
                    return;
                  }
                  showModalBottomSheet(
                      context: context,
                      builder: (ctx) => ListView.builder(
                            itemCount: _savedPins.length,
                            itemBuilder: (ctx, i) {
                              final p = _savedPins[i];
                              return ListTile(
                                title: Text('${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}'),
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(
                                    icon: const Icon(Icons.location_searching),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _mapController.move(p, 15.0);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () {
                                      setState(() {
                                        _savedPins.removeAt(i);
                                      });
                                      _savePins();
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                ]),
                              );
                            },
                          ));
                } else if (v == 'clear_pins') {
                  setState(() {
                    _savedPins.clear();
                  });
                  await _savePins();
                }
              },
            ),
          ]),
        ),
      ]),
    );
  }
}
