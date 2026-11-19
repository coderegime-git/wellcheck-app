// life360_driving_detection.dart  (v2 — replaces the previous version)
//
// Now tracks the individual metrics Life360's driving report shows:
//   - Top speed
//   - Hard braking events
//   - Rapid acceleration events
//   - Speeding events + total time spent speeding
//   - Distracted driving events (phone use while driving — see
//     DistractedDrivingMonitor below, which runs in the FOREGROUND isolate,
//     not here, since screen/app state isn't observable from a background
//     service isolate)

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:activity_recognition_flutter/activity_recognition_flutter.dart'
    as reg;
import 'package:geocoding/geocoding.dart';

enum DrivingState { stopped, driving }

class DrivingDetector {
  DrivingDetector(
    this._supabase, {
    this.startThresholdKmh = 10,
    this.stopThresholdKmh = 7,
    this.sustainedReadings = 2,
    this.hardBrakeThresholdKmhPerSec = 8,
    this.rapidAccelThresholdKmhPerSec = 8,
    this.speedingLimitKmh = 80,
    this.onDrivingEvent,
  });

  final Future<void> Function({
    required String type,
    required String title,
    required String body,
  })?
  onDrivingEvent;
  final SupabaseClient _supabase;
  final double startThresholdKmh;
  final double stopThresholdKmh;
  final int sustainedReadings;
  final double hardBrakeThresholdKmhPerSec;
  final double rapidAccelThresholdKmhPerSec;
  final double speedingLimitKmh;

  DrivingState _state = DrivingState.stopped;
  int _aboveCount = 0;
  int _belowCount = 0;

  String? _currentTripId;
  double _maxSpeedKmh = 0;
  double _distanceKm = 0;
  int _hardBrakeCount = 0;
  int _rapidAccelCount = 0;
  int _speedingEvents = 0;
  int _speedingDurationSec = 0;
  bool _wasSpeeding = false;
  Position? _lastPosition;
  double? _lastSpeedKmh;
  DateTime? _lastReadingTime;
  final List<double> _speedSamples = [];
  DateTime? _belowThresholdSince;

  DrivingState get state => _state;

  String? get currentTripId => _currentTripId;
  bool _activityInVehicle = false;
  int _activityConfidence = 0;

  void updateActivity({
    required reg.ActivityType activity,
    required int confidence,
  }) {
    _activityConfidence = confidence;

    _activityInVehicle =
        activity == reg.ActivityType.inVehicle && confidence >= 60;

    debugPrint(
      '🚗 Driving activity: $activity '
      '| confidence=$confidence '
      '| inVehicle=$_activityInVehicle',
    );
  }

  Future<void> _notifyDrivingEvent({
    required String type,
    required String title,
    required String body,
  }) async {
    try {
      if (onDrivingEvent == null) return;

      await onDrivingEvent!(type: type, title: title, body: body);
    } catch (e, stackTrace) {
      debugPrint('❌ Driving notification error: $e');
      debugPrint('$stackTrace');
    }
  }

  final int speedingDurationThresholdSec = 30;

  DateTime? _speedingStartedAt;
  bool _currentSpeedingEventCounted = false;

