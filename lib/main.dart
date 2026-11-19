import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_branch_sdk/flutter_branch_sdk.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart';
import 'package:purchases_flutter/models/purchases_configuration.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/navigation/shield_router.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

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
import 'package:well_check_v3/services/connectivity_services.dart';
import 'package:well_check_v3/services/dose_notification_service.dart';
import 'package:well_check_v3/services/driving_detection_motion.dart';
import 'package:well_check_v3/services/life360_location_service.dart';
import 'package:well_check_v3/services/referral_service.dart';

import 'config/constants.dart';
import 'core/notifications/checkin_service.dart';
import 'features/safety/services/location_service.dart';

Future<void> logWellEvent(
  SupabaseClient client,
  Map<String, dynamic> payload,
) async {
  debugPrint('[well_events insert] user_id=${payload['user_id']}');
  try {
    await client.from('well_events').insert(payload);
  } catch (e) {
    if (e is PostgrestException && e.code == '23503') {
      debugPrint(
        '[stitch_queue] Dropping stale queued item — user no longer exists: ${payload['user_id']}',
      );
      // remove this item from the queue instead of retrying it forever
      // continue; // or your queue's equivalent "mark as discarded"
    }
    rethrow;
  }
}

const String kLocationChannelId = 'well_check_location';

@pragma('vm:entry-point')
Future<void> backgroundOnStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  debugPrint('🚀 WellCheck background service started');

  // Register the stop listener first so it works even while startup is running.
  Life360LocationService? locationService;

  service.on('stopService').listen((event) async {
    debugPrint('🛑 WellCheck background service stopping');
    locationService?.stopSharingMyLocation();
    service.stopSelf();
  });

  // ---------------------------------------------------------
  // Android foreground notification
  // ---------------------------------------------------------
  debugPrint('🚀 WellCheck background service started');

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();

    await service.setForegroundNotificationInfo(
      title: 'Well Check',
      content: 'Location tracking is active',
    );
  }

  // ---------------------------------------------------------
  // Initialize environment
  // ---------------------------------------------------------
  // await dotenv.load(fileName: '.env');
  //
  // final supabaseUrl = dotenv.env['SUPABASE_URL'];
  // final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
  final supabaseUrl = Constants.kSupabaseUrl;
  final supabaseAnonKey = Constants.kSupabaseAnonKey;

  if (supabaseUrl == null || supabaseAnonKey == null) {
    debugPrint('❌ Supabase environment variables missing');
    service.stopSelf();
    return;
  }

  // ---------------------------------------------------------
  // Initialize Supabase in background isolate
  // ---------------------------------------------------------
  late final SupabaseClient supabase;

  try {
    supabase = Supabase.instance.client; // already initialized (same isolate)
  } catch (_) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    supabase = Supabase.instance.client;
  }
  // if (!Supabase.instance.isInitialized) {
  //   await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  // }

  //final supabase = Supabase.instance.client;
  late final DrivingDetector drivingDetector;

  // ---------------------------------------------------------
  // Get saved user information
  // ---------------------------------------------------------
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();

  final userId = prefs.getString('last_user_id');
  final familyId = prefs.getString('last_family_id');
  final userName = prefs.getString('last_user_name') ?? 'Member';
  if (userId == null || familyId == null) {
    debugPrint('❌ Missing userId/familyId');
    service.stopSelf(); // don't leave an idle foreground service running
    return;
  }

  debugPrint('👤 Background user: $userId');
  debugPrint('👨‍👩‍👧 Family: $familyId');

  // ---------------------------------------------------------
  // Create services INSIDE background isolate
  // ---------------------------------------------------------
  locationService = Life360LocationService(supabase);
  //final drivingDetector = DrivingDetector(supabase);
  final pulseService = PulseService();
  drivingDetector = DrivingDetector(
    supabase,
    onDrivingEvent:
        ({
          required String type,
          required String title,
          required String body,
        }) async {
          try {
            // await supabase.functions.invoke(
            //   'driving-alert',
            //   body: {
            //     'family_id': familyId,
            //     'driver_user_id': userId,
            //     'event_type': type,
            //     'title': title,
            //     'message': body,
            //     'trip_id': drivingDetector.currentTripId,
            //   },
            // );

            debugPrint('🔔 Driving alert sent: $type');
          } catch (e, stackTrace) {
            debugPrint('❌ Driving alert failed: $e');
            debugPrint('$stackTrace');
          }
        },
  );

  // ---------------------------------------------------------
  // Start GPS
  // ---------------------------------------------------------
  await locationService.startSharingMyLocation(
    name: userName,
    onPosition: (position) async {
      try {
        debugPrint(
          '📍 Background GPS: '
          '${position.latitude}, '
          '${position.longitude}',
        );

        //  await pulseService.handlePositionUpdate(position);
        await pulseService.updateLocation(userId);

        // await drivingDetector.feed(
        //   position,
        //   userId: userId,
        //   familyId: familyId,
        // );
      } catch (e, stackTrace) {
        debugPrint('❌ Background location processing error: $e');
        debugPrint('$stackTrace');
      }
    },
  );
}

