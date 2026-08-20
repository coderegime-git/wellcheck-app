import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// class SafeZoneScreen extends ConsumerStatefulWidget {
//   const SafeZoneScreen({super.key});
//
//   @override
//   ConsumerState<SafeZoneScreen> createState() => _SafeZoneScreenState();
// }
//
// class _SafeZoneScreenState extends ConsumerState<SafeZoneScreen> {
//   final _zoneNameController = TextEditingController();
//   double _radiusFeet = 1000; // default 1000 ft
//   bool _alertOnEntry = true;
//   bool _alertOnExit = true;
//   bool _isSaving = false;
//   bool _isFetchingLocation = false;
//   double? _latitude;
//   double? _longitude;
//
//   @override
//   void initState() {
//     super.initState();
//     _fetchCurrentLocation();
//   }
//
//   @override
//   void dispose() {
//     _zoneNameController.dispose();
//     super.dispose();
//   }
//
//   Future<void> _fetchCurrentLocation() async {
//     setState(() => _isFetchingLocation = true);
//     try {
//       bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
//       if (!serviceEnabled) {
//         throw Exception('Location services disabled');
//       }
//
//       LocationPermission permission = await Geolocator.checkPermission();
//       if (permission == LocationPermission.denied) {
//         permission = await Geolocator.requestPermission();
//         if (permission == LocationPermission.denied) {
//           throw Exception('Location permission denied');
//         }
//       }
//       if (permission == LocationPermission.deniedForever) {
//         throw Exception('Location permission permanently denied');
//       }
//
//       final position = await Geolocator.getCurrentPosition(
//         locationSettings:
//             const LocationSettings(accuracy: LocationAccuracy.high),
//       );
//       if (mounted) {
//         setState(() {
//           _latitude = position.latitude;
//           _longitude = position.longitude;
//         });
//       }
//     } catch (e) {
//       debugPrint('[SafeZone] Location error: $e');
//       // Default to a reasonable fallback
//       if (mounted) {
//         setState(() {
//           _latitude = 37.7749;
//           _longitude = -122.4194;
//         });
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Could not get location: $e. Using default.'),
//             backgroundColor: Colors.orange,
//           ),
//         );
//       }
//     } finally {
//       if (mounted) setState(() => _isFetchingLocation = false);
//     }
//   }
//
//   Future<void> _handleSave() async {
//     if (_zoneNameController.text.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Please enter a zone name.'),
//           backgroundColor: ShieldColors.urgentRed,
//         ),
//       );
//       return;
//     }
//
//     setState(() => _isSaving = true);
//     try {
//       final profile = await ref.read(currentUserProfileProvider.future);
//       if (profile == null) throw Exception('No profile found');
//
//       // 1 foot = 0.3048 meters
//       final radiusMeters = (_radiusFeet * 0.3048).round();
//       final now = DateTime.now().toUtc();
//       int batteryLevel =
//       100; // Safe default for simulators and aggressive background iOS policies
//       try {
//         final battery = Battery();
//         batteryLevel = await battery.batteryLevel;
//       } catch (e) {
//         debugPrint(
//           'Battery info not available over isolate, using default: $e',
//         );
//       }
//
//       await Supabase.instance.client.from('locations_safe_zones').insert({
//         'family_id': profile.familyId,
//         'name': _zoneNameController.text.trim(),
//         'latitude': _latitude ?? 37.7749,
//         'longitude': _longitude ?? -122.4194,
//         'radius_meters': radiusMeters,
//         'alert_on_entry': _alertOnEntry,
//         'alert_on_exit': _alertOnExit,
//       });
//
//       // Log event
//       await Supabase.instance.client.from('well_events').insert({
//         'family_id': profile.familyId,
//         'user_id': profile.userId,
//         'event_type': 'safe_zone_created',
//         'title': 'New Safe Zone',
//         'battery_level': batteryLevel,
//
//         'description':
//             '${profile.fullName ?? 'User'} created safe zone "${_zoneNameController.text.trim()}" (${_radiusFeet.round()} ft radius)',
//       });
//
//       if (mounted) {
//         Navigator.of(context).pop();
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Safe Zone created!'),
//             backgroundColor: ShieldColors.safeZoneGreen,
//           ),
//         );
//       }
//     } catch (e) {
//       debugPrint('[SafeZone] Save error: $e');
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Failed to save: $e'),
//             backgroundColor: Colors.red,
//             duration: const Duration(seconds: 6),
//           ),
//         );
//       }
//     } finally {
//       if (mounted) setState(() => _isSaving = false);
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Create Safe Zone'),
//         actions: [
//           TextButton(
//             onPressed: _isSaving ? null : _handleSave,
//             child: _isSaving
//                 ? const SizedBox(
//                     width: 20,
//                     height: 20,
//                     child: CircularProgressIndicator(strokeWidth: 2),
//                   )
//                 : const Text(
//                     'SAVE',
//                     style: TextStyle(
//                       color: ShieldColors.activeTeal,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//           ),
//         ],
//       ),
//       body: SingleChildScrollView(
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // Map area
//             Container(
//               height: 250,
//               width: double.infinity,
//               color: Colors.grey.shade200,
//               child: _latitude == null
//                   ? const Center(child: CircularProgressIndicator())
//                   : IgnorePointer(
//                       ignoring: true, // Let the user scroll the page, map is just visual
//                       child: Stack(
//                         children: [
//                           FlutterMap(
//                             options: MapOptions(
//                               initialCenter: LatLng(_latitude!, _longitude!),
//                               initialZoom: 14.5, // Closer zoom since we usually track houses/schools
//                               interactionOptions: const InteractionOptions(
//                                 flags: InteractiveFlag.none,
//                               ),
//                             ),
//                             children: [
//                               TileLayer(
//                                 urlTemplate:
//                                     'https://mt1.google.com/vt/lyrs=r&x={x}&y={y}&z={z}',
//                                 userAgentPackageName: 'com.anwiik.wellcheck',
//                               ),
//                               CircleLayer(
//                                 circles: [
//                                   CircleMarker(
//                                     point: LatLng(_latitude!, _longitude!),
//                                     color: ShieldColors.safeZoneGreen.withValues(alpha: 0.3),
//                                     borderColor: ShieldColors.safeZoneGreen,
//                                     borderStrokeWidth: 2,
//                                     useRadiusInMeter: true,
//                                     radius: _radiusFeet * 0.3048, // Convert ft to meters for map
//                                   ),
//                                 ],
//                               ),
//                               MarkerLayer(
//                                 markers: [
//                                   Marker(
//                                     point: LatLng(_latitude!, _longitude!),
//                                     width: 40,
//                                     height: 40,
//                                     child: const Icon(
//                                       Icons.location_on,
//                                       color: ShieldColors.activeTeal,
//                                       size: 40,
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ],
//                           ),
//                           Positioned(
//                             bottom: 10,
//                             right: 10,
//                             child: Container(
//                               padding: const EdgeInsets.symmetric(
//                                   horizontal: 12, vertical: 4),
//                               decoration: BoxDecoration(
//                                 color: Colors.white.withValues(alpha: 0.8),
//                                 borderRadius: BorderRadius.circular(12),
//                               ),
//                               child: Text(
//                                 '${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}',
//                                 style: const TextStyle(
//                                     fontSize: 11, fontWeight: FontWeight.bold),
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//             ),
//             Padding(
//               padding: const EdgeInsets.all(24.0),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   TextField(
//                     controller: _zoneNameController,
//                     decoration: InputDecoration(
//                       labelText: 'Zone Name (e.g. Home, School)',
//                       prefixIcon: const Icon(Icons.label_outline),
//                       border: OutlineInputBorder(
//                         borderRadius: ShieldDesign.roundedTwelve,
//                       ),
//                     ),
//                   ),
//                   const SizedBox(height: 24),
//                   Text(
//                     'Fence Radius: ${_radiusFeet.round()} ft',
//                     style: const TextStyle(fontWeight: FontWeight.bold),
//                   ),
//                   Slider(
//                     value: _radiusFeet,
//                     min: 250,
//                     max: 5280, // Up to 1 mile
//                     divisions: 20,
//                     activeColor: ShieldColors.activeTeal,
//                     label: '${_radiusFeet.round()} ft',
//                     onChanged: (value) => setState(() => _radiusFeet = value),
//                   ),
//                   const SizedBox(height: 24),
//                   const Text(
//                     'Alert Rules',
//                     style: TextStyle(fontWeight: FontWeight.bold),
//                   ),
//                   const SizedBox(height: 8),
//                   SwitchListTile(
//                     title: const Text('Alert on Entry'),
//                     subtitle: const Text('Notify when member arrives.'),
//                     value: _alertOnEntry,
//                     activeColor: ShieldColors.activeTeal,
//                     onChanged: (val) => setState(() => _alertOnEntry = val),
//                   ),
//                   SwitchListTile(
//                     title: const Text('Alert on Exit'),
//                     subtitle: const Text('Notify when member leaves.'),
//                     value: _alertOnExit,
//                     activeColor: ShieldColors.activeTeal,
//                     onChanged: (val) => setState(() => _alertOnExit = val),
//                   ),
//                   const SizedBox(height: 16),
//                   TextButton.icon(
//                     onPressed: _isFetchingLocation ? null : _fetchCurrentLocation,
//                     icon: const Icon(Icons.my_location),
//                     label: const Text('Refresh My Location'),
//                     style: TextButton.styleFrom(
//                       foregroundColor: ShieldColors.activeTeal,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class SafeZoneScreen extends ConsumerStatefulWidget {
  /// Pass an existing zone map to enter edit mode. Null = create mode.
  final Map<String, dynamic>? existingZone;

  const SafeZoneScreen({super.key, this.existingZone});

  @override
  ConsumerState<SafeZoneScreen> createState() => _SafeZoneScreenState();
}

