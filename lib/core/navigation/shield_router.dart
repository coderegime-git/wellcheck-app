import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/features/auth/welcome_screen.dart';
import 'package:well_check_v3/features/auth/registration_screen.dart';
import 'package:well_check_v3/features/auth/login_screen.dart';
import 'package:well_check_v3/features/auth/otp_verification_screen.dart';
import 'package:well_check_v3/features/auth/role_selection_screen.dart';
import 'package:well_check_v3/features/auth/role_selection_screen.dart';
import 'package:well_check_v3/features/auth/join_with_code_screen.dart';
import 'package:well_check_v3/features/auth/profile_setup_screen.dart';
import 'package:well_check_v3/features/dashboard/leader_dashboard.dart';
import 'package:well_check_v3/features/dashboard/monitor_dashboard.dart';
import 'package:well_check_v3/features/dashboard/senior_hud_screen.dart';
import 'package:well_check_v3/features/dashboard/student_dashboard.dart';
import 'package:well_check_v3/features/dashboard/pet_tracker_dashboard.dart';
import 'package:well_check_v3/features/profile/admin_dashboard.dart';
import 'package:well_check_v3/features/profile/referral_detail.dart';
import 'package:well_check_v3/features/tools/safe_zone_config_screen.dart';
import 'package:well_check_v3/features/tools/sync_calendar_screen.dart';
import 'package:well_check_v3/features/tools/safe_zone_screen.dart';

import '../../config/constants.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/auth/wellcheck_paywall_screen.dart';
import '../../features/safety/services/pulse_service.dart';
import '../../features/safety/services/purchase_services.dart';
import '../../services/connectivity_services.dart';
import '../notifications/push_notification_service.dart';
import '../security/biometric_screen.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

part 'shield_router.g.dart';

enum ShieldRole {
  leader,
  monitor,
  senior,
  student,
  pet,
  child,
  parent,
  other,
  none,
}

final connectivityService = ConnectivityService();

@Riverpod(keepAlive: true)
class UserRole extends _$UserRole {
  @override
  ShieldRole build() => ShieldRole.none;

  void setRole(ShieldRole role) => state = role;
}

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