Future<void> initializeBackgroundService() async {
  // Create the channel BEFORE configure(), since we pass a custom channel id.
  if (Platform.isAndroid) {
    const channel = AndroidNotificationChannel(
      kLocationChannelId,
      'Well Check Location',
      description: 'Location tracking status',
      importance: Importance.low,
    );

    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: backgroundOnStart,
      autoStart: false,
      autoStartOnBoot: true,
      isForegroundMode: true,
      notificationChannelId: kLocationChannelId,
      initialNotificationTitle: 'Well Check',
      initialNotificationContent: 'Location tracking is active',
      foregroundServiceNotificationId: 1001,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,

      //   onForeground: backgroundOnStart,
    ),
  );
}

/// Call this AFTER login (once last_user_id / last_family_id are saved)
/// and AFTER location + notification permissions are granted.
// Future<void> startWellCheckService() async {
//   if (!Platform.isAndroid) return;
//
//   final perm = await Geolocator.checkPermission();
//   if (perm == LocationPermission.denied ||
//       perm == LocationPermission.deniedForever) {
//     debugPrint('⚠️ Location permission missing, not starting service');
//     return;
//   }
//
//   final service = FlutterBackgroundService();
//   final isRunning = await service.isRunning();
//   debugPrint('Background service running: $isRunning');
//
//   if (!isRunning) {
//     await service.startService();
//     debugPrint('🚀 Background service start requested');
//   }
// }
Future<void>? appInitFuture;

// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//
//   await FlutterBranchSdk.init(
//     enableLogging: true,
//     branchAttributionLevel: BranchAttributionLevel.FULL,
//   );
//
//   // final pulseService = PulseService();
//
//   FlutterBranchSdk.listSession().listen((data) async {
//     print("REFERRAL: branch session data: $data");
//     await ReferralService.instance.handleBranchData(data);
//   });
//
//   // load environment variables
//   await dotenv.load(fileName: ".env");
//   await FMTCObjectBoxBackend().initialise();
//   await FMTCStore('mapStore').manage.create();
//   final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
//   final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
//
//   if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
//     await Supabase.initialize(
//       url: supabaseUrl,
//       anonKey: supabaseAnonKey,
//       realtimeClientOptions: const RealtimeClientOptions(
//         logLevel: RealtimeLogLevel.info,
//       ),
//       authOptions: FlutterAuthClientOptions(
//         authFlowType: AuthFlowType.pkce,
//         autoRefreshToken: true,
//       ),
//     );
//   }
//
//   //await PulseService.initializeBackgroundService();
//
//   //  await Supabase.instance.client.auth.signOut();
//   // Initialize Firebase (gracefully degrade if not configured)
//   //if (Platform.isAndroid) {
//   try {
//     await Firebase.initializeApp();
//     debugPrint('[Firebase] Initialized successfully.');
//     // Initialize Push Notifications (only if Firebase succeeded)
//     await PushNotificationService.initialize();
//     //await _checkNotificationPermission();
//   } catch (e) {
//     debugPrint('[Firebase] Not initialized: $e — push notifications disabled.');
//   }
//   // }
//
//   // Initialize Medication Notifications
//   await MedicationNotificationService.initialize();
//   await CheckinNotificationService.initialize();
//
//   // Initialize Background Safety Pulse
//   // if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
//   //await initializeBackgroundService();
//   //}
//   if (Platform.isIOS) {
//     await clearBadge();
//   }
//   // final locationGranted = await LocationService.requestLocationPermissions(context);
//   // if (!locationGranted) {
//   //   debugPrint(
//   //     'Location permission not granted — service may lack location data',
//   //   );
//   // }
//
//   await initializeRevenueCat();
//   // await stopWellCheckService();
//   // await initializeBackgroundService();
//   // await startWellCheckService();
//   // await Supabase.instance.client.auth.signOut();
//   //await initializeBackgroundService();
//   //  await FlutterBackgroundService().startService();
//   runApp(const ProviderScope(child: WellCheckApp()));
//   appInitFuture = _deferredInit();
// }

