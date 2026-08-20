import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
import 'package:well_check_v3/features/tools/safe_zone_config_screen.dart';
import 'package:well_check_v3/features/tools/sync_calendar_screen.dart';
import 'package:well_check_v3/features/tools/safe_zone_screen.dart';

import '../../features/auth/wellcheck_paywall_screen.dart';
import '../../features/safety/services/pulse_service.dart';
import '../../features/safety/services/purchase_services.dart';
import '../security/biometric_screen.dart';

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
    initialLocation: '/',
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
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

      debugPrint(
        'REDIRECT — path: ${state.matchedLocation} isLoggedIn: $isLoggedIn',
      );

      final isOnAuthPage =
          state.matchedLocation == '/' ||
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      final isOnOtp = state.matchedLocation.startsWith('/otp');
      final isOnPaywall = state.matchedLocation == '/paywall';

      if (isOnOtp) return null;

      if (!isLoggedIn && !isOnAuthPage) return '/';
      if (isLoggedIn && isOnAuthPage) return '/dashboard';

      if (isLoggedIn && !isOnPaywall) {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        debugPrint('REDIRECT — userId: $userId');

        if (userId != null) {
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

              final hasSubscription =
                  customerInfo.entitlements.active.containsKey(
                    'WellCheck Pro',
                  ) ||
                  customerInfo.entitlements.active.containsKey(
                    'WellCheck Premium',
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
        path: '/add-safe-zone',
        builder: (context, state) =>
            SafeZoneScreen(existingZone: state.extra as Map<String, dynamic>?),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) {
          return BiometricGateScreen(
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
                        GoRouter.of(context).go('/');
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
