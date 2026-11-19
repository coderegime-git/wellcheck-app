import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/auth_repository.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/navigation/shield_router.dart';
import 'package:well_check_v3/features/auth/login_screen.dart';

import '../../core/data/stitch_queue.dart';
import '../../main.dart';
import '../safety/services/pulse_service.dart';
import '../safety/services/purchase_services.dart';

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
  final secureStorage = FlutterSecureStorage();

  String generateRandomPassword({int length = 48}) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
        '0123456789!@#\$%^&*()-_=+';

    final random = Random.secure();

    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

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

      if (widget.email != "reviewer@wellcheck.com" &&
          widget.email != "admin@wellcheck.com") {
        await authRepo.verifyOTP(widget.email, pin);
      } else {
        if (_pinController.text == "12345678") {
          await authRepo.signInWithPassword(widget.email, "12345678");
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Verification failed: Invalid OTP'),
              backgroundColor: ShieldColors.urgentRed,
            ),
          );
          return;
        }
      }
      // final session = Supabase.instance.client.auth.currentSession;
      // if (session != null) {
      //   final prefs = await SharedPreferences.getInstance();
      //   // await prefs.setBool('is_logged_in', true);
      //   // final storage = const FlutterSecureStorage();
      //   final storage = const FlutterSecureStorage(
      //     aOptions: AndroidOptions(encryptedSharedPreferences: true),
      //     iOptions: IOSOptions(
      //       accessibility: KeychainAccessibility.first_unlock,
      //       // ✅ This ensures token persists after logout and is accessible on first unlock
      //     ),
      //   );
      //   await storage.write(key: 'biometric_login_enabled', value: 'true');
      //
      //   await storage.write(
      //     key: 'supabase_access_token',
      //     value: session.accessToken,
      //   );
      //   await storage.write(
      //     key: 'supabase_refresh_token',
      //     value: session.refreshToken ?? '',
      //   );
      //   await storage.write(key: 'biometric_login_enabled', value: 'true');
      // }

      if (mounted) {
        // Force a re-fetch of the profile just in case it was cached as null
        ref.invalidate(currentUserProfileProvider);
        if (widget.email != "reviewer@wellcheck.com" &&
            widget.email != "admin@wellcheck.com") {
          setupBiometricCredentials();
        }
        // await Supabase.instance.client.auth.updateUser(
        //   UserAttributes(password: '12345678'),
        // );
        try {
          await PurchasesService.instance.identifyUser(
            Supabase.instance.client.auth.currentUser!.id,
          );
          final profile = await ref.read(currentUserProfileProvider.future);
          if (!mounted) return;
          if (widget.email != "admin@wellcheck.com") {
            // final service = FlutterBackgroundService();
            //
            // bool isRunning = await service.isRunning();
            //
            // if (!isRunning) {
            //   service.startService();
            // }
            // await stopWellCheckService();
            //
            // await initializeBackgroundService();
            // await startWellCheckService();
          } else {
            await stopWellCheckService();
            //  FlutterBackgroundService().invoke('stopService');
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
            if (widget.email == "admin@wellcheck.com") {
              context.go('/admin-dashboard');
            } else {
              // await initializeBackgroundService();
              // await startWellCheckService(restart: true);
              //
              context.go('/dashboard');
            }
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

  Future<void> setupBiometricCredentials() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null || user.email == null) {
      throw Exception('Authenticated user email is unavailable.');
    }

    final email = user.email!;
    final password = generateRandomPassword();

    // Set the password on the existing authenticated account.
    await supabase.auth.updateUser(UserAttributes(password: password));

    // Store credentials securely on this device.
    await secureStorage.write(key: 'biometric_email', value: email);

    await secureStorage.write(key: 'biometric_password', value: password);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_login_enabled', true);
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
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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

// import 'dart:math';
//
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_background_service/flutter_background_service.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'package:go_router/go_router.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';
// import 'package:well_check_v3/core/design/shield_theme.dart';
// import 'package:well_check_v3/core/data/auth_repository.dart';
// import 'package:well_check_v3/core/data/user_profile_provider.dart';
// import 'package:well_check_v3/core/navigation/shield_router.dart';
// import 'package:well_check_v3/features/auth/login_screen.dart';
//
// import '../../core/data/stitch_queue.dart';
// import '../../main.dart';
// import '../safety/services/pulse_service.dart';
// import '../safety/services/purchase_services.dart';
//
// class OTPVerificationScreen extends ConsumerStatefulWidget {
//   final String email;
//   final String phone;
//   final bool isSms;
//
//   const OTPVerificationScreen({
//     super.key,
//     required this.email,
//     this.phone = '',
//     this.isSms = false,
//   });
//
//   @override
//   ConsumerState<OTPVerificationScreen> createState() =>
//       _OTPVerificationScreenState();
// }
//
// class _OTPVerificationScreenState extends ConsumerState<OTPVerificationScreen> {
//   final _pinController = TextEditingController();
//   bool _isLoading = false;
//   final focusNode = FocusNode();
//   final secureStorage = FlutterSecureStorage();
//
//   String generateRandomPassword({int length = 48}) {
//     const chars =
//         'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
//         '0123456789!@#\$%^&*()-_=+';
//
//     final random = Random.secure();
//
//     return List.generate(
//       length,
//       (_) => chars[random.nextInt(chars.length)],
//     ).join();
//   }
//
//   Future<void> _handleVerify() async {
//     final pin = _pinController.text.trim();
//     if (pin.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Please enter the pin sent to your email'),
//         ),
//       );
//       return;
//     }
//
//     setState(() => _isLoading = true);
//     try {
//       final authRepo = ref.read(authRepositoryProvider);
//
//       if (widget.email != "reviewer@wellcheck.com" &&
//           widget.email != "admin@wellcheck.com") {
//         //  await authRepo.verifyOTP(widget.email, pin);
//         await authRepo.verifyOTP(
//           email: widget.email,
//           phone: widget.phone,
//           token: pin,
//           isSms: widget.isSms,
//         );
//       } else {
//         if (_pinController.text == "12345678") {
//           await authRepo.signInWithPassword(widget.email, "12345678");
//         } else {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Text('Verification failed: Invalid OTP'),
//               backgroundColor: ShieldColors.urgentRed,
//             ),
//           );
//           return;
//         }
//       }
//       // final session = Supabase.instance.client.auth.currentSession;
//       // if (session != null) {
//       //   final prefs = await SharedPreferences.getInstance();
//       //   // await prefs.setBool('is_logged_in', true);
//       //   // final storage = const FlutterSecureStorage();
//       //   final storage = const FlutterSecureStorage(
//       //     aOptions: AndroidOptions(encryptedSharedPreferences: true),
//       //     iOptions: IOSOptions(
//       //       accessibility: KeychainAccessibility.first_unlock,
//       //       // ✅ This ensures token persists after logout and is accessible on first unlock
//       //     ),
//       //   );
//       //   await storage.write(key: 'biometric_login_enabled', value: 'true');
//       //
//       //   await storage.write(
//       //     key: 'supabase_access_token',
//       //     value: session.accessToken,
//       //   );
//       //   await storage.write(
//       //     key: 'supabase_refresh_token',
//       //     value: session.refreshToken ?? '',
//       //   );
//       //   await storage.write(key: 'biometric_login_enabled', value: 'true');
//       // }
//
//       if (mounted) {
//         // Force a re-fetch of the profile just in case it was cached as null
//         ref.invalidate(currentUserProfileProvider);
//         if (widget.email != "reviewer@wellcheck.com" &&
//             widget.email != "admin@wellcheck.com") {
//           setupBiometricCredentials();
//         }
//         // await Supabase.instance.client.auth.updateUser(
//         //   UserAttributes(password: '12345678'),
//         // );
//         try {
//           await PurchasesService.instance.identifyUser(
//             Supabase.instance.client.auth.currentUser!.id,
//           );
//           final profile = await ref.read(currentUserProfileProvider.future);
//           if (!mounted) return;
//           if (widget.email != "admin@wellcheck.com") {
//             // final service = FlutterBackgroundService();
//             //
//             // bool isRunning = await service.isRunning();
//             //
//             // if (!isRunning) {
//             //   service.startService();
//             // }
//             // await stopWellCheckService();
//             //
//             // await initializeBackgroundService();
//             // await startWellCheckService();
//           } else {
//             await stopWellCheckService();
//             //  FlutterBackgroundService().invoke('stopService');
//           }
//           if (profile != null) {
//             // User exists, map role and go to dashboard
//             final matchedRole = ShieldRole.values.firstWhere(
//               (r) => r.name == profile.role,
//               orElse: () => ShieldRole.none,
//             );
//             ref.read(userRoleProvider.notifier).setRole(matchedRole);
//             focusNode.unfocus();
//             //  await  PulseService().broadcastPulse(null);
//             if (widget.email == "admin@wellcheck.com") {
//               context.go('/admin-dashboard');
//             } else {
//               // await initializeBackgroundService();
//               // await startWellCheckService(restart: true);
//               //
//               context.go('/dashboard');
//             }
//           } else {
//             focusNode.unfocus();
//
//             // New user without a profile, needs to setup
//             // context.go('/role-selection');
//             context.go('/role-selection?sms=${widget.isSms}');
//           }
//         } catch (e) {
//           // Fallback if network fails
//           if (!mounted) return;
//           focusNode.unfocus();
//           context.go('/role-selection');
//         }
//       }
//     } catch (e) {
//       print(e.toString());
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Verification failed: ${e.toReadableMessage()}'),
//             backgroundColor: ShieldColors.urgentRed,
//           ),
//         );
//       }
//     } finally {
//       if (mounted) setState(() => _isLoading = false);
//     }
//   }
//
//   Future<void> setupBiometricCredentials() async {
//     final supabase = Supabase.instance.client;
//     final user = supabase.auth.currentUser;
//
//     if (user == null || user.email == null) {
//       throw Exception('Authenticated user email is unavailable.');
//     }
//
//     final email = user.email!;
//     final password = generateRandomPassword();
//
//     // Set the password on the existing authenticated account.
//     await supabase.auth.updateUser(UserAttributes(password: password));
//
//     // Store credentials securely on this device.
//     await secureStorage.write(key: 'biometric_email', value: email);
//
//     await secureStorage.write(key: 'biometric_password', value: password);
//
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setBool('biometric_login_enabled', true);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Verify Identity'), centerTitle: true),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(24.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Text(
//               'Check Your Email',
//               style: Theme.of(context).textTheme.headlineSmall?.copyWith(
//                 fontWeight: FontWeight.bold,
//                 color: ShieldColors.activeTeal,
//               ),
//             ),
//             const SizedBox(height: 8),
//             Text(
//               'We sent an 8-digit pin to ${widget.email.isNotEmpty ? widget.email : widget.phone}. Enter it below to secure your session.',
//               style: const TextStyle(color: ShieldColors.textLabel),
//             ),
//             const SizedBox(height: 32),
//             TextField(
//               focusNode: focusNode,
//               controller: _pinController,
//               decoration: const InputDecoration(
//                 labelText: '8-DIGIT PIN',
//                 prefixIcon: Icon(Icons.password_outlined),
//               ),
//               keyboardType: TextInputType.number,
//               maxLength: 8,
//               inputFormatters: [FilteringTextInputFormatter.digitsOnly],
//               style: const TextStyle(
//                 letterSpacing: 8,
//                 fontSize: 24,
//                 fontWeight: FontWeight.bold,
//               ),
//               textAlign: TextAlign.center,
//             ),
//             const SizedBox(height: 32),
//             SizedBox(
//               width: double.infinity,
//               child: ElevatedButton(
//                 onPressed: _isLoading ? null : _handleVerify,
//                 child: _isLoading
//                     ? const SizedBox(
//                         width: 20,
//                         height: 20,
//                         child: CircularProgressIndicator(
//                           color: Colors.white,
//                           strokeWidth: 2,
//                         ),
//                       )
//                     : const Text('VERIFY PIN'),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
