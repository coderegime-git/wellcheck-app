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

import '../safety/services/pulse_service.dart';

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
            content: Text('Biometric auth error: ${e.toReadableMessage()}'),
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
          //   await  PulseService().broadcastPulse(null);

          final matchedRole = ShieldRole.values.firstWhere(
            (r) => r.name == profile.role,
            orElse: () => ShieldRole.none,
          );
          ref.read(userRoleProvider.notifier).setRole(matchedRole);
          if (mounted) {
            context.go('/dashboard');
          }
        } else if (mounted) {
          context.go('/role-selection');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: ${e.toReadableMessage()}'),
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
    // return Scaffold(
    //   backgroundColor: Colors.grey.shade50, // o
    //   body: Container(
    //     decoration: BoxDecoration(
    //       gradient: LinearGradient(
    //         begin: Alignment.topCenter,
    //         end: Alignment.bottomCenter,
    //         colors: [
    //           ShieldColors.activeTeal, // teal top
    //           ShieldColors.activeTeal.withOpacity(0.5), // teal top
    //           Colors.grey.shade100, // off-white bottom
    //           Colors.grey.shade50, // o// off-white bottom
    //         ],
    //       ),
    //     ),
    //     child: SafeArea(
    //       child: SingleChildScrollView(
    //         padding: const EdgeInsets.symmetric(horizontal: 32),
    //         child: Column(
    //           children: [
    //             const SizedBox(height: 64),
    //
    //             // App Icon
    //             Container(
    //               width: 150,
    //               height: 140,
    //               decoration: BoxDecoration(
    //                 //   color: Colors.white.withOpacity(0.25),
    //                 borderRadius: BorderRadius.circular(24),
    //               ),
    //               child: Image.asset("assets/logo.png"),
    //             ),
    //
    //             const SizedBox(height: 18),
    //
    //             // Title
    //             const Text(
    //               'Welcome Back',
    //               style: TextStyle(
    //                 fontSize: 26,
    //                 fontWeight: FontWeight.bold,
    //                 color: Color(0xFF1A1A1A),
    //               ),
    //             ),
    //             const SizedBox(height: 6),
    //             const Text(
    //               'Sign in to continue',
    //               style: TextStyle(fontSize: 14, color: Colors.black),
    //             ),
    //
    //             const SizedBox(height: 30),
    //
    //             // White card area
    //             Container(
    //               //padding: const EdgeInsets.all(24),
    //               decoration: BoxDecoration(
    //                 //   color: Colors.white,
    //                 borderRadius: BorderRadius.circular(20),
    //                 boxShadow: [
    //                   BoxShadow(
    //                     color: Colors.black.withOpacity(0.06),
    //                     blurRadius: 16,
    //                     offset: const Offset(0, 4),
    //                   ),
    //                 ],
    //               ),
    //               child: Column(
    //                 crossAxisAlignment: CrossAxisAlignment.stretch,
    //                 children: [
    //                   // OTP Login label
    //                   // Container(
    //                   //   padding: const EdgeInsets.symmetric(vertical: 10),
    //                   //   decoration: BoxDecoration(
    //                   //     color: const Color(0xFF00796B),
    //                   //     borderRadius: BorderRadius.circular(10),
    //                   //   ),
    //                   //   alignment: Alignment.center,
    //                   //   child: const Text(
    //                   //     'OTP Login',
    //                   //     style: TextStyle(
    //                   //       color: Colors.white,
    //                   //       fontWeight: FontWeight.w600,
    //                   //       fontSize: 15,
    //                   //     ),
    //                   //   ),
    //                   // ),
    //                   const SizedBox(height: 20),
    //
    //                   // Email field
    //                   TextFormField(
    //                     controller: _emailController,
    //                     keyboardType: TextInputType.emailAddress,
    //                     decoration: InputDecoration(
    //                       hintText: 'EMAIL ADDRESS',
    //                       hintStyle: const TextStyle(
    //                         fontSize: 13,
    //                         color: Color(0xFFAAAAAA),
    //                         letterSpacing: 0.5,
    //                       ),
    //                       prefixIcon: Icon(
    //                         Icons.email_outlined,
    //                         color: Colors.grey.shade600,
    //                         size: 25,
    //                       ),
    //                       contentPadding: const EdgeInsets.symmetric(
    //                         vertical: 14,
    //                         horizontal: 12,
    //                       ),
    //                       enabledBorder: OutlineInputBorder(
    //                         borderRadius: BorderRadius.circular(10),
    //                         borderSide: const BorderSide(
    //                           color: Color(0xFFDDDDDD),
    //                         ),
    //                       ),
    //                       focusedBorder: OutlineInputBorder(
    //                         borderRadius: BorderRadius.circular(10),
    //                         borderSide: const BorderSide(
    //                           color: Color(0xFF00796B),
    //                           width: 1.5,
    //                         ),
    //                       ),
    //                     ),
    //                   ),
    //
    //                   const SizedBox(height: 16),
    //
    //                   // Send OTP button
    //                   SizedBox(
    //                     height: 50,
    //                     child: ElevatedButton(
    //                       onPressed: _isLoading ? null : _handleOtpLogin,
    //                       style: ElevatedButton.styleFrom(
    //                         backgroundColor: ShieldColors.activeTeal,
    //                         foregroundColor: Colors.white,
    //                         shape: RoundedRectangleBorder(
    //                           borderRadius: BorderRadius.circular(10),
    //                         ),
    //                         elevation: 0,
    //                       ),
    //                       child: _isLoading
    //                           ? const SizedBox(
    //                               width: 20,
    //                               height: 20,
    //                               child: CircularProgressIndicator(
    //                                 color: Colors.white,
    //                                 strokeWidth: 2,
    //                               ),
    //                             )
    //                           : const Text(
    //                               'SEND VERIFICATION PIN',
    //                               style: TextStyle(
    //                                 fontSize: 14,
    //                                 fontWeight: FontWeight.w600,
    //                                 letterSpacing: 0.8,
    //                               ),
    //                             ),
    //                     ),
    //                   ),
    //                 ],
    //               ),
    //             ),
    //
    //             const SizedBox(height: 24),
    //
    //             // OR divider
    //             Row(
    //               children: [
    //                 Expanded(
    //                   child: Divider(
    //                     color: Colors.grey.shade400,
    //                     thickness: 0.5,
    //                   ),
    //                 ),
    //                 Padding(
    //                   padding: const EdgeInsets.symmetric(horizontal: 12),
    //                   child: Text(
    //                     'OR',
    //                     style: TextStyle(
    //                       color: Colors.grey.shade500,
    //                       fontSize: 13,
    //                     ),
    //                   ),
    //                 ),
    //                 Expanded(
    //                   child: Divider(
    //                     color: Colors.grey.shade400,
    //                     thickness: 0.5,
    //                   ),
    //                 ),
    //               ],
    //             ),
    //
    //             const SizedBox(height: 20),
    //
    //             // Biometrics
    //             GestureDetector(
    //               onTap: () {
    //                 // trigger biometric auth
    //               },
    //               child: Column(
    //                 children: [
    //                   Icon(
    //                     Icons.fingerprint,
    //                     size: 48,
    //                     color: const Color(0xFF00796B),
    //                   ),
    //                   const SizedBox(height: 6),
    //                   const Text(
    //                     'Use Biometrics',
    //                     style: TextStyle(
    //                       color: Color(0xFF00796B),
    //                       fontSize: 14,
    //                       fontWeight: FontWeight.w500,
    //                     ),
    //                   ),
    //                 ],
    //               ),
    //             ),
    //
    //             const SizedBox(height: 32),
    //
    //             // Sign up link
    //             GestureDetector(
    //               onTap: () => context.push('/register'),
    //
    //               child: RichText(
    //                 text: const TextSpan(
    //                   style: TextStyle(fontSize: 13, color: Color(0xFF777777)),
    //                   children: [
    //                     TextSpan(
    //                       text: "Don't have an account? ",
    //                       style: TextStyle(
    //                         color: Colors.black,
    //                         fontWeight: FontWeight.bold,
    //                       ),
    //                     ),
    //                     TextSpan(
    //                       text: 'Sign Up',
    //                       style: TextStyle(
    //                         color: Color(0xFF00796B),
    //                         fontWeight: FontWeight.bold,
    //                       ),
    //                     ),
    //                   ],
    //                 ),
    //               ),
    //             ),
    //
    //             const SizedBox(height: 32),
    //           ],
    //         ),
    //       ),
    //     ),
    //   ),
    // );
  }
}
// lib/core/utils/supabase_exception.dart

