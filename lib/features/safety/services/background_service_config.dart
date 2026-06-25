import 'dart:async';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:well_check_v3/features/safety/services/pulse_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'location_service.dart';

// Future<void> initializeBackgroundService() async {
//   final service = FlutterBackgroundService();
//
//   await service.configure(
//     androidConfiguration: AndroidConfiguration(
//       onStart: onStart,
//       autoStart: true,
//       isForegroundMode: true,
//       notificationChannelId: 'well_check_channel',
//       initialNotificationTitle: 'Well-Check Active',
//       initialNotificationContent: 'Monitoring family shield status',
//       foregroundServiceNotificationId: 888,
//     ),
//     iosConfiguration: IosConfiguration(
//       autoStart: true,
//       onForeground: onStart,
//       onBackground: onIosBackground,
//     ),
//   );
// }
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // ✅ ADD THIS BLOCK
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'well_check_channel',
    'Well Check Background Service',
    description: 'This channel is used for background monitoring',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  // ✅ THEN configure service
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'well_check_channel',
      initialNotificationTitle: 'Well-Check Active',
      initialNotificationContent: 'Monitoring family shield status',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [
        // ← add this if your plugin version supports it
        AndroidForegroundType.location,
      ],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Re-initialize Supabase for background isolate
  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  final pulseService = PulseService();

  // Fire the first pulse immediately so new users see data right away
  final prefs0 = await SharedPreferences.getInstance();
  final userId0 = prefs0.getString('last_user_id');
  if (userId0 != null) {
    try {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          await pulseService.broadcastPulse(userId0);
        }
      } else {
        await pulseService.broadcastPulse(userId0);
      }
    } catch (e) {
      debugPrint('Initial pulse failed: $e');
    }
  }

  // Then continue on a 5-minute timer
  Timer.periodic(const Duration(minutes: 5), (timer) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('last_user_id');

    if (userId == null) {
      debugPrint('Background Service: Still waiting for user identity...');
      return;
    }

    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        await pulseService.broadcastPulse(userId);
      }
    } else {
      await pulseService.broadcastPulse(userId);
    }
  });
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('last_user_id');
  Position? _lastPosition;

  LocationService.getPositionStream().listen((position) async {
    // print("Background location ${position.latitude}  ${position.longitude}");
    await pulseService.updateLocation(userId);
  });
}

// Timer.periodic(const Duration(seconds: 20), (timer) async {
//   final prefs = await SharedPreferences.getInstance();
//   final userId = prefs.getString('last_user_id');
//
//   if (userId == null) {
//     debugPrint('Background Service: Still waiting for user identity...');
//     return;
//   }
//
//   if (service is AndroidServiceInstance) {
//     if (await service.isForegroundService()) {
//       await pulseService.updateLocation(userId);
//     }
//   } else {
//     await pulseService.updateLocation(userId);
//   }
// });
