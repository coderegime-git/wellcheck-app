import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_branch_sdk/flutter_branch_sdk.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/navigation/shield_router.dart';
import '../../core/notifications/checkin_service.dart';
import '../../core/notifications/medication_notification_service.dart';
import '../../core/notifications/push_notification_service.dart';
import '../../main.dart';
import '../../services/referral_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeApp());
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  Future<void>? appInitFuture;

  Future<void> _initializeApp() async {
    // SharedPreferences prefs = await SharedPreferences.getInstance();
    try {
      // final hasInternet = await _hasInternet();
      // if (!hasInternet) {
      //   await prefs.setBool('navigate', true);
      //   //  await AppData.setSplash(true);
      //   return;
      // }
      //
      // await prefs.setBool('navigate', false);

      if (!mounted) return;

      // Now continue your normal app flow
      _goToNextScreen();
    } catch (e) {
      debugPrint('Splash initialization error: $e');

      if (!mounted) return;

      _goToNextScreen();
    }
  }

  Future<void> _checkNotificationPermission() async {
    await appInitFuture;
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.getNotificationSettings();

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      // Wait for app to fully load before showing dialog
      await Future.delayed(const Duration(seconds: 2));

      final context = rootNavigatorKey.currentContext;
      print("contextcontext");
      print(context);
      if (context == null || !context.mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEEEE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.notifications_off_outlined,
                  color: Colors.red,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Notifications Disabled',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: const Text(
            'Without notifications, you won\'t receive alerts for:\n\n'
            '• ⚠️  Missed check-ins\n'
            '• 💊  Medication reminders\n'
            '• 🆘  SOS emergency alerts\n'
            '• 📍  Safe zone entry/exit\n\n'
            'WellCheck works best with notifications enabled.'
            'Please enable them in your device Settings to stay protected.',
            style: TextStyle(fontSize: 14, height: 1.6),
          ),
          actions: [
            // TextButton(
            //   onPressed: () => Navigator.of(context).pop(),
            //   child: Text(
            //     'Maybe Later',
            //     style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            //   ),
            // ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Opens device notification settings
                AppSettings.openAppSettings(type: AppSettingsType.notification);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007F80),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Enable Notifications'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _deferredInit() async {
    await Future.wait([
      () async {
        try {
          await FlutterBranchSdk.init(
            enableLogging: true,
            branchAttributionLevel: BranchAttributionLevel.FULL,
          );
          FlutterBranchSdk.listSession().listen((data) async {
            print("REFERRAL: branch session data: $data");
            await ReferralService.instance.handleBranchData(data);
          });
        } catch (e) {
          debugPrint('[Branch] init failed: $e');
        }
      }(),
      () async {
        try {
          await FMTCObjectBoxBackend().initialise();
          await FMTCStore('mapStore').manage.create();
        } catch (e) {
          debugPrint('[FMTC] init failed: $e');
        }
      }(),
      () async {
        try {
          await Firebase.initializeApp();
          debugPrint('[Firebase] Initialized successfully.');
          await PushNotificationService.initialize();
        } catch (e) {
          debugPrint(
            '[Firebase] Not initialized: $e — push notifications disabled.',
          );
        }
      }(),
      () async {
        try {
          await initializeRevenueCat();
        } catch (e) {
          debugPrint('[RevenueCat] init failed: $e');
        }
      }(),
    ]);

    await MedicationNotificationService.initialize();
    await CheckinNotificationService.initialize();
    if (Platform.isIOS) await clearBadge();
  }

  void _goToNextScreen() {
    // Your existing authentication/navigation logic

    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    // return Scaffold(
    //   body: Center(child: Image.asset('assets/logo.png', width: 150)),
    // );
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Image.asset('assets/logo_splash_android12.png', width: 150),
      ),
    );
  }
}
