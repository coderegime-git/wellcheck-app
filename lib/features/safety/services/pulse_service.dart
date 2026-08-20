import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/data/safety_repository.dart';
import 'package:well_check_v3/core/data/health_repository.dart';
import 'package:well_check_v3/core/data/location_processor.dart';
import 'package:well_check_v3/core/data/stitch_queue.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PulseService {
  static Future<void> initializeBackgroundService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    try {
      await dotenv.load(fileName: ".env");
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL'] ?? '',
        anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
      );
      await PulseService().broadcastPulse(null);
    } catch (e) {
      debugPrint('[iOS Background] Headless fetch failed: $e');
    }
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    // Load env for headless isolate
    await dotenv.load(fileName: ".env");

    // Initialize headless Supabase Client
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL'] ?? '',
      anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    );

    // Run continuous background ping for foreground tracking models
    Timer.periodic(const Duration(minutes: 15), (timer) async {
      await PulseService().broadcastPulse(null);
    });
  }

  final Map<String, bool> _lastZoneInsideStatus = {};

  Future<void> broadcastPulse(String? fallbackUserId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final familyId = prefs.getString('last_family_id');
      final persistentUserId = prefs.getString('last_user_id');
      final persistentUserName = prefs.getString('last_user_name');
      final effectiveUserId = persistentUserId ?? fallbackUserId;

      if (familyId == null || effectiveUserId == null) {
        debugPrint(
          'Pulse skipped: Missing identity (Family: $familyId, User: $effectiveUserId)',
        );
        return;
      }

      double? lat;
      double? lng;
      double? altitude;
      double speed = 0.0;

      try {
        LocationPermission permission = await Geolocator.checkPermission();

        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.deniedForever) {
          //await Geolocator.openAppSettings();
          //  showLocationDialog(context);

          return;
        }

        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );

          lat = position.latitude;
          lng = position.longitude;
          print(position.latitude);
          print(position.longitude);
        }
      } catch (e) {
        // await Geolocator.openAppSettings();

        debugPrint('Could not retrieve location: $e');
      }

      int level =
          100; // Safe default for simulators and aggressive background iOS policies
      try {
        final battery = Battery();
        level = await battery.batteryLevel;
      } catch (e) {
        debugPrint(
          'Battery info not available over isolate, using default: $e',
        );
      }

      final repo = SafetyRepository(Supabase.instance.client);
      final healthRepo = HealthRepository(Supabase.instance.client);
      final locProcessor = LocationProcessor(Supabase.instance.client);

      // Resolve semantic location (Geo-Shield Pro)
      final semanticLabel = await locProcessor.resolveSemanticLocation(
        familyId: familyId,
        latitude: lat ?? 0.0,
        longitude: lng ?? 0.0,
        altitude: altitude,
      );

      final pulsePayload = {
        'family_id': familyId,
        'user_id': effectiveUserId,
        'latitude': lat ?? 0.0,
        'longitude': lng ?? 0.0,
        'battery_level': level,
        'event_type': 'heartbeat',
        'user_name': persistentUserName,
        'metadata': {'semantic_location': semanticLabel},
      };

      // 1. Core Heartbeat with Offline-First Stitching
      try {
        await repo.submitPulse(
          familyId: familyId,
          latitude: lat ?? 0.0,
          longitude: lng ?? 0.0,
          batteryLevel: level,
          type: 'heartbeat',
        );

        // Success? Process any queued items
        await StitchQueue.processQueue(Supabase.instance.client);
      } catch (e) {
        debugPrint('System Offline: Queuing pulse locally.');
        await StitchQueue.enqueue('pulse', pulsePayload);

        // If this was a critical SOS (not yet implemented in this loop but planned),
        // we would start the mesh beacon here.
      }

      // Update Profile Semantic State
      if (semanticLabel != null) {
        try {
          await locProcessor.updateSemanticState(
            userId: effectiveUserId,
            familyId: familyId,
            latitude: lat ?? 0.0,
            longitude: lng ?? 0.0,
            altitude: altitude,
          );
        } catch (e) {
          debugPrint('Failed sync failed in background: $e');
        }
      }

      // 2. Biometric Sync (Physiological Awareness)
      try {
        print("syncVitals");
        final heartRateEnabled = prefs.getBool('priv_heartbeat') ?? true;
        print(heartRateEnabled);
        print("heartRateEnabledheartRateEnabled2");
        if (heartRateEnabled) {
          await healthRepo.syncVitals(
            userId: effectiveUserId,
            familyId: familyId,
            userName: persistentUserName ?? "",
          );
        } else {
          debugPrint('Heart rate sync disabled by user');
        }
      } catch (e) {
        print(e.toString());
        debugPrint('Biometric sync failed in background: $e');
      }
      //3. Driving Intelligence (Threshold: ~21 km/h or 6 m/s)
      if (speed > 6.0) {
        await repo.submitPulse(
          familyId: familyId,
          latitude: lat ?? 0.0,
          longitude: lng ?? 0.0,
          batteryLevel: level,
          type: 'driving',
        );
      }

      // 3. Campus Watch (Geofencing)

      // if (lat != null && lng != null) {
      //   final zones = await Supabase.instance.client
      //       .from('locations_safe_zones')
      //       .select()
      //       .eq('family_id', familyId);
      //
      //   for (final zone in zones) {
      //     print(zone);
      //     print("zonezone");
      //     final double zoneLat = zone['latitude'] != null
      //         ? zone['latitude'].toDouble()
      //         : 0;
      //     final double zoneLng = zone['longitude'] != null
      //         ? zone['longitude'].toDouble()
      //         : 0;
      //     final double radius = zone['radius_meters'] != null
      //         ? zone['radius_meters'].toDouble()
      //         : 100.0;
      //
      //     final distance = Geolocator.distanceBetween(
      //       lat,
      //       lng,
      //       zoneLat,
      //       zoneLng,
      //     );
      //     if (zone["assigned_user_id"] != effectiveUserId) continue;
      //     if (distance <= radius) {
      //       // User is inside this safe zone
      //       await repo.submitPulse(
      //         familyId: familyId,
      //         latitude: lat,
      //         longitude: lng,
      //         batteryLevel: level,
      //         type: 'safe_zone_enter',
      //       );
      //     } else {
      //       await repo.submitPulse(
      //         familyId: familyId,
      //         latitude: lat,
      //         longitude: lng,
      //         batteryLevel: level,
      //         type: 'safe_zone_exit',
      //       );
      //     }
      //   }
      // }

      if (lat == null || lng == null) return;

      final zones = await Supabase.instance.client
          .from('locations_safe_zones')
          .select()
          .eq('family_id', familyId)
          .eq('assigned_user_id', effectiveUserId);

      for (final zone in zones) {
        final zoneId = zone['id']?.toString();
        if (zoneId == null) continue;

        final latRaw = zone['latitude'];
        final lngRaw = zone['longitude'];

        // Skip zones with missing coordinates instead of defaulting to (0,0)
        if (latRaw == null || lngRaw == null) continue;

        final double zoneLat = latRaw.toDouble();
        final double zoneLng = lngRaw.toDouble();
        final double radius = zone['radius_meters'] != null
            ? zone['radius_meters'].toDouble()
            : 100.0;
        print("zonezone");
        print(zone);
        final bool alertOnEntry = zone['alert_on_entry'] == true;
        final bool alertOnExit = zone['alert_on_exit'] == true;
        final distance = Geolocator.distanceBetween(lat, lng, zoneLat, zoneLng);
        final bool isInside = distance <= radius;

        //final bool? wasInside = _lastZoneInsideStatus[zoneId];
        final bool? wasInside = await SafeZoneService.getLastZoneStatus(zoneId);

        // Only log when the status actually changes (or on first check)
        if (wasInside == isInside) {
          continue; // no state change, skip logging
        }

        _lastZoneInsideStatus[zoneId] = isInside;
        await SafeZoneService.setLastZoneStatus(zoneId, isInside);

        if (isInside && !alertOnEntry) continue;
        if (!isInside && !alertOnExit) continue;
        await repo.submitPulse(
          familyId: familyId,
          latitude: lat,
          longitude: lng,
          batteryLevel: level,
          type: isInside ? 'safe_zone_enter' : 'safe_zone_exit',
          safeZoneName: zone['name'],
        );
      }
      debugPrint('Pulse successfully transmitted for Family: $familyId');
    } catch (e) {
      debugPrint('Pulse failed entirely: $e');
    }
  }

  Position? _lastPosition;

  Future<void> updateLocation(String? fallbackUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    if (!isLoggedIn) {
      debugPrint('[Location] Skipping update — user logged out');
      return;
    }
    final familyId = prefs.getString('last_family_id');
    final persistentUserId = prefs.getString('last_user_id');
    final persistentUserName = prefs.getString('last_user_name');
    final persistentUserRole = prefs.getString('last_user_role');

    final effectiveUserId = persistentUserId ?? fallbackUserId;

    if (familyId == null || effectiveUserId == null) {
      return;
    }

    Position? position;

    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
      }

      if (position == null) return;

      // Check movement distance
      if (_lastPosition != null) {
        final distance = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );

        if (distance < 10) {
          // debugPrint("Location unchanged (${distance.toStringAsFixed(1)}m)");
          return;
        }
      }

      _lastPosition = position;

      int level = 100;
      try {
        final battery = Battery();
        level = await battery.batteryLevel;
      } catch (_) {}

      final response =
          await Supabase.instance.client.from('live_locations').upsert({
            'user_id': persistentUserId,
            'family_id': familyId,
            'user_name': persistentUserName,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'role': persistentUserRole,
            'battery_level': level,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id').select();

      debugPrint("UPSERT RESPONSE");
      debugPrint(response.toString());
    } catch (e) {
      debugPrint("updateLocation error: $e");
    }
  }
}

class SafeZoneService {
  static const String _prefsKeyPrefix = 'zone_status_';

  static Future<bool?> getLastZoneStatus(String zoneId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('$_prefsKeyPrefix$zoneId')) return null;
    return prefs.getBool('$_prefsKeyPrefix$zoneId');
  }

  static Future<void> setLastZoneStatus(String zoneId, bool isInside) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefsKeyPrefix$zoneId', isInside);
  }

  /// Call this when navigating to dashboard to reset all zone state
  static Future<void> clearZoneStatusCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefsKeyPrefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