@riverpod
GoRouter shieldRouter(Ref ref) {
  final authNotifier = _AuthNotifier(); // ← ADD THIS

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    observers: [_SplashRemoveObserver()],
    //  initialLocation: '/splash',
    initialLocation: '/',
    // observers: <NavigatorObserver>[
    //   ConnectivityNavigatorObserver(connectivityService),
    // ],
    refreshListenable: authNotifier,
    // ← ADD THIS
    // redirect: (context, state) {
    //   final session = Supabase.instance.client.auth.currentSession;
    //   final isLoggedIn = session != null;
    //
    //   final isOnAuthPage =
    //       state.matchedLocation == '/' ||
    //       state.matchedLocation == '/login' ||
    //       state.matchedLocation == '/register';
    //
    //   final isOnOtp = state.matchedLocation.startsWith('/otp');
    //
    //   if (isOnOtp) return null;
    //   if (isLoggedIn && isOnAuthPage) return '/dashboard';
    //   if (!isLoggedIn && !isOnAuthPage) return '/';
    //
    //   return null;
    // },
    redirect: (context, state) async {
      // final session = Supabase.instance.client.auth.currentSession;
      // //final isLoggedIn = session != null;
      // final prefs = await SharedPreferences.getInstance();
      // final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      // final isOnAuthPage =
      //     state.matchedLocation == '/' ||
      //     state.matchedLocation == '/login' ||
      //     state.matchedLocation == '/register';
      //
      // final isOnOtp = state.matchedLocation.startsWith('/otp');
      // final isOnPaywall = state.matchedLocation == '/paywall';
      //
      // if (isOnOtp) return null;
      //
      // if (!isLoggedIn && !isOnAuthPage) return '/';
      // if (isLoggedIn && isOnAuthPage) return '/dashboard';

      // Pro gate — check entitlement before allowing dashboard access
      // if (isLoggedIn && !isOnPaywall) {
      //   final supabaseUserId = Supabase.instance.client.auth.currentUser?.id;
      //   if (supabaseUserId != null) {
      //     await Purchases.logIn(supabaseUserId);
      //   }
      //   final offerings = await Purchases.getOfferings();
      //
      //   print('Current Offering: ${offerings.current?.identifier}');
      //
      //   if (offerings.current != null) {
      //     for (final package in offerings.current!.availablePackages) {
      //       print('Package Identifier: ${package.identifier}');
      //       print('Store Product ID: ${package.storeProduct.identifier}');
      //       print('Title: ${package.storeProduct.title}');
      //       print('Price: ${package.storeProduct.priceString}');
      //       print('-------------------');
      //     }
      //   }
      //   final customerInfo = await Purchases.getCustomerInfo();
      //   print("Info123 $customerInfo");
      //   print("Info123 $supabaseUserId");
      //   final isPro = customerInfo.entitlements.active.containsKey(
      //     'WellCheck Pro',
      //   );
      //   if (!isPro) return '/paywall';
      // }
      // Pro gate — only leaders require subscription
      if (state.matchedLocation == '/splash') return null;
      final prefs = await SharedPreferences.getInstance();
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;
      final user = session?.user;
      // final isLoggedIn = user != null;
      final isLoggedIn = session != null;

      debugPrint(
        'REDIRECT — path: ${state.matchedLocation} isLoggedIn: $isLoggedIn',
      );
      print("state.fullPath");
      print(state.fullPath);
      print(state);
      print(state.uri);
      print(state.uri);
      if (state.uri.toString().contains("wellcheckapp.app.link")) {
        return '/';
      }
      final isOnAuthPage =
          state.matchedLocation == '/' ||
          state.matchedLocation == '/splash' ||
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      final isOnOtp = state.matchedLocation.startsWith('/otp');
      final isOnPaywall = state.matchedLocation == '/paywall';

      if (isOnOtp) return null;

      if (!isLoggedIn && !isOnAuthPage) return '/';
      //  if (!isLoggedIn && !isOnAuthPage) return '/splash';

      if (isLoggedIn && isOnAuthPage) return '/dashboard';

      if (isLoggedIn && !isOnPaywall) {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        debugPrint('REDIRECT — userId: $userId');

        if (userId != null) {
          try {
            final salesperson = await Supabase.instance.client
                .from('salespersons')
                .select(
                  'id, name, email, referral_code, referral_url, qr_code_url, is_active',
                )
                .eq('user_id', userId)
                .maybeSingle();

            debugPrint('Salesperson: $salesperson');

            if (salesperson != null) {
              if (salesperson['is_active'] == true) {
                debugPrint('User is salesperson');

                return '/referral-details';
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Account is inactive.Please contact admin."),
                  ),
                );
                // final prefs = await SharedPreferences.getInstance();
                // await prefs.setBool('priv_biometric', false);
                // await prefs.setBool('is_logged_in', false);

                await PushNotificationService.saveTokenToProfile(null);
                await Supabase.instance.client.auth.signOut();
                return '/';
              }
            }
            // } else {
            //   // Scaffold
            //
            //   ScaffoldMessenger.of(
            //     context,
            //   ).showSnackBar(SnackBar(content: Text("Account is inactive")));
            //   final prefs = await SharedPreferences.getInstance();
            //   await prefs.setBool('priv_biometric', false);
            //   await prefs.setBool('is_logged_in', false);
            //
            //   await PushNotificationService.saveTokenToProfile(null);
            //   await Supabase.instance.client.auth.signOut();
            //   return '/splash';
            // }
          } catch (e) {
            print("slaeeee${e.toString()}");
          }
          try {
            final members = await Supabase.instance.client
                .from('family_members')
                .select('role')
                .eq('user_id', userId)
                .limit(1);
            if (members.isEmpty) {
              return null;
            }
            // No rows — new user

            // New user hasn't selected a role yet
            // if (member == null) {
            //   return null;
            // }

            final role = members.first['role'];

            print('User role: $role');
            if (role != null) {
              if (isLoggedIn) {
                final userId = Supabase.instance.client.auth.currentUser?.id;
                if (userId != null) {
                  final profile = await Supabase.instance.client
                      .from('profiles')
                      .select('full_name')
                      .eq('id', userId)
                      .maybeSingle();
                  if (profile == null || profile['full_name'] == null) {
                    return '/profile-setup';
                  }
                }
              }
            }
            if (role == 'admin') {
              return '/admin-dashboard';
            }
            // Only leaders must subscribe
            if (role == 'leader') {
              final profile = await Supabase.instance.client
                  .from('profiles')
                  .select('full_name')
                  .eq('id', userId)
                  .maybeSingle();

              // Still in profile setup flow
              if (profile == null || profile['full_name'] == null) {
                return null;
              }
              await Purchases.logIn(userId);

              final customerInfo = await Purchases.getCustomerInfo();

              print('CustomerInfo: $customerInfo');
              debugPrint(
                'ACTIVE ENTITLEMENTS: ${customerInfo.entitlements.active.keys}',
              );

              debugPrint(
                'ALL ENTITLEMENTS: ${customerInfo.entitlements.all.keys}',
              );

              final pro = customerInfo.entitlements.all['WellCheck Pro'];

              debugPrint('PRO ENTITLEMENT: $pro');
              debugPrint('PRO IS ACTIVE: ${pro?.isActive}');
              final hasSubscription =
                  customerInfo.entitlements.active.containsKey(
                    'WellCheck Pro',
                  ) ||
                  customerInfo.entitlements.active.containsKey(
                    'WellCheck Premium',
                  ) ||
                  customerInfo.entitlements.active.containsKey(
                    'Well Check Premium',
                  );

              if (!hasSubscription) {
                return '/paywall';
              }
            }
          } catch (e) {
            print('Subscription check errorr: $e');
            return null;
          }
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) {
          return const SplashScreen();
        },
      ),
      GoRoute(path: '/', builder: (context, state) => const WelcomeScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegistrationScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/otp',
        builder: (context, state) {
          final email = state.uri.queryParameters['email'] ?? '';
          return OTPVerificationScreen(email: email);
        },
      ),
      GoRoute(
        path: '/role-selection',
        builder: (context, state) => const RoleSelectionScreen(),
      ),

      GoRoute(
        path: '/referral-details',
        builder: (context, state) => const ReferralDetailsScreen(),
      ),
      GoRoute(
        path: '/join-with-code',
        builder: (context, state) => const JoinWithCodeScreen(),
      ),
      GoRoute(
        path: '/profile-setup',
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: '/safe-zone-config',
        builder: (context, state) {
          final isEdit = state.extra as bool? ?? false;
          return SafeZoneConfigScreen(fromLeader: isEdit);
        },
      ),
      GoRoute(
        path: '/paywall',
        builder: (context, state) => const WellCheckPaywallScreen(),
      ),
      GoRoute(
        path: '/sync-calendar',
        builder: (context, state) => const SyncCalendarScreen(),
      ),
      GoRoute(
        path: '/admin-dashboard',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/add-safe-zone',
        builder: (context, state) =>
            SafeZoneScreen(existingZone: state.extra as Map<String, dynamic>?),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) {
          return BiometricGateScreen(
            child: UpdateCheckGate(
              child: Consumer(
                builder: (context, ref, child) {
                  final role = ref.watch(userRoleProvider);
                  if (role != ShieldRole.none) {
                    return _dashboardForRole(role);
                  }
                  // Resolve role from profile
                  return FutureBuilder(
                    future: ref.read(currentUserProfileProvider.future),
                    builder: (context, snapshot) {
                      print(snapshot.connectionState);
                      print("ssddsdds");

                      debugPrint(
                        'auth user: ${Supabase.instance.client.auth.currentUser?.id}',
                      );
                      print(snapshot.connectionState);
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Scaffold(
                          body: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final profile = snapshot.data;

                      // ✅ No waiting, no retry — decide immediately
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        if (!context.mounted) return;

                        final user = Supabase.instance.client.auth.currentUser;
                        print(profile);
                        print("profileprofile");

                        if (user == null) {
                          GoRouter.of(context).go('/');
                          //  GoRouter.of(context).go('/splash');
                          return;
                        }
                        if (profile != null) {
                          final matchedRole = ShieldRole.values.firstWhere(
                            (r) => r.name == profile.role,
                            orElse: () => ShieldRole.none,
                          );
                          ref
                              .read(userRoleProvider.notifier)
                              .setRole(matchedRole);
                          await SafeZoneService.clearZoneStatusCache();
                        } else if (user == null) {
                          GoRouter.of(context).go('/splash');
                        } else {
                          GoRouter.of(context).go('/role-selection');
                        }
                      });

                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    ],
  );
}

Widget _dashboardForRole(ShieldRole role) {
  switch (role) {
    case ShieldRole.leader:
      return const LeaderDashboard();
    case ShieldRole.monitor:
      return const MonitorDashboard();
    case ShieldRole.senior:
    case ShieldRole.parent:
    case ShieldRole.other:
      return const SeniorHUD();
    case ShieldRole.student:
    case ShieldRole.child:
      return const StudentDashboard();
    case ShieldRole.pet:
      return const PetDashboard();
    case ShieldRole.none:
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

// class _AuthNotifier extends ChangeNotifier {
//   late final StreamSubscription<AuthState> _sub;
//
//   _AuthNotifier() {
//     _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
//       _handleAuthChange(data);
//       notifyListeners();
//     });
//   }
//
//   Future<void> _handleAuthChange(AuthState data) async {
//     final user = data.session?.user;
//     final sharedSecureStorage = const FlutterSecureStorage(
//       aOptions: AndroidOptions(encryptedSharedPreferences: true),
//       iOptions: IOSOptions(
//         accessibility: KeychainAccessibility.first_unlock,
//         // ✅ This ensures token persists after logout and is accessible on first unlock
//       ),
//     );
//     if (data.event == AuthChangeEvent.signedIn && user != null) {
//       await PurchasesService.instance.identifyUser(user.id);
//
//       // ✅ Sync latest tokens on every signIn/tokenRefresh
//       final session = data.session;
//       if (session != null) {
//         await sharedSecureStorage.write(
//           key: 'supabase_refresh_token',
//           value: session.refreshToken ?? '',
//         );
//         await sharedSecureStorage.write(
//           key: 'supabase_access_token',
//           value: session.accessToken,
//         );
//         await sharedSecureStorage.write(
//           key: 'biometric_login_enabled',
//           value: 'true',
//         );
//       }
//     } else if (data.event == AuthChangeEvent.tokenRefreshed) {
//       // ✅ Always keep tokens in sync when rotated
//       final session = data.session;
//       if (session != null) {
//         await sharedSecureStorage.write(
//           key: 'supabase_refresh_token',
//           value: session.refreshToken ?? '',
//         );
//         await sharedSecureStorage.write(
//           key: 'supabase_access_token',
//           value: session.accessToken,
//         );
//       }
//     } else if (data.event == AuthChangeEvent.signedOut) {
//       debugPrint('SIGNED OUT EVENT — stack trace:');
//       debugPrint(StackTrace.current.toString());
//
//       if (LogoutState.isLoggingOut) {
//         debugPrint('Intentional logout — skipping');
//         return;
//       }
//       //  final router = ref.read(shieldRouterProvider);
//       // router.go('/');
//     }
//   }
//
//   @override
//   void dispose() {
//     _sub.cancel();
//     super.dispose();
//   }
// }
class _AuthNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _sub;
  bool _initialEventSkipped = false; // ✅ add this

  // _AuthNotifier() {
  //   _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
  //     // ✅ Skip the first replayed event from rxdart startWith
  //     if (!_initialEventSkipped) {
  //       _initialEventSkipped = true;
  //       debugPrint('[Auth] Skipping replayed event: ${data.event}');
  //       notifyListeners();
  //       return;
  //     }
  //     _handleAuthChange(data);
  //     notifyListeners();
  //   });
  // }
  _AuthNotifier() {
    final sharedSecureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
        // ✅ This ensures token persists after logout and is accessible on first unlock
      ),
    );
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;
      debugPrint('[Auth Event] $event');

      // ✅ Only sync tokens on signIn/refresh — ignore signedOut completely
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
          if (event == AuthChangeEvent.signedIn) {
            PurchasesService.instance.identifyUser(session.user.id);
          }
        }
      }
      // ✅ No signedOut handling — logout is manual navigation only
      notifyListeners();
    });
  }

  Future<void> _handleAuthChange(AuthState data) async {
    final user = data.session?.user;
    final session = data.session;
    final sharedSecureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
        // ✅ This ensures token persists after logout and is accessible on first unlock
      ),
    );
    if (data.event == AuthChangeEvent.signedIn && user != null) {
      await PurchasesService.instance.identifyUser(user.id);

      if (session != null) {
        await sharedSecureStorage.write(
          key: 'supabase_refresh_token',
          value: session.refreshToken ?? '',
        );
        await sharedSecureStorage.write(
          key: 'supabase_access_token',
          value: session.accessToken,
        );
        await sharedSecureStorage.write(
          key: 'biometric_login_enabled',
          value: 'true',
        );
        debugPrint('TOKEN SYNCED on signedIn: ${session.refreshToken}');
      }
    } else if (data.event == AuthChangeEvent.tokenRefreshed) {
      if (session != null) {
        await sharedSecureStorage.write(
          key: 'supabase_refresh_token',
          value: session.refreshToken ?? '',
        );
        await sharedSecureStorage.write(
          key: 'supabase_access_token',
          value: session.accessToken,
        );
        debugPrint('TOKEN SYNCED on tokenRefreshed: ${session.refreshToken}');
      }
    } else if (data.event == AuthChangeEvent.signedOut) {
      if (LogoutState.isLoggingOut) {
        debugPrint('[Auth] Intentional logout — skipping RC logout');
        return;
      }
      // Real session expiry
      try {
        await PurchasesService.instance.logOut();
      } catch (e) {
        debugPrint('[RC] logOut skipped: $e');
      }
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

class LogoutState {
  static bool isLoggingOut = false;
}

class _SplashRemoveObserver extends NavigatorObserver {
  bool _removed = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_removed) return;
    _removed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }
}

