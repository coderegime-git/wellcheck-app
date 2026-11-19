// life360_location_service.dart
//
// Two responsibilities:
//   1. Track THIS device's GPS (lat/lng/speed/heading) and push updates
//      to your backend so other members can see you.
//   2. Listen for ALL members' latest locations and expose them as a
//      Stream<List<MemberLocation>> that Life360MapScreen can consume directly.
//
// Dependencies (pubspec.yaml):
//   geolocator: ^13.0.0
//   supabase_flutter: ^2.8.0   // swap for your own backend client if different
//
// Backend table assumed (Supabase/Postgres), adjust names to match yours:
//
//   create table member_locations (
//     user_id      uuid primary key references auth.users(id),
//     name         text not null,
//     avatar_url   text,
//     color_hex    text,               -- e.g. '#2196F3'
//     latitude     double precision not null,
//     longitude    double precision not null,
//     speed_kmh    double precision not null default 0,
//     heading      double precision,
//     battery_pct  double precision,
//     address      text,
//     status       text,               -- 'driving' | 'walking' | 'stopped'
//     updated_at   timestamptz not null default now()
//   );
//
//   -- enable Realtime on this table in Supabase dashboard, and RLS policies
//   -- so members can only read locations within their own group/org.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/driving_detection/activity_recognition_service.dart';
import '../features/driving_detection/life360_screen.dart';

class Life360LocationService {
  Life360LocationService(this._supabase);

  final SupabaseClient _supabase;
  StreamSubscription<Position>? _gpsSub;
  RealtimeChannel? _channel;
  final ActivityRecognitionService _activityService =
      ActivityRecognitionService();

  // ---------------------------------------------------------------------
  // 1. CAPTURE + PUSH this device's own location
  // ---------------------------------------------------------------------

  /// Call once (e.g. in initState of your home screen, or a background
  /// service) after checking/requesting location permission.

  void stopSharingMyLocation() {
    _gpsSub?.cancel();
    _gpsSub = null;
  }

  DateTime? _lastProcessed;
  Position? _lastPos;

  static const _minInterval = Duration(seconds: 10);
  static const _minMoveMeters = 15.0;

