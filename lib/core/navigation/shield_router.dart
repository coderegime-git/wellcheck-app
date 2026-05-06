import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

import '../security/biometric_screen.dart';

part 'shield_router.g.dart';

enum ShieldRole { leader, monitor, senior, student, pet, none }

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
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isLoggedIn = session != null;

      final isOnAuthPage =
          state.matchedLocation == '/' ||
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      final isOnOtp = state.matchedLocation.startsWith('/otp');

      if (isOnOtp) return null;

      // If logged in, check biometric pref
      if (isLoggedIn && isOnAuthPage) {
        // Get pref synchronously from cached prefs
        // BiometricNotifier handles the actual gate
        return '/dashboard';
      }

      if (!isLoggedIn && !isOnAuthPage) return '/';

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
        builder: (context, state) => const SafeZoneConfigScreen(),
      ),
      GoRoute(
        path: '/sync-calendar',
        builder: (context, state) => const SyncCalendarScreen(),
      ),
      GoRoute(
        path: '/add-safe-zone',
        builder: (context, state) => const SafeZoneScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) {
          return BiometricGateScreen(
            child: Consumer(
              builder: (context, ref, child) {
                final role = ref.watch(userRoleProvider);

                // If role is unset (cold start with persisted session), resolve it
                if (role == ShieldRole.none) {
                  return FutureBuilder(
                    future: ref.read(currentUserProfileProvider.future),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Scaffold(
                          body: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final profile = snapshot.data;
                      if (profile != null) {
                        final matchedRole = ShieldRole.values.firstWhere(
                          (r) => r.name == profile.role,
                          orElse: () => ShieldRole.none,
                        );
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          ref
                              .read(userRoleProvider.notifier)
                              .setRole(matchedRole);
                        });
                        // Return the correct dashboard immediately
                        return _dashboardForRole(matchedRole);
                      }

                      // No profile — send to role selection
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        GoRouter.of(context).go('/role-selection');
                      });
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    },
                  );
                }

                return _dashboardForRole(role);
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
      return const SeniorHUD();
    case ShieldRole.student:
      return const StudentDashboard();
    case ShieldRole.pet:
      return const PetDashboard();
    case ShieldRole.none:
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _AuthNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _sub;

  _AuthNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      notifyListeners(); // ← triggers redirect re-evaluation
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
