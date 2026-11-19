import 'dart:async';
import 'dart:math';
import 'dart:ui';
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

import '../../../config/constants.dart';
import '../../../services/driving_detection_motion.dart';
import '../../../services/life360_location_service.dart';
import '../../driving_detection/activity_recognition_service.dart';

@pragma('vm:entry-point')
class PulseService {
  final TripDetector _tripDetector = TripDetector();

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
      // await dotenv.load(fileName: ".env");
      // await Supabase.initialize(
      //   url: dotenv.env['SUPABASE_URL'] ?? '',
      //   anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
      // );
      if (Constants.kSupabaseUrl.isEmpty || Constants.kSupabaseUrl.isEmpty) {
        debugPrint('❌ Supabase environment variables missing');
        service.stopSelf();
        return false;
      }
      await Supabase.initialize(
        url: Constants.kSupabaseUrl,
        anonKey: Constants.kSupabaseAnonKey,
      );
      // final pulseService = PulseService();
      // StreamSubscription<Position>? positionSub;
      // positionSub =
      //     Geolocator.getPositionStream(
      //       locationSettings: const LocationSettings(
      //         accuracy: LocationAccuracy.high,
      //         distanceFilter: 15, // meters between updates
      //       ),
      //     ).listen((position) async {
      //       pulseService.handlePositionUpdate(position);
      //     });
      await PulseService().broadcastPulse(null);
    } catch (e) {
      debugPrint('[iOS Background] Headless fetch failed: $e');
    }
    return true;
  }

  //late final Life360LocationService locationService;
  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    // ---------------------------------------------------------
    // 1. Load environment first
    // ---------------------------------------------------------
    await dotenv.load(fileName: '.env');

    // final supabaseUrl = dotenv.env['SUPABASE_URL'];
    // final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
    final supabaseUrl = Constants.kSupabaseUrl;
    final supabaseAnonKey = Constants.kSupabaseAnonKey;
    if (supabaseUrl == null || supabaseAnonKey == null) {
      print('Supabase environment variables are missing');
      return;
    }

    // ---------------------------------------------------------
    // 2. Initialize Supabase in this background isolate
    // ---------------------------------------------------------
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

    print('Background Supabase initialized');

    // ---------------------------------------------------------
    // 3. Now it is safe to use Supabase.instance
    // ---------------------------------------------------------
    final supabase = Supabase.instance.client;
    final prefs = await SharedPreferences.getInstance();

    final userId = prefs.getString('last_user_id');
    final userName = prefs.getString('last_user_name') ?? 'Unknown';
    final familyId = prefs.getString('last_family_id');
    late final DrivingDetector drivingDetector;

    drivingDetector = DrivingDetector(
      supabase,
      onDrivingEvent:
          ({
            required String type,
            required String title,
            required String body,
          }) async {
            try {
              await supabase.functions.invoke(
                'driving-alert',
                body: {
                  'family_id': familyId,
                  'driver_user_id': userId,
                  'event_type': type,
                  'title': title,
                  'message': body,
                  'trip_id': drivingDetector.currentTripId,
                },
              );

              debugPrint('🔔 Driving alert sent: $type');
            } catch (e, stackTrace) {
              debugPrint('❌ Driving alert failed: $e');
              debugPrint('$stackTrace');
            }
          },
    );

    final pulseService = PulseService();

    final locationService = Life360LocationService(supabase);
    final activityService = ActivityRecognitionService();

    // ---------------------------------------------------------
    // 4. Load SharedPreferences
    // ---------------------------------------------------------

    final persistentUserRole = prefs.getString('last_user_role');

    if (familyId == null || userId == null) {
      print('Missing userId or familyId');
      return;
    }

    // ---------------------------------------------------------
    // 5. Don't start location sharing for leader
    // ---------------------------------------------------------
    // if (persistentUserRole == 'leader') {
    //   print('User is leader - background location sharing skipped');
    //   return;
    // }
    // await activityService.initialize(
    //   onActivityChanged: (activity, confidence) {
    //     drivingDetector.updateActivity(
    //       activity: activity,
    //       confidence: confidence,
    //     );
    //   },
    // );
    // ---------------------------------------------------------
    // 6. Start Life360 location sharing
    // ---------------------------------------------------------
    //  await locationService.startSharingMyLocation(name: userName);

    // ---------------------------------------------------------
    // 7. Start GPS stream AFTER Supabase is initialized
    // ---------------------------------------------------------
    // StreamSubscription<Position>? positionSub;
    //
    // positionSub =
    //     Geolocator.getPositionStream(
    //       locationSettings: const LocationSettings(
    //         accuracy: LocationAccuracy.high,
    //         distanceFilter: 50,
    //       ),
    //     ).listen(
    //       (position) async {
    //         try {
    //           print(
    //             'Background location: '
    //             '${position.latitude}, ${position.longitude}',
    //           );
    //
    //           // Pulse/location handling
    //           await pulseService.handlePositionUpdate(position);
    //
    //           // Update location
    //           await pulseService.updateLocation(userId);
    //
    //           // Driving detection
    //           await drivingDetector.feed(
    //             position,
    //             userId: userId,
    //             familyId: familyId,
    //           );
    //         } catch (e, stackTrace) {
    //           print('Background location error: $e');
    //           print(stackTrace);
    //         }
    //       },
    //       onError: (error) {
    //         print('Location stream error: $error');
    //       },
    //     );
    // await locationService.startSharingMyLocation(
    //   name: userName,
    //   onPosition: (position) async {
    //     // Pulse
    //     await pulseService.handlePositionUpdate(position);
    //     await pulseService.updateLocation(userId);
    //
    //     // Driving detection
    //     await drivingDetector.feed(
    //       position,
    //       userId: userId,
    //       familyId: familyId,
    //     );
    //   },
    // );
    // ---------------------------------------------------------
    // 8. Existing 15-minute heartbeat
    // ---------------------------------------------------------
    Timer.periodic(const Duration(minutes: 15), (timer) async {
      try {
        await PulseService().broadcastPulse(null);
      } catch (e) {
        print('Pulse error: $e');
      }
    });

    // ---------------------------------------------------------
    // 9. Stop service handler
    // ---------------------------------------------------------
    service.on('stopService').listen((event) async {
      //  await positionSub?.cancel();
      service.stopSelf();
    });
  }

  // @pragma('vm:entry-point')
  // static void onStart(ServiceInstance service) async {
  //   // Load env for headless isolate
  //   DartPluginRegistrant.ensureInitialized();
  //   final drivingDetector = DrivingDetector(Supabase.instance.client);
  //
  //   final pulseService = PulseService();
  //   StreamSubscription<Position>? positionSub;
  //   positionSub =
  //       Geolocator.getPositionStream(
  //         locationSettings: const LocationSettings(
  //           accuracy: LocationAccuracy.high,
  //           distanceFilter: 50, // meters between updates
  //         ),
  //       ).listen((position) async {
  //         print("bakground");
  //         await pulseService.handlePositionUpdate(position);
  //         final prefs = await SharedPreferences.getInstance();
  //         final userId = prefs.getString('last_user_id');
  //         await pulseService.updateLocation(userId);
  //
  //         final familyId = prefs.getString('last_family_id');
  //         if (userId != null && familyId != null) {
  //           await drivingDetector.feed(
  //             position,
  //             userId: userId,
  //             familyId: familyId,
  //           );
  //         }
  //       });
  //
  //   await dotenv.load(fileName: ".env");
  //   print("sasasasas");
  //   //
  //
  //   // Initialize headless Supabase Client
  //   await Supabase.initialize(
  //     url: dotenv.env['SUPABASE_URL'] ?? '',
  //     anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  //   );
  //   final locationService = Life360LocationService(
  //     Supabase.instance.client,
  //   ); // ← local var
  //
  //   final prefs = await SharedPreferences.getInstance();
  //   final userName = prefs.getString('last_user_name') ?? 'Unknown';
  //   final familyId = prefs.getString('last_family_id');
  //
  //   if (familyId == null) return;
  //   final persistentUserRole = prefs.getString('last_user_role');
  //   if (persistentUserRole == "leader") return;
  //   // ← don't hardcodep
  //     await locationService.startSharingMyLocation(name: userName);
  //   // Keep your existing 15-min heartbeat for battery/vitals/geofence sync
  //   Timer.periodic(const Duration(minutes: 15), (timer) async {
  //     await PulseService().broadcastPulse(null);
  //   });
  //   // Run continuous background ping for foreground tracking models
  //   // Timer.periodic(const Duration(minutes: 15), (timer) async {
  //   //   await PulseService().broadcastPulse(null);
  //   // });
  //   service.on('stopService').listen((event) {
  //     positionSub?.cancel();
  //     service.stopSelf();
  //   });
  // }

  final Map<String, bool> _lastZoneInsideStatus = {};
  Position? _lastPulsePosition;
  DateTime? _lastPulseTime;

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
    // final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    // if (!isLoggedIn) {
    //   debugPrint('[Location] Skipping update — user logged out');
    //   return;
    // }
    final supabase = Supabase.instance.client;

    final session = supabase.auth.currentSession;
    final user = session?.user;
    // final isLoggedIn = user != null;
    final isLoggedIn = session != null;
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
            distanceFilter: 10,
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

  Future<void> handlePositionUpdate(Position position) async {
    final speedKmh = (position.speedAccuracy <= 5 && position.speed >= 0)
        ? position.speed * 3.6
        : 0.0; // ignore unreliable stream readings; getPositionStream is usually accurate
    print(speedKmh);
    print("hhghghgh");
    final event = _tripDetector.update(position, speedKmh);
    print(event);

    if (event == null) return;
    print(event);
    print("hhghghgh11");
    final prefs = await SharedPreferences.getInstance();
    final familyId = prefs.getString('last_family_id');
    final userId = prefs.getString('last_user_id');
    if (familyId == null || userId == null) return;

    final repo = SafetyRepository(Supabase.instance.client);
    int level = 100;
    try {
      level = await Battery().batteryLevel;
    } catch (_) {}
    print(event.type);
    print("event.type");
    switch (event.type) {
      case TripEventType.start:
        await repo.submitPulse(
          familyId: familyId,
          latitude: position.latitude,
          longitude: position.longitude,
          batteryLevel: level,
          type: event.mode == TripMode.driving
              ? 'driving_start'
              : 'biking_start',
        );
        break;
      case TripEventType.end:
        await repo.submitPulse(
          familyId: familyId,
          latitude: position.latitude,
          longitude: position.longitude,
          batteryLevel: level,
          type: event.mode == TripMode.driving ? 'driving_end' : 'biking_end',
          // if submitPulse doesn't accept extra metadata, route these through StitchQueue's payload map instead
        );
        debugPrint(
          'Trip ended: mode=${event.mode}, duration=${event.durationSeconds}s, '
          'distance=${event.distanceMeters?.toStringAsFixed(0)}m, maxSpeed=${event.maxSpeedKmh?.toStringAsFixed(1)}km/h',
        );
        break;
      case TripEventType.modeChange:
        await repo.submitPulse(
          familyId: familyId,
          latitude: position.latitude,
          longitude: position.longitude,
          batteryLevel: level,
          type: event.mode == TripMode.driving ? 'driving' : 'biking',
        );
        break;
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

enum TripMode { still, walking, biking, driving }

class TripDetector {
  static const double _walkingKmh = 7.0;
  static const double _bikingKmh = 25.0;
  static const int _hysteresisCount =
      3; // consecutive readings to confirm a switch

  TripMode _currentMode = TripMode.still;
  TripMode? _pendingMode;
  int _pendingCount = 0;

  DateTime? _tripStartTime;
  Position? _tripStartPosition;
  double _tripMaxSpeedKmh = 0;

  TripMode get currentMode => _currentMode;

  bool get isInTrip =>
      _currentMode == TripMode.biking || _currentMode == TripMode.driving;

  TripMode _classify(double speedKmh) {
    if (speedKmh < 1.5) return TripMode.still;
    if (speedKmh < _walkingKmh) return TripMode.walking;
    if (speedKmh < _bikingKmh) return TripMode.biking;
    return TripMode.driving;
  }

  /// Returns a TripEvent if a confirmed state change happened, else null.
  TripEvent? update(Position position, double speedKmh) {
    final classified = _classify(speedKmh);

    if (classified == _currentMode) {
      _pendingMode = null;
      _pendingCount = 0;
      if (isInTrip && speedKmh > _tripMaxSpeedKmh) _tripMaxSpeedKmh = speedKmh;
      return null;
    }

    if (_pendingMode == classified) {
      _pendingCount++;
    } else {
      _pendingMode = classified;
      _pendingCount = 1;
    }

    if (_pendingCount < _hysteresisCount) {
      print('pending: $classified count: $_pendingCount');
      return null;
    }
    // Confirmed state change
    final previousMode = _currentMode;
    _currentMode = classified;
    _pendingMode = null;
    _pendingCount = 0;

    final wasInTrip =
        previousMode == TripMode.biking || previousMode == TripMode.driving;
    final nowInTrip = isInTrip;

    if (!wasInTrip && nowInTrip) {
      _tripStartTime = DateTime.now();
      _tripStartPosition = position;
      _tripMaxSpeedKmh = speedKmh;
      return TripEvent(
        type: TripEventType.start,
        mode: _currentMode,
        position: position,
      );
    }

    if (wasInTrip && !nowInTrip) {
      final event = TripEvent(
        type: TripEventType.end,
        mode: previousMode,
        position: position,
        durationSeconds: _tripStartTime != null
            ? DateTime.now().difference(_tripStartTime!).inSeconds
            : null,
        distanceMeters: (_tripStartPosition != null)
            ? Geolocator.distanceBetween(
                _tripStartPosition!.latitude,
                _tripStartPosition!.longitude,
                position.latitude,
                position.longitude,
              )
            : null,
        maxSpeedKmh: _tripMaxSpeedKmh,
      );
      _tripStartTime = null;
      _tripStartPosition = null;
      _tripMaxSpeedKmh = 0;
      return event;
    }

    // Mode changed but stayed "in trip" (e.g. biking -> driving)
    return TripEvent(
      type: TripEventType.modeChange,
      mode: _currentMode,
      position: position,
    );
  }
}

enum TripEventType { start, end, modeChange }

class TripEvent {
  final TripEventType type;
  final TripMode mode;
  final Position position;
  final int? durationSeconds;
  final double? distanceMeters;
  final double? maxSpeedKmh;

  TripEvent({
    required this.type,
    required this.mode,
    required this.position,
    this.durationSeconds,
    this.distanceMeters,
    this.maxSpeedKmh,
  });
}