extension SupabaseExceptionMessage on Object {
  String toReadableMessage() {
    final error = toString();
    if (error.contains('429') ||
        error.contains('over_email_send_rate_limit') ||
        error.contains('over_request_rate_limit') ||
        error.contains('For security purposes')) {
      // Extract seconds if present
      final match = RegExp(r'after (\d+) seconds').firstMatch(error);
      if (match != null) {
        final seconds = match.group(1);
        return 'Please wait $seconds seconds before trying again.';
      }
      return 'Too many attempts. Please wait a moment and try again.';
    }
    // PostgrestException — DB errors
    if (this is PostgrestException) {
      final e = this as PostgrestException;
      print(e);
      switch (e.code) {
        case '23505':
          return 'This record already exists.';
        case '23503':
          return 'Related record not found.';
        case '23502':
          return 'Required field is missing.';
        case '42501':
          return 'You don\'t have permission to do this.';
        case 'PGRST116':
          return 'Record not found.';
        case 'over_email_send_rate_limit':
          return 'Too many emails sent. Please wait a few minutes and try again.';

        default:
          return e.message;
      }
    }

    // AuthException — login/signup errors
    if (this is AuthException) {
      final e = this as AuthException;
      print(e);
      switch (e.message) {
        case 'Invalid login credentials':
          return 'Incorrect email or password.';
        case 'Email not confirmed':
          return 'Please verify your email first.';
        case 'User already registered':
          return 'An account with this email already exists.';
        case 'Password should be at least 6 characters':
          return 'Password must be at least 6 characters.';

        // ── Rate limit cases ──────────────────────────────────
        case 'Email rate limit exceeded':
        case 'over_email_send_rate_limit':
          return 'Too many emails sent. Please wait a few minutes and try again.';
        case 'over_request_rate_limit':
          return 'Too many requests. Please slow down and try again.';
        case 'For security purposes, you can only request this after':
          return 'Please wait before requesting another email.';
        // ─────────────────────────────────────────────────────

        default:
          // Catch rate limit messages that come as dynamic strings
          if (e.message.contains('rate limit') ||
              e.message.contains('after') ||
              e.message.contains('seconds')) {
            return 'Too many attempts. Please wait a moment and try again.';
          }
          return e.message;
      }
    }

    // StorageException — file upload errors
    if (this is StorageException) {
      final e = this as StorageException;
      return e.message;
    }

    // Network / timeout
    if (error.contains('SocketException') ||
        error.contains('NetworkException')) {
      return 'No internet connection. Please check your network.';
    }
    if (error.contains('TimeoutException')) {
      return 'Request timed out. Please try again.';
    }

    // Fallback
    return 'Something went wrong. Please try again.';
  }
}
