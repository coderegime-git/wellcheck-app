import 'dart:async';
import 'dart:io';
import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:purchases_flutter/models/purchases_configuration.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/navigation/shield_router.dart';
import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:well_check_v3/core/notifications/push_notification_service.dart';
import 'package:well_check_v3/core/notifications/medication_notification_service.dart';
import 'package:well_check_v3/features/safety/services/background_service_config.dart';
import 'package:well_check_v3/features/safety/widgets/global_alert_overlay.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/notifications/global_notification_wrapper.dart';
import 'package:well_check_v3/features/safety/services/pulse_service.dart';

import 'core/notifications/checkin_service.dart';
import 'features/safety/services/location_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");
  await FMTCObjectBoxBackend().initialise();
  await FMTCStore('mapStore').manage.create();
  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        autoRefreshToken: true,
      ),
    );
  }
  //  await Supabase.instance.client.auth.signOut();
  // Initialize Firebase (gracefully degrade if not configured)
  //if (Platform.isAndroid) {
  try {
    await Firebase.initializeApp();
    debugPrint('[Firebase] Initialized successfully.');
    // Initialize Push Notifications (only if Firebase succeeded)
    await PushNotificationService.initialize();
    //await _checkNotificationPermission();
  } catch (e) {
    debugPrint('[Firebase] Not initialized: $e — push notifications disabled.');
  }
  // }

  // Initialize Medication Notifications
  await MedicationNotificationService.initialize();
  await CheckinNotificationService.initialize();

  // Initialize Background Safety Pulse
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await initializeBackgroundService();
  }
  if (Platform.isIOS) {
    await clearBadge();
  }
  // final locationGranted = await LocationService.requestLocationPermissions(context);
  // if (!locationGranted) {
  //   debugPrint(
  //     'Location permission not granted — service may lack location data',
  //   );
  // }
  await initializeRevenueCat();
  //await initializeBackgroundService();
  await FlutterBackgroundService().startService();
  runApp(const ProviderScope(child: WellCheckApp()));
}

Future<void> clearBadge() async {
  final plugin = FlutterLocalNotificationsPlugin();

  const iosDetails = DarwinNotificationDetails(
    presentAlert: false,
    presentBadge: true,
    presentSound: false,
    badgeNumber: 0,
  );

  await plugin.show(0, null, null, const NotificationDetails(iOS: iosDetails));
}

Future<void> initializeRevenueCat() async {
  // Platform-specific API keys
  await Purchases.setLogLevel(
    const bool.fromEnvironment('dart.vm.product')
        ? LogLevel.error
        : LogLevel.verbose,
  );

  String apiKey;
  if (Platform.isIOS) {
    //apiKey = 'test_RkkbIScltWKRExGQlJRcyqVtfZg';
    apiKey = 'appl_RzALamoKBAqvXxsCqUgqzMTOsBO';
  } else if (Platform.isAndroid) {
    //  apiKey = 'test_RkkbIScltWKRExGQlJRcyqVtfZg';
    apiKey = 'goog_NndwRPhezROHtiZUaBiJZeAwfrk';
  } else {
    throw UnsupportedError('Platform not supported');
  }

  await Purchases.configure(PurchasesConfiguration(apiKey));
}

class WellCheckApp extends ConsumerStatefulWidget {
  const WellCheckApp({super.key});

  @override
  ConsumerState<WellCheckApp> createState() => _WellCheckAppState();
}

class _WellCheckAppState extends ConsumerState<WellCheckApp> {
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkNotificationPermission();
    });
    try {
      final sharedSecureStorage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock,
          // ✅ This ensures token persists after logout and is accessible on first unlock
        ),
      );
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
        data,
      ) {
        final event = data.event;
        final session = data.session;
        debugPrint('[Auth Event] $event');

        // ✅ Always keep tokens in sync
        if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.tokenRefreshed) {
          if (session != null) {
            sharedSecureStorage.write(
              key: 'supabase_refresh_token',
              value: session.refreshToken ?? '',
            );
            sharedSecureStorage.write(
              key: 'supabase_access_token',
              value: session.accessToken,
            );
            sharedSecureStorage.write(
              key: 'biometric_login_enabled',
              value: 'true',
            );
            debugPrint('TOKEN SYNCED: ${session.refreshToken}');
          }
        }

        if (event == AuthChangeEvent.signedIn) {
          ref.invalidate(currentUserProfileProvider);
          _handleSignedIn();
        }

        // ✅ REMOVED signedOut handler — navigation handled in _logout() directly
      });
    } catch (e) {
      debugPrint('[Auth] Supabase not initialized: $e');
    }
    // WidgetsBinding.instance.addPostFrameCallback((_){final router = ref.read(shieldRouterProvider);
    // router.go('/');});
  }

  Future<void> _handleSignedIn() async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile != null) {
        final matchedRole = ShieldRole.values.firstWhere(
          (r) => r.name == profile.role,
          orElse: () => ShieldRole.none,
        );
        ref.read(userRoleProvider.notifier).setRole(matchedRole);
        await PulseService().broadcastPulse(null);
        final service = FlutterBackgroundService();

        bool isRunning = await service.isRunning();

        if (!isRunning) {
          service.startService();
        }
        ref.read(shieldRouterProvider).go('/dashboard');
      } else {
        ref.read(shieldRouterProvider).go('/role-selection');
      }
    } catch (e) {
      debugPrint('Deep link auth handling error: $e');
      ref.read(shieldRouterProvider).go('/role-selection');
    }
  }

  Future<void> _checkNotificationPermission() async {
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
            'WellCheck works best with notifications enabled. '
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

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(shieldRouterProvider);

    return GlobalNotificationWrapper(
      child: MaterialApp.router(
        title: 'Well-Check V3',
        theme: ShieldDesign.lightTheme,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          return GlobalAlertOverlay(child: child!);
        },
      ),
    );
  }
}