Future<void> main() async {
  //WidgetsFlutterBinding.ensureInitialized();
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  // await dotenv.load(fileName: ".env");
  // final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  // final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  //
  // if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
  //   await Supabase.initialize(
  //     url: supabaseUrl,
  //     anonKey: supabaseAnonKey,
  //     realtimeClientOptions: const RealtimeClientOptions(
  //       logLevel: RealtimeLogLevel.info,
  //     ),
  //     authOptions: FlutterAuthClientOptions(
  //       authFlowType: AuthFlowType.pkce,
  //       autoRefreshToken: true,
  //     ),
  //   );
  // }
  try {
    // await dotenv.load(fileName: ".env");
    // final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    // final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

    if (Constants.kSupabaseUrl.isNotEmpty &&
        Constants.kSupabaseAnonKey.isNotEmpty) {
      await Supabase.initialize(
        url: Constants.kSupabaseUrl,
        anonKey: Constants.kSupabaseAnonKey,
        realtimeClientOptions: const RealtimeClientOptions(
          logLevel: RealtimeLogLevel.info,
        ),
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          autoRefreshToken: true,
        ),
      );
    }
  } catch (e) {
    debugPrint('[Startup] init failed/timed out: $e');
  }
  try {
    await DoseNotificationService.instance.init();
  } catch (e) {
    debugPrint('[DoseSync] init failed: $e');
  }
  runApp(const ProviderScope(child: WellCheckApp()));

  // Everything else runs after the first frame is on screen
  appInitFuture = _deferredInit();
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
        //  await PulseService().broadcastPulse(null);
        // await PulseService()
        //     .broadcastPulse(null)
        //     .timeout(
        //       const Duration(seconds: 10),
        //       onTimeout: () {
        //         debugPrint('[PulseService] broadcastPulse timed out');
        //       },
        //     );
        // final service = FlutterBackgroundService();
        //
        // bool isRunning = await service.isRunning();
        //
        // if (!isRunning) {
        //   service.startService();
        // }
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
    await appInitFuture;
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.getNotificationSettings();

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      // Wait for app to fully load before showing dialog
      await Future.delayed(const Duration(seconds: 2));

      final context = rootNavigatorKey.currentContext;
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
        title: 'Well-Check',
        theme: ShieldDesign.lightTheme,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          return GlobalAlertOverlay(
            child: Stack(
              children: [
                // Shown only while the router is still resolving the redirect
                // const ColoredBox(
                //   color: Colors.white,
                //   child: Center(
                //     child: Column(
                //       mainAxisSize: MainAxisSize.min,
                //       children: [
                //         // Image.asset('assets/images/logo.png', width: 120),
                //         // SizedBox(height: 24),
                //         // CircularProgressIndicator(
                //         //     color: ShieldColors.activeTeal),
                //       ],
                //     ),
                //   ),
                // ),
                ColoredBox(
                  color: Colors.white,
                  child: Center(
                    child: Image.asset(
                      'assets/logo_splash_android12.png',
                      width: 150,
                    ),
                  ),
                ),
                if (child != null) child,
              ],
            ),
          );
        },
      ),
    );
  }
}

Future<void> _processPosition(
  Position position, {
  required PulseService pulseService,
  //required DrivingDetector drivingDetector,
  required String userId,
  required String familyId,
}) async {
  try {
    debugPrint(
      '📍 Background GPS: ${position.latitude}, ${position.longitude}',
    );
    //  await pulseService.handlePositionUpdate(position);
    await pulseService.updateLocation(userId);
    // await drivingDetector.feed(position, userId: userId, familyId: familyId);
  } catch (e, st) {
    debugPrint('❌ Background location processing error: $e');
    debugPrint('$st');
  }
}

/// iOS background tracker. Runs in the MAIN isolate.
class IosBackgroundTracker {
  IosBackgroundTracker._();

  static final IosBackgroundTracker instance = IosBackgroundTracker._();

  StreamSubscription<Position>? _sub;

  //bool get isRunning => _sub != null;

  // Future<void> start() async {
  //   if (_sub != null) return;
  //
  //   final prefs = await SharedPreferences.getInstance();
  //   await prefs.reload();
  //   final userId = prefs.getString('last_user_id');
  //   final familyId = prefs.getString('last_family_id');
  //
  //   if (userId == null || familyId == null) {
  //     debugPrint('❌ Missing userId/familyId (iOS)');
  //     return;
  //   }
  //
  //   final supabase = Supabase.instance.client;
  //   final pulseService = PulseService();
  //   // final drivingDetector = DrivingDetector(supabase);
  //
  //   final settings = AppleSettings(
  //     accuracy: LocationAccuracy.high,
  //     activityType: ActivityType.automotiveNavigation,
  //     distanceFilter: 25,
  //     // meters
  //     pauseLocationUpdatesAutomatically: false,
  //     showBackgroundLocationIndicator: true,
  //     allowBackgroundLocationUpdates: true,
  //   );
  //   late final DrivingDetector drivingDetector;
  //
  //   drivingDetector = DrivingDetector(
  //     supabase,
  //     onDrivingEvent:
  //         ({
  //           required String type,
  //           required String title,
  //           required String body,
  //         }) async {
  //           try {
  //             await supabase.functions.invoke(
  //               'driving-alert',
  //               body: {
  //                 'family_id': familyId,
  //                 'driver_user_id': userId,
  //                 'event_type': type,
  //                 'title': title,
  //                 'message': body,
  //                 'trip_id': drivingDetector.currentTripId,
  //               },
  //             );
  //
  //             debugPrint('🔔 Driving alert sent: $type');
  //           } catch (e, stackTrace) {
  //             debugPrint('❌ Driving alert failed: $e');
  //             debugPrint('$stackTrace');
  //           }
  //         },
  //   );
  //   _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
  //     (position) => _processPosition(
  //       position,
  //       pulseService: pulseService,
  //       drivingDetector: drivingDetector,
  //       userId: userId,
  //       familyId: familyId,
  //     ),
  //     onError: (e) => debugPrint('❌ iOS location stream error: $e'),
  //   );
  //
  //   debugPrint('🚀 iOS background tracking started');
  // }
  Life360LocationService? _locationService;

