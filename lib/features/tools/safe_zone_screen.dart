import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class SafeZoneScreen extends ConsumerStatefulWidget {
  const SafeZoneScreen({super.key});

  @override
  ConsumerState<SafeZoneScreen> createState() => _SafeZoneScreenState();
}

class _SafeZoneScreenState extends ConsumerState<SafeZoneScreen> {
  final _zoneNameController = TextEditingController();
  double _radiusFeet = 1000; // default 1000 ft
  bool _alertOnEntry = true;
  bool _alertOnExit = true;
  bool _isSaving = false;
  bool _isFetchingLocation = false;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
  }

  @override
  void dispose() {
    _zoneNameController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isFetchingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services disabled');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission permanently denied');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
      }
    } catch (e) {
      debugPrint('[SafeZone] Location error: $e');
      // Default to a reasonable fallback
      if (mounted) {
        setState(() {
          _latitude = 37.7749;
          _longitude = -122.4194;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not get location: $e. Using default.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isFetchingLocation = false);
    }
  }

  Future<void> _handleSave() async {
    if (_zoneNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a zone name.'),
          backgroundColor: ShieldColors.urgentRed,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile found');

      // 1 foot = 0.3048 meters
      final radiusMeters = (_radiusFeet * 0.3048).round();

      await Supabase.instance.client.from('locations_safe_zones').insert({
        'family_id': profile.familyId,
        'name': _zoneNameController.text.trim(),
        'latitude': _latitude ?? 37.7749,
        'longitude': _longitude ?? -122.4194,
        'radius_meters': radiusMeters,
        'alert_on_entry': _alertOnEntry,
        'alert_on_exit': _alertOnExit,
      });

      // Log event
      await Supabase.instance.client.from('well_events').insert({
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'event_type': 'safe_zone_created',
        'title': 'New Safe Zone',
        'description':
            '${profile.fullName ?? 'User'} created safe zone "${_zoneNameController.text.trim()}" (${_radiusFeet.round()} ft radius)',
      });

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Safe Zone created!'),
            backgroundColor: ShieldColors.safeZoneGreen,
          ),
        );
      }
    } catch (e) {
      debugPrint('[SafeZone] Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Safe Zone'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _handleSave,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'SAVE',
                    style: TextStyle(
                      color: ShieldColors.activeTeal,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Map area
            Container(
              height: 250,
              width: double.infinity,
              color: Colors.grey.shade200,
              child: _latitude == null
                  ? const Center(child: CircularProgressIndicator())
                  : IgnorePointer(
                      ignoring: true, // Let the user scroll the page, map is just visual
                      child: Stack(
                        children: [
                          FlutterMap(
                            options: MapOptions(
                              initialCenter: LatLng(_latitude!, _longitude!),
                              initialZoom: 14.5, // Closer zoom since we usually track houses/schools
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.none,
                              ),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://mt1.google.com/vt/lyrs=r&x={x}&y={y}&z={z}',
                                userAgentPackageName: 'com.anwiik.wellcheck',
                              ),
                              CircleLayer(
                                circles: [
                                  CircleMarker(
                                    point: LatLng(_latitude!, _longitude!),
                                    color: ShieldColors.safeZoneGreen.withValues(alpha: 0.3),
                                    borderColor: ShieldColors.safeZoneGreen,
                                    borderStrokeWidth: 2,
                                    useRadiusInMeter: true,
                                    radius: _radiusFeet * 0.3048, // Convert ft to meters for map
                                  ),
                                ],
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(_latitude!, _longitude!),
                                    width: 40,
                                    height: 40,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: ShieldColors.activeTeal,
                                      size: 40,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Positioned(
                            bottom: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}',
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _zoneNameController,
                    decoration: InputDecoration(
                      labelText: 'Zone Name (e.g. Home, School)',
                      prefixIcon: const Icon(Icons.label_outline),
                      border: OutlineInputBorder(
                        borderRadius: ShieldDesign.roundedTwelve,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Fence Radius: ${_radiusFeet.round()} ft',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    value: _radiusFeet,
                    min: 250,
                    max: 5280, // Up to 1 mile
                    divisions: 20,
                    activeColor: ShieldColors.activeTeal,
                    label: '${_radiusFeet.round()} ft',
                    onChanged: (value) => setState(() => _radiusFeet = value),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Alert Rules',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Alert on Entry'),
                    subtitle: const Text('Notify when member arrives.'),
                    value: _alertOnEntry,
                    activeColor: ShieldColors.activeTeal,
                    onChanged: (val) => setState(() => _alertOnEntry = val),
                  ),
                  SwitchListTile(
                    title: const Text('Alert on Exit'),
                    subtitle: const Text('Notify when member leaves.'),
                    value: _alertOnExit,
                    activeColor: ShieldColors.activeTeal,
                    onChanged: (val) => setState(() => _alertOnExit = val),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _isFetchingLocation ? null : _fetchCurrentLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Refresh My Location'),
                    style: TextButton.styleFrom(
                      foregroundColor: ShieldColors.activeTeal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