  Future<void> feed(
    Position pos, {
    required String userId,
    required String familyId,
  }) async {
    final speedKmh = (pos.speed.isFinite ? pos.speed : 0) * 3.6;
    final now = DateTime.now();
    double dtSeconds = 0;

    if (_state == DrivingState.driving &&
        _lastSpeedKmh != null &&
        _lastReadingTime != null) {
      dtSeconds = now.difference(_lastReadingTime!).inMilliseconds / 1000;
      if (dtSeconds > 0) {
        final deltaKmh = (_lastSpeedKmh! - speedKmh) / dtSeconds;
        // Positive delta = slowing down = braking. Negative = speeding up.
        if (deltaKmh >= hardBrakeThresholdKmhPerSec) {
          _hardBrakeCount++;
          await _notifyDrivingEvent(
            type: 'hard_braking',
            title: 'Hard Braking Alert',
            body: 'A hard braking event was detected.',
          );
        } else if (-deltaKmh >= rapidAccelThresholdKmhPerSec) {
          _rapidAccelCount++;
          await _notifyDrivingEvent(
            type: 'rapid_acceleration',
            title: 'Rapid Acceleration Alert',
            body: 'A rapid acceleration event was detected.',
          );
        }
      }

      // Speeding: count a new "event" each time we cross into speeding,
      // and accumulate total seconds spent over the limit.
      // final isSpeedingNow = speedKmh > speedingLimitKmh;
      // if (isSpeedingNow) {
      //   _speedingStartedAt ??= now;
      //   if (!_wasSpeeding) _speedingEvents++;
      //
      //   if (!_wasSpeeding) _speedingEvents++;
      //   await _notifyDrivingEvent(
      //     type: 'speeding',
      //     title: 'Speeding Alert',
      //     body: '$speedKmh km/h detected while driving.',
      //   );
      //   _speedingDurationSec += dtSeconds.round();
      // }
      // _wasSpeeding = isSpeedingNow;
      // Speeding: count only after continuously exceeding 80 km/h for 30 seconds.
      final isSpeedingNow = speedKmh > speedingLimitKmh;

      if (isSpeedingNow) {
        // Start timing when the vehicle first crosses the limit.
        _speedingStartedAt ??= now;

        final speedingSeconds = now.difference(_speedingStartedAt!).inSeconds;

        // Count this event only once after 30 continuous seconds.
        if (!_currentSpeedingEventCounted &&
            speedingSeconds >= speedingDurationThresholdSec) {
          _speedingEvents++;
          _currentSpeedingEventCounted = true;

          await _notifyDrivingEvent(
            type: 'speeding',
            title: 'Speeding Alert',
            body:
                'Speed remained above ${speedingLimitKmh.toStringAsFixed(0)} km/h for at least $speedingDurationThresholdSec seconds.',
          );

          debugPrint('⚠️ Speeding event counted: $_speedingEvents');
        }

        // Accumulate time above the limit.
        if (dtSeconds > 0) {
          _speedingDurationSec += dtSeconds.round();
        }
      } else {
        // At or below the limit ends the current continuous speeding period.
        _speedingStartedAt = null;
        _currentSpeedingEventCounted = false;
      }

      _wasSpeeding = isSpeedingNow;
    }
    _lastSpeedKmh = speedKmh;
    _lastReadingTime = now;

    // if (speedKmh >= startThresholdKmh) {
    //   _aboveCount++;
    //   _belowCount = 0;
    // } else if (speedKmh <= stopThresholdKmh) {
    //   _belowCount++;
    //   _aboveCount = 0;
    // }
    if (speedKmh >= startThresholdKmh) {
      _aboveCount++;
      _belowCount = 0;

      debugPrint(
        '🚗 SPEED ABOVE: $speedKmh | above=$_aboveCount | below=$_belowCount',
      );
    } else if (speedKmh <= stopThresholdKmh) {
      _belowCount++;
      _aboveCount = 0;

      debugPrint(
        '🛑 SPEED BELOW: $speedKmh | below=$_belowCount/$sustainedReadings | state=$_state',
      );
    } else {
      _belowCount = 0;
      _aboveCount = 0;
      debugPrint(
        '⚠️ SPEED BETWEEN THRESHOLDS: $speedKmh | '
        'stop=$stopThresholdKmh | start=$startThresholdKmh',
      );
    }
    if (_state == DrivingState.stopped && _aboveCount >= sustainedReadings) {
      await _startTrip(pos, userId: userId, familyId: familyId);
    }
    // if (_state == DrivingState.driving) {
    //   if (speedKmh <= stopThresholdKmh) {
    //     _belowThresholdSince ??= now;
    //
    //     final stoppedFor = now.difference(_belowThresholdSince!).inSeconds;
    //
    //     debugPrint(
    //       '🛑 LOW SPEED: $speedKmh km/h '
    //       '| stoppedFor=${stoppedFor}s',
    //     );
    //
    //     if (stoppedFor >= 20) {
    //       debugPrint('⏹️ ENDING TRIP AFTER 20 SEC STOP');
    //       await _notifyDrivingEvent(
    //         type: 'trip_completed',
    //         title: 'Trip Completed',
    //         body:
    //             'Trip completed. Distance: ${_distanceKm.toStringAsFixed(1)} km.',
    //       );
    //       await _endTrip(pos);
    //       return;
    //     }
    //   } else {
    //     _belowThresholdSince = null;
    //   }
    // }
    // Check whether the current trip should end.
    if (_state == DrivingState.driving) {
      const double stopSpeedKmh = 2.0;
      const int stopDurationSeconds = 20;

      if (speedKmh <= stopSpeedKmh) {
        _belowThresholdSince ??= now;

        final stoppedFor = now.difference(_belowThresholdSince!).inSeconds;

        debugPrint(
          '🛑 TRIP STOP CHECK: '
          'speed=${speedKmh.toStringAsFixed(1)} km/h, '
          'stoppedFor=$stoppedFor seconds',
        );

        if (stoppedFor >= stopDurationSeconds) {
          debugPrint('⏹️ ENDING TRIP AFTER 20 SECONDS');

          await _notifyDrivingEvent(
            type: 'trip_completed',
            title: 'Trip Completed',
            body:
                'Trip completed. Distance: '
                '${_distanceKm.toStringAsFixed(1)} km.',
          );

          await _endTrip(pos);
          return;
        }
      } else {
        _belowThresholdSince = null;
      }
    }
    if (_state == DrivingState.driving) {
      _maxSpeedKmh = math.max(_maxSpeedKmh, speedKmh);
      _speedSamples.add(speedKmh);
      if (_lastPosition != null) {
        _distanceKm +=
            Geolocator.distanceBetween(
              _lastPosition!.latitude,
              _lastPosition!.longitude,
              pos.latitude,
              pos.longitude,
            ) /
            1000;
      }
      _lastPosition = pos;

      if (_currentTripId != null) {
        await _supabase
            .from('driving_trips')
            .update({
              'max_speed_kmh': _maxSpeedKmh,
              'distance_km': _distanceKm,
              'hard_brake_count': _hardBrakeCount,
              'rapid_accel_count': _rapidAccelCount,
              'speeding_events': _speedingEvents,
              'speeding_duration_sec': _speedingDurationSec,
            })
            .eq('id', _currentTripId!);
      }
    }
  }

