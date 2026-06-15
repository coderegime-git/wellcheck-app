import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  // Initialize Firebase (gracefully degrade if not configured)
  //if (Platform.isAndroid) {
  try {
    await Firebase.initializeApp();
    debugPrint('[Firebase] Initialized successfully.');
    // Initialize Push Notifications (only if Firebase succeeded)
    await PushNotificationService.initialize();
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
Future<void> initializeRevenueCat() async {
  // Platform-specific API keys
  await Purchases.setLogLevel(
    const bool.fromEnvironment('dart.vm.product') ? LogLevel.error : LogLevel.verbose,
  );

  String apiKey;
  if (Platform.isIOS) {
    apiKey = 'test_RkkbIScltWKRExGQlJRcyqVtfZg';
  } else if (Platform.isAndroid) {
    apiKey = 'test_RkkbIScltWKRExGQlJRcyqVtfZg';
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
    try {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((data) {
            final event = data.event;
            debugPrint('[Auth Event] $event');

            if (event == AuthChangeEvent.signedIn) {
              // User signed in via magic link deep link or OTP
              ref.invalidate(currentUserProfileProvider);
              _handleSignedIn();
            } else if (event == AuthChangeEvent.signedOut) {
              // Session expired or user signed out
              final router = ref.read(shieldRouterProvider);
              router.go('/');
            }
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
