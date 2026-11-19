import 'dart:async';
import 'dart:io';

import 'package:activity_recognition_flutter/activity_recognition_flutter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class ActivityRecognitionService {
  final ActivityRecognition _activityRecognition = ActivityRecognition();

  StreamSubscription<ActivityEvent>? _subscription;

  ActivityType? _currentActivity;
  int _confidence = 0;

  ActivityType? get currentActivity => _currentActivity;

  int get confidence => _confidence;

  bool get isInVehicle => _currentActivity == ActivityType.inVehicle;

  bool get isStill => _currentActivity == ActivityType.still;

  Future<bool> initialize({
    required void Function(ActivityType activity, int confidence)
    onActivityChanged,
  }) async {
    try {
      final status = await Permission.activityRecognition.status;

      debugPrint('🔥 Permission = $status');

      if (!status.isGranted) {
        debugPrint('❌ Activity permission not granted');
        return false;
      }

      debugPrint('🔥 Creating activity stream...');

      _subscription = _activityRecognition
          .activityStream(runForegroundService: true)
          .listen(
            (event) {
              debugPrint('🔥🔥🔥 ACTIVITY EVENT RECEIVED 🔥🔥🔥');
              debugPrint('🔥 Type: ${event.type}');
              debugPrint('🔥 Confidence: ${event.confidence}');

              onActivityChanged(event.type, event.confidence);
            },
            onError: (error, stackTrace) {
              debugPrint('❌ ACTIVITY STREAM ERROR: $error');
              debugPrint('$stackTrace');
            },
            onDone: () {
              debugPrint('⚠️ ACTIVITY STREAM DONE');
            },
            cancelOnError: false,
          );

      debugPrint('🔥 Dart activity listener created');

      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ Activity initialize error: $e');
      debugPrint('$stackTrace');
      return false;
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