Future<void> _openStore(String url) async {
  final uri = Uri.parse(url);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    debugPrint('Could not open store: $url');
  }
}

List<String> _parseNotes(String? notes) {
  if (notes == null || notes.trim().isEmpty) return [];
  return notes
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'^\s*[-•*]\s*'), '').trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

/// Blocking dialog: no barrier dismiss, no back button.
Future<void> showForceUpdateDialog(
  BuildContext context,
  String updateUrl,
  String? releaseNotes,
) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _UpdateContent(
            isForce: true,
            releaseNotes: releaseNotes,
            onUpdate: () => _openStore(updateUrl),
          ),
        ),
      ),
    ),
  );
}

/// Dismissible bottom sheet.
Future<void> showSoftUpdateDialog(
  BuildContext context,
  String updateUrl,
  String? releaseNotes,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _UpdateContent(
              isForce: false,
              releaseNotes: releaseNotes,
              onUpdate: () {
                Navigator.pop(ctx);
                _openStore(updateUrl);
              },
              onLater: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    ),
  );
}

class _UpdateContent extends StatelessWidget {
  final bool isForce;
  final String? releaseNotes;
  final VoidCallback onUpdate;
  final VoidCallback? onLater;

  const _UpdateContent({
    required this.isForce,
    required this.releaseNotes,
    required this.onUpdate,
    this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final notes = _parseNotes(releaseNotes);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(
            isForce ? Icons.system_update_rounded : Icons.rocket_launch_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          isForce ? 'Update Required' : 'New Version Available',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          isForce
              ? 'Please update the app to continue using it.'
              : 'A newer version is ready with improvements and fixes.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54, height: 1.4),
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "WHAT'S NEW",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...notes.map(
                    (n) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle, size: 16, color: color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(n, style: const TextStyle(height: 1.3)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onUpdate,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Update Now',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
        if (!isForce && onLater != null) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: onLater,
            child: const Text(
              'Maybe Later',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ],
      ],
    );
  }
}

class UpdateCheckGate extends StatefulWidget {
  final Widget child;

  const UpdateCheckGate({super.key, required this.child});

  // Only check once per app launch, not on every dashboard rebuild
  static bool _checkedThisSession = false;

  @override
  State<UpdateCheckGate> createState() => _UpdateCheckGateState();
}

class _UpdateCheckGateState extends State<UpdateCheckGate> {
  Future<bool> _checkForUpdate() async {
    final info = Platform.isAndroid
        ? Constants.androidAppVersion
        : Constants.iOSAppVersion;
    return checkAppUpdate(info);
  }

  Future<bool> checkAppUpdate(String currentVersion) async {
    try {
      final response = await http.post(
        Uri.parse('${Constants.kSupabaseUrl}/functions/v1/check-app-update'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${Constants.kSupabaseAnonKey}',
        },
        body: jsonEncode({
          'platform': Platform.isAndroid ? 'android' : 'ios',
          // Use Platform.isAndroid ? 'android' : 'ios'
          'current_version': currentVersion,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String updateType = data['updateType'];

        if (updateType == 'FORCE') {
          showForceUpdateDialog(
            context,
            data['updateUrl'],
            data['releaseNotes'],
          );
          return true;
        } else if (updateType == 'SOFT') {
          showSoftUpdateDialog(
            context,
            data['updateUrl'],
            data['releaseNotes'],
          );
          return false;
        }
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    if (UpdateCheckGate._checkedThisSession) return;
    UpdateCheckGate._checkedThisSession = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      await _checkForUpdate();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