class _SafeZoneScreenState extends ConsumerState<SafeZoneScreen> {
  final _zoneNameController = TextEditingController();
  double _radiusFeet = 1000;
  bool _alertOnEntry = true;
  bool _alertOnExit = true;
  bool _isSaving = false;
  bool _isFetchingLocation = false;
  double? _latitude;
  double? _longitude;

  bool get _isEditing => widget.existingZone != null;
  bool _isLoadingMembers = true;
  String? _selectedUserId;
  String? _selectedUserName;
  List<Map<String, dynamic>> _familyMembers = [];
  final _addressController = TextEditingController();
  final mapController = MapController();

  List<dynamic> _addressSuggestions = [];
  bool _isSearchingAddress = false;
  Timer? _debounce;

  void onMapMoved(double lat, double lng) {
    _debounce?.cancel();

    _debounce = Timer(const Duration(seconds: 1), () {
      _reverseGeocode(lat, lng);
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchFamilyMembers();
  }

  @override
  void dispose() {
    _zoneNameController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isFetchingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services disabled');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          await Geolocator.openLocationSettings();

          throw Exception('Location permission denied');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openLocationSettings();
        throw Exception('Location permission permanently denied');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
        if (_latitude != null && _longitude != null) {
          await _reverseGeocode(_latitude ?? 0, _longitude ?? 0);
        }
        print("_latitude");
        print(_latitude);
      }
    } catch (e) {
      debugPrint('[SafeZone] Location error: $e');
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

  Future<void> _searchAddress(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isSearchingAddress = true;
    });

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=10',
      );