  bool get isRunning => _locationService != null;

  Future<void> start() async {
    if (_locationService != null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final userId = prefs.getString('last_user_id');
    final familyId = prefs.getString('last_family_id');
    final userName = prefs.getString('last_user_name') ?? 'Member';

    if (userId == null || familyId == null) {
      debugPrint('❌ Missing userId/familyId (iOS)');
      return;
    }

    final supabase = Supabase.instance.client;
    final pulseService = PulseService();

    // late final DrivingDetector drivingDetector;
    //
    // drivingDetector = DrivingDetector(
    //   supabase,
    //   onDrivingEvent:
    //       ({
    //         required String type,
    //         required String title,
    //         required String body,
    //       }) async {
    //         try {
    //           await supabase.functions.invoke(
    //             'driving-alert',
    //             body: {
    //               'family_id': familyId,
    //               'driver_user_id': userId,
    //               'event_type': type,
    //               'title': title,
    //               'message': body,
    //               'trip_id': drivingDetector.currentTripId,
    //             },
    //           );
    //
    //           debugPrint('🔔 Driving alert sent: $type');
    //         } catch (e, stackTrace) {
    //           debugPrint('❌ Driving alert failed: $e');
    //           debugPrint('$stackTrace');
    //         }
    //       },
    // );

    final service = Life360LocationService(supabase);
    _locationService = service;

    try {
      await service.startSharingMyLocation(
        name: userName,
        onPosition: (position) => _processPosition(
          position,
          pulseService: pulseService,
          //   drivingDetector: drivingDetector,
          userId: userId,
          familyId: familyId,
        ),
      );
      debugPrint('🚀 iOS background tracking started');
    } catch (e, stackTrace) {
      debugPrint('❌ iOS tracking failed to start: $e');
      debugPrint('$stackTrace');
      _locationService = null; // allow a retry on the next call
    }
  }

  Future<void> stop() async {
    _locationService?.stopSharingMyLocation();
    _locationService = null;
    debugPrint('🛑 iOS background tracking stopped');
  }
}

/// Ask for the permission level background tracking needs.
/// iOS requires "When In Use" first, then upgrades to "Always".
Future<bool> ensureBackgroundLocationPermission() async {
  if (!await Geolocator.isLocationServiceEnabled()) return false;

  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.deniedForever ||
      perm == LocationPermission.denied) {
    return false;
  }

  // Upgrade to Always
  if (perm == LocationPermission.whileInUse) {
    perm = await Geolocator.requestPermission();
  }

  // Android: whileInUse is enough for a foreground service.
  // iOS: need "always" for tracking after the app is backgrounded.
  //if (Platform.isIOS) return perm == LocationPermission.always;
  return perm == LocationPermission.always ||
      perm == LocationPermission.whileInUse;
}

/// Replaces the previous startWellCheckService()
Future<void> startWellCheckService({bool restart = false}) async {
  debugPrint('▶️ startWellCheckService called');
  if (!await ensureBackgroundLocationPermission()) {
    debugPrint('⚠️ Location permission missing, not starting tracking');
    return;
  }

  if (Platform.isAndroid) {
    final service = FlutterBackgroundService();
    final running = await service.isRunning();

    if (running && !restart) return;

    if (running && restart) {
      service.invoke('stopService');
      await Future.delayed(const Duration(seconds: 1));
    }

    await service.startService();
  } else if (Platform.isIOS) {
    //await IosBackgroundTracker2.instance.start();
    await IosBackgroundTracker.instance.start();
  }
}

/// Call on logout
Future<void> stopWellCheckService() async {
  if (Platform.isAndroid) {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) service.invoke('stopService');
  } else if (Platform.isIOS) {
    await IosBackgroundTracker.instance.stop();
  }
}
