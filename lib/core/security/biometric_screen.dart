import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/shield_theme.dart';

class BiometricGateScreen extends ConsumerStatefulWidget {
  final Widget child;

  const BiometricGateScreen({super.key, required this.child});

  @override
  ConsumerState<BiometricGateScreen> createState() =>
      _BiometricGateScreenState();
}

class _BiometricGateScreenState extends ConsumerState<BiometricGateScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _authenticated = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkAndAuthenticate();
  }

  Future<void> _checkAndAuthenticate() async {
    final prefs = await SharedPreferences.getInstance();
    final biometricEnabled = prefs.getBool('priv_biometric') ?? false;

    if (!biometricEnabled) {
      // Biometric not required — show dashboard directly
      if (mounted)
        setState(() {
          _authenticated = true;
          _checking = false;
        });
      return;
    }

    // Biometric required — authenticate
    await _authenticate();
  }

  Future<void> _authenticate() async {
    try {
      final result = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access your Family Shield',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      if (mounted) {
        setState(() {
          _authenticated = result;
          _checking = false;
        });

        if (!result) {
          // Auth failed/cancelled — go back to welcome
          GoRouter.of(context).go('/');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checking = false);
        GoRouter.of(context).go('/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF131A2A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.fingerprint, size: 64, color: ShieldColors.activeTeal),
              SizedBox(height: 24),
              Text(
                'Verifying Identity...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    if (!_authenticated) {
      return const Scaffold(
        backgroundColor: Color(0xFF131A2A),
        body: Center(
          child: Text(
            'Authentication required.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return widget.child;
  }
}
