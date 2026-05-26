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

  // Send a pulse broadcast directly
  Future<void> broadcastPulse(String? fallbackUserId) async {
    try {
      debugPrint('heartbeatheartbeatheartbeat');
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
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );
          lat = position.latitude;
          lng = position.longitude;
          speed = position.speed; // Speed in m/s
          altitude = position.altitude;
        }
      } catch (e) {
        await Geolocator.openLocationSettings();

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
        await healthRepo.syncVitals(
          userId: effectiveUserId,
          familyId: familyId,
          userName: persistentUserName ?? "",
        );
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
      if (lat != null && lng != null) {
        final zones = await Supabase.instance.client
            .from('locations_safe_zones')
            .select()
            .eq('family_id', familyId);

        for (final zone in zones) {
          final double zoneLat = zone['latitude'] != null
              ? zone['latitude'].toDouble()
              : 0;
          final double zoneLng = zone['longitude'] != null
              ? zone['longitude'].toDouble()
              : 0;
          final double radius = zone['radius_meters'] != null
              ? zone['radius_meters'].toDouble()
              : 100.0;

          final distance = Geolocator.distanceBetween(
            lat,
            lng,
            zoneLat,
            zoneLng,
          );
          if (distance <= radius) {
            // User is inside this safe zone
            await repo.submitPulse(
              familyId: familyId,
              latitude: lat,
              longitude: lng,
              batteryLevel: level,
              type: 'safe_zone_enter',
            );
          }
        }
      }

      debugPrint('Pulse successfully transmitted for Family: $familyId');
    } catch (e) {
      debugPrint('Pulse failed entirely: $e');
    }
  }
}