  Future<void> _startTrip(
    Position pos, {
    required String userId,
    required String familyId,
  }) async {
    _state = DrivingState.driving;
    _maxSpeedKmh = 0;
    _distanceKm = 0;
    _hardBrakeCount = 0;
    _rapidAccelCount = 0;
    _speedingEvents = 0;
    _speedingDurationSec = 0;
    _wasSpeeding = false;
    _speedSamples.clear();
    _lastPosition = pos;

    final row = await _supabase
        .from('driving_trips')
        .insert({
          'family_id': familyId,
          'user_id': userId,
          'status': 'in_progress',
          'start_lat': pos.latitude,
          'start_lng': pos.longitude,
          'speed_limit_kmh': speedingLimitKmh,
        })
        .select()
        .single();

    _currentTripId = row['id'] as String;
    final prefs = await SharedPreferences.getInstance();
    final userName = prefs.getString('last_user_name');
    await _notifyDrivingEvent(
      type: 'trip_started',
      title: '$userName Trip Started',
      body: 'Driving activity has started.',
    );
  }

  //   Future<void> _endTrip(Position pos) async {
  //     _state = DrivingState.stopped;
  //     if (_currentTripId == null) return;
  //
  //     final avgSpeed = _speedSamples.isEmpty
  //         ? 0.0
  //         : _speedSamples.reduce((a, b) => a + b) / _speedSamples.length;
  //
  //     await _supabase
  //         .from('driving_trips')
  //         .update({
  //           'status': 'completed',
  //           'end_time': DateTime.now().toIso8601String(),
  //           'end_lat': pos.latitude,
  //           'end_lng': pos.longitude,
  //           'max_speed_kmh': _maxSpeedKmh,
  //           'avg_speed_kmh': avgSpeed,
  //           'distance_km': _distanceKm,
  //           'hard_brake_count': _hardBrakeCount,
  //           'rapid_accel_count': _rapidAccelCount,
  //           'speeding_events': _speedingEvents,
  //           'speeding_duration_sec': _speedingDurationSec,
  //         })
  //         .eq('id', _currentTripId!);
  //
  //     _currentTripId = null;
  //     _aboveCount = 0;
  //     _belowCount = 0;
  //   }
  Future<String?> getPlaceName({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=$latitude,$longitude'
          '&key=AIzaSyDaiR-2trfsS9oVK7ed0MnxhD9YRnOaQCk',
        ),
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);

