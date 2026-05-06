import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/auth_repository.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/navigation/shield_router.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isBiometricAvailable = false;
  bool _obscurePassword = true;

  // Toggle between OTP and Password login
  bool _usePasswordLogin = false;

  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      if (mounted) {
        setState(() {
          _isBiometricAvailable = canCheck && isDeviceSupported;
        });
      }
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> _handleBiometricLogin() async {
    setState(() => _isLoading = true);
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access your Family Shield',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      if (!authenticated) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Authentication cancelled.')),
          );
        }
        return;
      }

      // Try current session first
      Session? session = Supabase.instance.client.auth.currentSession;

      // If no session, try refreshing from stored refresh token
      if (session == null) {
        try {
          final response = await Supabase.instance.client.auth.refreshSession();
          session = response.session;
        } catch (_) {
          session = null;
        }
      }

      if (session != null && mounted) {
        ref.invalidate(currentUserProfileProvider);
        final profile = await ref.read(currentUserProfileProvider.future);
        if (profile != null && mounted) {
          final matchedRole = ShieldRole.values.firstWhere(
            (r) => r.name == profile.role,
            orElse: () => ShieldRole.none,
          );
          ref.read(userRoleProvider.notifier).setRole(matchedRole);
          context.go('/dashboard');
        } else if (mounted) {
          context.go('/role-selection');
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expired. Please sign in with email first.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Biometric auth error: $e'),
            backgroundColor: ShieldColors.urgentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // OTP / Magic link login
  Future<void> _handleOtpLogin() async {
    if (_emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter your email.')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.signInWithMagicLink(_emailController.text.trim(), '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification PIN sent to your email.')),
        );
        context.push(
          '/otp?email=${Uri.encodeComponent(_emailController.text.trim())}',
        );
      }
    } catch (e) {
      print(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: $e'),
            backgroundColor: ShieldColors.urgentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Email + Password login
  Future<void> _handlePasswordLogin() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password.')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.signInWithPassword(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (mounted) {
        // Session is now set — load profile and navigate
        ref.invalidate(currentUserProfileProvider);
        final profile = await ref.read(currentUserProfileProvider.future);
        if (profile != null && mounted) {
          final matchedRole = ShieldRole.values.firstWhere(
            (r) => r.name == profile.role,
            orElse: () => ShieldRole.none,
          );
          ref.read(userRoleProvider.notifier).setRole(matchedRole);
          context.go('/dashboard');
        } else if (mounted) {
          context.go('/role-selection');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: $e'),
            backgroundColor: ShieldColors.urgentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign In'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 40),
            const Icon(
              Icons.lock_person_outlined,
              size: 80,
              color: ShieldColors.activeTeal,
            ),
            const SizedBox(height: 24),
            Text(
              'Welcome Back',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),

            // Toggle buttons
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _usePasswordLogin = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !_usePasswordLogin
                              ? ShieldColors.activeTeal
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'OTP Login',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: !_usePasswordLogin
                                ? Colors.white
                                : Colors.grey.shade600,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _usePasswordLogin = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _usePasswordLogin
                              ? ShieldColors.activeTeal
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Password Login',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _usePasswordLogin
                                ? Colors.white
                                : Colors.grey.shade600,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Email field
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'EMAIL ADDRESS',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),

            // Password field — only show in password mode
            if (_usePasswordLogin) ...[
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'PASSWORD',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Forgot password
              // Align(
              //   alignment: Alignment.centerRight,
              //   child: TextButton(
              //     onPressed: () {
              //       // TODO: handle forgot password
              //     },
              //     child: const Text('Forgot Password?'),
              //   ),
              // ),
            ],

            const SizedBox(height: 24),

            // Login button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : _usePasswordLogin
                    ? _handlePasswordLogin
                    : _handleOtpLogin,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _usePasswordLogin ? 'SIGN IN' : 'SEND VERIFICATION PIN',
                      ),
              ),
            ),

            // Biometric
            if (_isBiometricAvailable) ...[
              const SizedBox(height: 24),
              Row(
                children: const [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('OR', style: TextStyle(color: Colors.grey)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),
              IconButton(
                onPressed: _isLoading ? null : _handleBiometricLogin,
                icon: const Icon(
                  Icons.fingerprint,
                  size: 48,
                  color: ShieldColors.activeTeal,
                ),
                tooltip: 'Biometric Sign In',
              ),
              const Text(
                'Use Biometrics',
                style: TextStyle(color: ShieldColors.activeTeal),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