      final res = await http.get(url, headers: {'User-Agent': 'wellcheck-app'});

      final data = jsonDecode(res.body);

      setState(() {
        _addressSuggestions = data;
      });
    } catch (e) {
      debugPrint("search error: $e");
    }

    setState(() {
      _isSearchingAddress = false;
    });
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
    if (_addressController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a address.'),
          backgroundColor: ShieldColors.urgentRed,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile found');

      final radiusMeters = (_radiusFeet * 0.3048).round();
      int batteryLevel = 100;
      try {
        final battery = Battery();
        batteryLevel = await battery.batteryLevel;
      } catch (e) {
        debugPrint('Battery info not available: $e');
      }

      final payload = {
        'name': _zoneNameController.text.trim(),

        'assigned_user_id': _selectedUserId,

        'assigned_user_name': _selectedUserName,

        'address': _addressController.text,

        'latitude': _latitude,

        'longitude': _longitude,

        'radius_meters': radiusMeters,

        'alert_on_entry': _alertOnEntry,

        'alert_on_exit': _alertOnExit,
      };

      if (_isEditing) {
        // ── UPDATE ──────────────────────────────────────────────
        await Supabase.instance.client
            .from('locations_safe_zones')
            .update(payload)
            .eq('id', widget.existingZone!['id']);

        await Supabase.instance.client.from('well_events').insert({
          'family_id': profile.familyId,
          'user_id': profile.userId,
          'event_type': 'safe_zone_updated',
          'title': 'Safe Zone Updated',
          'battery_level': batteryLevel,
          'description':
              '${profile.fullName ?? 'User'} updated safe zone "${_zoneNameController.text.trim()}" (${_radiusFeet.round()} ft radius)',
        });
      } else {
        // ── CREATE ──────────────────────────────────────────────
        await Supabase.instance.client.from('locations_safe_zones').insert({
          ...payload,
          'family_id': profile.familyId,
        });

        await Supabase.instance.client.from('well_events').insert({
          'family_id': profile.familyId,
          'user_id': profile.userId,
          'event_type': 'safe_zone_created',
          'title': 'New Safe Zone',
          'battery_level': batteryLevel,
          'description':
              '${profile.fullName ?? 'User'} created safe zone "${_zoneNameController.text.trim()}" (${_radiusFeet.round()} ft radius)',
        });
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Safe Zone updated!' : 'Safe Zone created!',
            ),
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

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: ShieldColors.activeTeal,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Future<void> _fetchFamilyMembers() async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;

      final res = await Supabase.instance.client
          .from('family_members')
          .select('user_id, role, profiles(full_name)')
          .eq('family_id', profile.familyId);

      if (mounted) {
        setState(() {
          _familyMembers = List<Map<String, dynamic>>.from(res);
          _isLoadingMembers = false;
          if (_familyMembers.isNotEmpty) {
            final me = _familyMembers
                .where((m) => m['user_id'] == profile.userId)
                .toList();
            _selectedUserId = me.isNotEmpty
                ? me.first['user_id']
                : _familyMembers.first['user_id'];
            _selectedUserName = me.isNotEmpty
                ? me.first['profiles']['full_name']
                : _familyMembers.first['profile']['user_id'];
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching members: $e');
      if (mounted) setState(() => _isLoadingMembers = false);
    }
    if (_isEditing) {
      final zone = widget.existingZone!;

      _zoneNameController.text = zone['name'] ?? '';
      final radiusMeters = (zone['radius_meters'] as num?)?.toDouble() ?? 304.8;
      _radiusFeet = radiusMeters / 0.3048; // convert meters back to feet
      _alertOnEntry = zone['alert_on_entry'] ?? true;
      _alertOnExit = zone['alert_on_exit'] ?? true;
      _latitude = (zone['latitude'] as num?)?.toDouble();
      _longitude = (zone['longitude'] as num?)?.toDouble();
      if (zone['address'] != null) {
        _addressController.text = zone['address'] ?? '';
      }
      print(zone['assigned_user_name']);
      print(zone['assigned_user_id']);
      print("assigned_user_id");
      if (zone['assigned_user_name'] != null) {
        _selectedUserId = zone['assigned_user_id'];
        _selectedUserName = zone['assigned_user_name'];
      }
    } else {
      _fetchCurrentLocation();
    }
    _addressController.addListener(() {
      setState(() {});
    });
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json'
        '&lat=$lat'
        '&lon=$lng',
      );

      final res = await http.get(url, headers: {'User-Agent': 'wellcheck-app'});

      print("Status: ${res.statusCode}");
      print("Body: ${res.body}");

      if (res.statusCode != 200) {
        return;
      }

      final data = jsonDecode(res.body);

      if (mounted) {
        setState(() {
          _addressController.text = data["display_name"] ?? "";
        });
      }
    } catch (e, s) {
      print(e);
      print(s);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Safe Zone' : 'Create Safe Zone'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _handleSave,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _isEditing ? 'UPDATE' : 'SAVE',
                    style: const TextStyle(
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
            // Map preview
            Container(
              height: 250,
              width: double.infinity,
              color: Colors.grey.shade200,
              child: _latitude == null
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      children: [
                        // FlutterMap(
                        //   options: MapOptions(
                        //     initialCenter: LatLng(_latitude!, _longitude!),
                        //     initialZoom: 14.5,
                        //     interactionOptions: const InteractionOptions(
                        //       flags: InteractiveFlag.all,
                        //     ),
                        //     onPositionChanged: (point, b) {
                        //       print("onPositionChanged");
                        //
                        //       setState(() {
                        //         _latitude = point.center.latitude;
                        //         _longitude = point.center.longitude;
                        //       });
                        //     },
                        //     onTap: (tapPosition, point) {
                        //       print("ontappp");
                        //       setState(() {
                        //         _latitude = point.latitude;
                        //         _longitude = point.longitude;
                        //       });
                        //     },
                        //   ),
                        //   children: [
                        //     TileLayer(
                        //       urlTemplate:
                        //           'https://mt1.google.com/vt/lyrs=r&x={x}&y={y}&z={z}',
                        //       userAgentPackageName: 'com.anwiik.wellcheck',
                        //     ),
                        //     CircleLayer(
                        //       circles: [
                        //         CircleMarker(
                        //           point: LatLng(_latitude!, _longitude!),
                        //           color: ShieldColors.safeZoneGreen.withOpacity(
                        //             0.3,
                        //           ),
                        //           borderColor: ShieldColors.safeZoneGreen,
                        //           borderStrokeWidth: 2,
                        //           useRadiusInMeter: true,
                        //           radius: _radiusFeet * 0.3048,
                        //         ),
                        //       ],
                        //     ),
                        //     MarkerLayer(
                        //       markers: [
                        //         Marker(
                        //           point: LatLng(_latitude!, _longitude!),
                        //           width: 40,
                        //           height: 40,
                        //           child: const Icon(
                        //             Icons.location_on,
                        //             color: ShieldColors.activeTeal,
                        //             size: 40,
                        //           ),
                        //         ),
                        //       ],
                        //     ),
                        //   ],
                        // ),
                        FlutterMap(
                          mapController: mapController,

                          options: MapOptions(
                            initialCenter: LatLng(_latitude!, _longitude!),

                            initialZoom: 15,

                            onTap: (tapPosition, point) async {
                              setState(() {
                                _latitude = point.latitude;

                                _longitude = point.longitude;
                              });

                              await _reverseGeocode(
                                point.latitude,
                                point.longitude,
                              );
                            },

                            onPositionChanged: (position, hasGesture) {
                              if (!hasGesture) return;

                              final center = position.center;
                              if (center == null) return;

                              setState(() {
                                _latitude = center.latitude;
                                _longitude = center.longitude;
                              });

                              // Cancel previous timer
                              _debounce?.cancel();

                              // Wait 1 second after user stops moving
                              _debounce = Timer(
                                const Duration(seconds: 1),
                                () async {
                                  await _reverseGeocode(
                                    center.latitude,
                                    center.longitude,
                                  );
                                },
                              );
                            },
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
                                  color: ShieldColors.safeZoneGreen.withOpacity(
                                    0.3,
                                  ),
                                  borderColor: ShieldColors.safeZoneGreen,
                                  borderStrokeWidth: 2,
                                  useRadiusInMeter: true,
                                  radius: _radiusFeet * 0.3048,
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
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Assign To'),
                  if (_isLoadingMembers)
                    const Center(child: CircularProgressIndicator()),
                  if (_familyMembers.isEmpty)
                    Text("No Family member")
                  else if (_familyMembers.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: _selectedUserId,

                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: ShieldDesign.roundedTwelve,
                        ),
                        prefixIcon: const Icon(Icons.person),
                      ),
                      items: _familyMembers.map((m) {
                        final name = m['profiles']?['full_name'] ?? 'Unknown';

                        final role = m['role'];

                        return DropdownMenuItem<String>(
                          value: m['user_id'] as String,
                          child: Text(
                            '$name ($role)',
                            style: TextStyle(fontSize: 15),
                          ),
                        );
                      }).toList(),

                      onChanged: (val) {
                        final selectedMember = _familyMembers.firstWhere(
                          (m) => m['user_id'] == val,
                        );

                        setState(() {
                          _selectedUserId = val;

                          _selectedUserName =
                              selectedMember['profiles']?['full_name'] ??
                              'Unknown';
                        });
                      },

                      validator: (val) => val == null ? 'Required' : null,
                    ),
                  SizedBox(height: 20),
                  Column(
                    children: [
                      TextField(
                        controller: _addressController,

                        decoration: InputDecoration(
                          labelText: "Search address",
                          prefixIcon: Icon(Icons.search),

                          suffixIcon: _isSearchingAddress
                              ? Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : _addressController.text.isEmpty
                              ? SizedBox.shrink()
                              : GestureDetector(
                                  onTap: () {
                                    _addressController.clear();
                                    _addressSuggestions = [];
                                    setState(() {});
                                  },
                                  child: Icon(Icons.close),
                                ),

                          border: OutlineInputBorder(
                            borderRadius: ShieldDesign.roundedTwelve,
                          ),
                        ),

                        onChanged: (v) {
                          if (v.length > 2) {
                            _searchAddress(v);
                          } else {
                            setState(() {
                              _addressSuggestions = [];
                            });
                          }
                        },
                      ),

                      if (_addressSuggestions.isNotEmpty)
                        Container(
                          constraints: BoxConstraints(maxHeight: 250),

                          child: ListView.builder(
                            shrinkWrap: true,

                            itemCount: _addressSuggestions.length,

                            itemBuilder: (_, index) {
                              final item = _addressSuggestions[index];

                              return ListTile(
                                title: Text(item['display_name'], maxLines: 2),

                                onTap: () async {
                                  final lat = double.parse(item['lat']);

                                  final lng = double.parse(item['lon']);

                                  setState(() {
                                    _latitude = lat;

                                    _longitude = lng;

                                    _addressController.text =
                                        item['display_name'];

                                    _addressSuggestions = [];
                                  });

                                  mapController.move(LatLng(lat, lng), 15);
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
                    max: 5280,
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
                    onPressed: _isFetchingLocation
                        ? null
                        : _fetchCurrentLocation,
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
