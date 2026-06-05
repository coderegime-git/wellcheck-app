import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/auth_repository.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/navigation/shield_router.dart';
import 'package:well_check_v3/features/auth/login_screen.dart';

import '../safety/services/pulse_service.dart';

class OTPVerificationScreen extends ConsumerStatefulWidget {
  final String email;

  const OTPVerificationScreen({super.key, required this.email});

  @override
  ConsumerState<OTPVerificationScreen> createState() =>
      _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends ConsumerState<OTPVerificationScreen> {
  final _pinController = TextEditingController();
  bool _isLoading = false;
  final focusNode = FocusNode();

  Future<void> _handleVerify() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the pin sent to your email'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.verifyOTP(widget.email, pin);

      if (mounted) {
        // Force a re-fetch of the profile just in case it was cached as null
        ref.invalidate(currentUserProfileProvider);
        // await Supabase.instance.client.auth.updateUser(
        //   UserAttributes(password: '12345678'),
        // );
        try {
          final profile = await ref.read(currentUserProfileProvider.future);
          if (!mounted) return;
          final service = FlutterBackgroundService();

          bool isRunning = await service.isRunning();

          if (!isRunning) {
            service.startService();
          }
          if (profile != null) {
            // User exists, map role and go to dashboard
            final matchedRole = ShieldRole.values.firstWhere(
              (r) => r.name == profile.role,
              orElse: () => ShieldRole.none,
            );
            ref.read(userRoleProvider.notifier).setRole(matchedRole);
            focusNode.unfocus();
            //  await  PulseService().broadcastPulse(null);

            context.go('/dashboard');
          } else {
            focusNode.unfocus();

            // New user without a profile, needs to setup
            context.go('/role-selection');
          }
        } catch (e) {
          // Fallback if network fails
          if (!mounted) return;
          focusNode.unfocus();
          context.go('/role-selection');
        }
      }
    } catch (e) {
      print(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification failed: ${e.toReadableMessage()}'),
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
      appBar: AppBar(title: const Text('Verify Identity'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Check Your Email',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: ShieldColors.activeTeal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'We sent an 8-digit pin to ${widget.email}. Enter it below to secure your session.',
              style: const TextStyle(color: ShieldColors.textLabel),
            ),
            const SizedBox(height: 32),
            TextField(
              focusNode: focusNode,
              controller: _pinController,
              decoration: const InputDecoration(
                labelText: '8-DIGIT PIN',
                prefixIcon: Icon(Icons.password_outlined),
              ),
              keyboardType: TextInputType.number,
              maxLength: 8,
              style: const TextStyle(
                letterSpacing: 8,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleVerify,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('VERIFY PIN'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