      if (data['status'] != 'OK') {
        debugPrint('Geocoding status: ${data['status']}');
        return null;
      }

      final results = data['results'] as List;

      if (results.isEmpty) {
        return null;
      }

      return results.first['formatted_address']?.toString();
    } catch (e) {
      debugPrint('Reverse geocoding failed: $e');
      return null;
    }
  }

  Future<void> _endTrip(Position pos) async {
    _state = DrivingState.stopped;

    if (_currentTripId == null) return;

    final avgSpeed = _speedSamples.isEmpty
        ? 0.0
        : _speedSamples.reduce((a, b) => a + b) / _speedSamples.length;

    String? endPlaceName;
    String? endAddress;

    // Reverse geocode final location
    endPlaceName = await getPlaceName(
      latitude: pos.latitude,
      longitude: pos.longitude,
    );

    await _supabase
        .from('driving_trips')
        .update({
          'status': 'completed',
          'end_time': DateTime.now().toIso8601String(),
          'end_lat': pos.latitude,
          'end_lng': pos.longitude,
          'end_place_name': endPlaceName,
          'end_address': endAddress,
          'max_speed_kmh': _maxSpeedKmh,
          'avg_speed_kmh': avgSpeed,
          'distance_km': _distanceKm,
          'hard_brake_count': _hardBrakeCount,
          'rapid_accel_count': _rapidAccelCount,
          'speeding_events': _speedingEvents,
          'speeding_duration_sec': _speedingDurationSec,
        })
        .eq('id', _currentTripId!);
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _supabase
        .from('member_locations')
        .update({'address': endPlaceName})
        .eq('user_id', userId);
    _currentTripId = null;
    _aboveCount = 0;
    _belowCount = 0;
  }
}

// ---------------------------------------------------------------------------
// DISTRACTED DRIVING MONITOR (runs in the FOREGROUND app, not the
// background isolate — phone unlock/app-resume events aren't observable
// from a background service)
// ---------------------------------------------------------------------------

/// Mix this into a State that wraps your app's root (or a persistent
/// widget that's always mounted while the app can be foregrounded), e.g.
/// your MaterialApp's home widget's State class:
///
///   class _HomeState extends State<Home> with WidgetsBindingObserver,
///       DistractedDrivingMonitor {
///     @override
///     void initState() {
///       super.initState();
///       WidgetsBinding.instance.addObserver(this);
///       initDistractedDrivingMonitor(Supabase.instance.client);
///     }
///     @override
///     void dispose() {
///       WidgetsBinding.instance.removeObserver(this);
///       super.dispose();
///     }
///     @override
///     void didChangeAppLifecycleState(AppLifecycleState state) {
///       checkDistractedDriving(state);
///     }
///   }
mixin DistractedDrivingMonitor {
  SupabaseClient? _ddSupabase;

  void initDistractedDrivingMonitor(SupabaseClient supabase) {
    _ddSupabase = supabase;
  }

  Future<void> checkDistractedDriving(AppLifecycleState state) async {
    if (state != AppLifecycleState.resumed) return;
    final supabase = _ddSupabase;
    if (supabase == null) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final trip = await supabase
        .from('driving_trips')
        .select('id, distracted_events')
        .eq('user_id', userId)
        .eq('status', 'in_progress')
        .maybeSingle();

    if (trip == null) return; // not currently driving — resuming is normal

    final current = (trip['distracted_events'] as int?) ?? 0;
    await supabase
        .from('driving_trips')
        .update({'distracted_events': current + 1})
        .eq('id', trip['id'] as String);
  }
}