  bool _shouldProcess(Position pos) {
    final now = DateTime.now();
    if (_lastProcessed != null &&
        now.difference(_lastProcessed!) < _minInterval) {
      return false;
    }
    if (_lastPos != null) {
      final d = Geolocator.distanceBetween(
        _lastPos!.latitude,
        _lastPos!.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (d < _minMoveMeters && pos.speed < 1.0)
        return false; // stationary jitter
    }
    _lastProcessed = now;
    _lastPos = pos;
    return true;
  }

  Future<void> processPosition(
    Position pos, {
    required String name,
    double? batteryPct,
  }) async {
    await _pushMyPosition(pos, name: name, batteryPct: batteryPct);
    await _checkSavedLocations(pos);
  }

  // Future<void> startSharingMyLocation({
  //   required String name,
  //   double? batteryPct,
  //   Future<void> Function(Position position)? onPosition,
  // }) async {
  //   final permission = await _ensurePermission();
  //   if (!permission) return;
  //
  //   // Start activity recognition
  //   // await _activityService.initialize(
  //   //   onActivityChanged: (activity, confidence) {
  //   //     debugPrint(
  //   //       '📱 Activity: $activity '
  //   //       '| confidence=$confidence%',
  //   //     );
  //   //
  //   //     // You can also pass this to DrivingDetector here
  //   //     // if you want the detector to know the current activity.
  //   //   },
  //   // );
  //
  //   const settings = LocationSettings(
  //     accuracy: LocationAccuracy.high,
  //     distanceFilter: 15,
  //   );
  //
  //   _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
  //     (pos) async {
  //       try {
  //         // Existing dashboard / leader location update
  //         await _pushMyPosition(pos, name: name, batteryPct: batteryPct);
  //
  //         // Give the same GPS position to other services
  //         if (onPosition != null) {
  //           await onPosition(pos);
  //         }
  //       } catch (e, stackTrace) {
  //         debugPrint('Location update error: $e');
  //         debugPrint('$stackTrace');
  //       }
  //     },
  //     onError: (error) {
  //       debugPrint('GPS stream error: $error');
  //     },
  //   );
  // }

  Future<void> startSharingMyLocation({
    required String name,
    double? batteryPct,
    Future<void> Function(Position position)? onPosition,
  }) async {
    final permission = await _ensurePermission();
    if (!permission) {
      debugPrint('Location permission not granted');
      return;
    }

    // Prevent duplicate streams.
    await _gpsSub?.cancel();
    _gpsSub = null;

    late final LocationSettings settings;

    if (Platform.isIOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.best,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 15,
        timeLimit: const Duration(seconds: 15),
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
        intervalDuration: const Duration(seconds: 10),
        forceLocationManager: false,
        // foregroundNotificationConfig: const ForegroundNotificationConfig(
        //   notificationTitle: 'Well Check',
        //   notificationText: 'Location tracking is active',
        //   // notificationIcon: AndroidResource(
        //   //   name: 'ic_stat_notify',
        //   //   defType: 'drawable',
        //   // ),
        //   enableWakeLock: true,
        //   setOngoing: true,
        // ),
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      );
    }

    _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (Position pos) async {
        try {
          //  await _pushMyPosition(pos, name: name, batteryPct: batteryPct);
          // await _checkSavedLocations(pos);
          if (!_shouldProcess(pos)) return;

          if (onPosition != null) {
            await onPosition(pos);
          }
        } catch (e, stackTrace) {
          debugPrint('Location update error: $e');
          debugPrint('$stackTrace');
        }
      },
      onError: (error) {
        debugPrint('GPS stream error: $error');
      },
    );
  }

  Future<void> _checkSavedLocations(Position position) async {
    final userId = _supabase.auth.currentUser?.id;

    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    final familyId = prefs.getString('last_family_id');

    if (familyId == null || familyId.isEmpty) return;

    try {
      final places = await _supabase
          .from('saved_places')
          .select()
          .eq('family_id', familyId);

      for (final place in places) {
        final latitude = (place['latitude'] as num?)?.toDouble();
        final longitude = (place['longitude'] as num?)?.toDouble();

        if (latitude == null || longitude == null) continue;

        final radius = (place['radius_m'] as num?)?.toDouble() ?? 250;

        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          latitude,
          longitude,
        );

        final isInside = distance <= radius;

        await _updateSavedLocationPresence(
          familyId: familyId,
          userId: userId,
          place: place,
          isInside: isInside,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Saved location detection error: $e');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _updateSavedLocationPresence({
    required String familyId,
    required String userId,
    required Map<String, dynamic> place,
    required bool isInside,
  }) async {
    final placeId = place['id']?.toString();

    if (placeId == null || placeId.isEmpty) return;

    final placeName =
        place['label']?.toString() ??
        place['name']?.toString() ??
        'Saved location';

    try {
      final existing = await _supabase
          .from('saved_location_presence')
          .select('id, is_inside')
          .eq('user_id', userId)
          .eq('saved_place_id', placeId)
          .maybeSingle();

      // First GPS reading for this place.
      if (existing == null) {
        // await _supabase.from('saved_location_presence').insert({
        //   'family_id': familyId,
        //   'user_id': userId,
        //   'saved_place_id': placeId,
        //   'is_inside': isInside,
        //   if (isInside) 'entered_at': DateTime.now().toIso8601String(),
        //   'updated_at': DateTime.now().toIso8601String(),
        // });
        final now = DateTime.now().toUtc().toIso8601String();

        await _supabase
            .from('saved_location_presence')
            .upsert(
              {
                'family_id': familyId,
                'user_id': userId,
                'saved_place_id': placeId,
                'is_inside': isInside,
                if (isInside) 'entered_at': now,
                'updated_at': now,
              },
              onConflict: 'user_id,saved_place_id',
              ignoreDuplicates: true,
            );

        // If the first location is already inside,
        // send the arrival notification.
        if (isInside) {
          await _sendSavedLocationNotification(
            familyId: familyId,
            userId: userId,
            placeId: placeId,
            placeName: placeName,
            eventType: 'arrived',
          );
        }

        return;
      }

      final previousInside = existing['is_inside'] as bool? ?? false;

      // Nothing changed.
      if (previousInside == isInside) {
        return;
      }

      // OUTSIDE -> INSIDE
      if (!previousInside && isInside) {
        await _supabase
            .from('saved_location_presence')
            .update({
              'is_inside': true,
              'entered_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', existing['id']);

        await _sendSavedLocationNotification(
          familyId: familyId,
          userId: userId,
          placeId: placeId,
          placeName: placeName,
          eventType: 'arrived',
        );
      }
      // INSIDE -> OUTSIDE
      else if (previousInside && !isInside) {
        await _supabase
            .from('saved_location_presence')
            .update({
              'is_inside': false,
              'left_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', existing['id']);

        await _sendSavedLocationNotification(
          familyId: familyId,
          userId: userId,
          placeId: placeId,
          placeName: placeName,
          eventType: 'left',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Saved location presence error: $e');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _sendSavedLocationNotification({
    required String familyId,
    required String userId,
    required String placeId,
    required String placeName,
    required String eventType,
  }) async {
    try {
      print("asdfghj");
      final prefs = await SharedPreferences.getInstance();

      final userName = prefs.getString('last_user_name') ?? 'A family member';

      final bool arrived = eventType == 'arrived';

      await _supabase.functions.invoke(
        'saved-location-notification',
        body: {
          'family_id': familyId,
          'user_id': userId,
          'user_name': userName,
          'place_id': placeId,
          'place_name': placeName,
          'event_type': eventType,
          'title': arrived ? 'Location Reached' : 'Location Left',
          'message': arrived
              ? '$userName reached $placeName'
              : '$userName left $placeName',
        },
      );
    } catch (e, stackTrace) {
      debugPrint('Saved location notification error: $e');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _pushMyPosition(
    Position pos, {
    required String name,
    double? batteryPct,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final speedKmh = (pos.speed.isFinite ? pos.speed : 0) * 3.6;
    final prefs = await SharedPreferences.getInstance();
    final familyId = prefs.getString('last_family_id');
    final avatar = prefs.getString('last_user_profile');

    await _supabase.from('member_locations').upsert({
      'user_id': userId,
      'family_id': familyId,
      'name': name,
      'avatar': avatar,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'speed_kmh': speedKmh,
      'heading': pos.heading,
      'battery_pct': batteryPct,
      'status': speedKmh < 1
          ? 'stopped'
          : speedKmh < 8
          ? 'walking'
          : 'driving',
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> reportMotionPermissionStatus(bool enabled) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _supabase
        .from('member_locations')
        .update({
          'motion_permission_enabled': enabled,
          'permission_changed_at': DateTime.now().toIso8601String(),
        })
        .eq('user_id', userId);
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  // ---------------------------------------------------------------------
  // 2. LISTEN for everyone's latest locations -> feed Life360MapScreen
  // ---------------------------------------------------------------------

  final _membersController = StreamController<List<MemberLocation>>.broadcast();

  /// Stream of the full member list, updated live as anyone moves.
  /// Pass this straight into a StreamBuilder<List<MemberLocation>> that
  /// builds Life360MapScreen.
  Stream<List<MemberLocation>> watchMembers(String familyId) {
    _loadInitial(familyId);
    _channel ??= _supabase
        .channel('member_locations_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'member_locations',
          filter: PostgresChangeFilter(
            // ← add
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (_) => _loadInitial(familyId),
        )
        .subscribe();
    return _membersController.stream;
  }

  //
  Future<void> _loadInitial(String familyId) async {
    final rows = await _supabase
        .from('member_locations')
        .select()
        .eq('family_id', familyId); // ← add
    _membersController.add(rows.map(_rowToMemberLocation).toList());
  }

  MemberLocation _rowToMemberLocation(Map<String, dynamic> row) {
    return MemberLocation(
      id: row['user_id'] as String,
      name: (row['name'] as String?) ?? 'Member',
      avatarUrl: row['avatar'] as String?,
      color: _colorFromHex(row['color_hex'] as String?),
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
      speedKmh: (row['speed_kmh'] as num?)?.toDouble() ?? 0,
      headingDegrees: (row['heading'] as num?)?.toDouble(),
      batteryPercent: (row['battery_pct'] as num?)?.toDouble(),
      address: row['address'] as String?,
      status: _statusFromString(row['status'] as String?),
      lastUpdated:
          DateTime.tryParse(row['updated_at'] as String? ?? '') ??
          DateTime.now(),
      motionPermissionEnabled:
          (row['motion_permission_enabled'] as bool?) ?? true,
      // ← add
      permissionChangedAt: DateTime.tryParse(
        // ← add
        row['permission_changed_at'] as String? ?? '',
      ),
    );
  }

  Color _colorFromHex(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.blue;
    final clean = hex.replaceFirst('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  }

  MovementStatus _statusFromString(String? s) {
    switch (s) {
      case 'driving':
        return MovementStatus.driving;
      case 'walking':
        return MovementStatus.walking;
      case 'stopped':
        return MovementStatus.stopped;
      default:
        return MovementStatus.unknown;
    }
  }

  void dispose() {
    _gpsSub?.cancel();
    _channel?.unsubscribe();
    _membersController.close();
  }
}
