import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/auth_repository.dart';
import 'package:url_launcher/url_launcher.dart';

enum OtpMethod { email, sms }

class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  final _formKey = GlobalKey<FormState>();

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> _handleRegister() async {
    setState(() => _isLoading = true);
    try {
      if (_formKey.currentState!.validate()) {
        final authRepo = ref.read(authRepositoryProvider);
        await authRepo.signInWithMagicLink(_emailController.text.trim(), '');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Registration PIN sent to your email.'),
            ),
          );
          // Force navigate to OTP verification view with the email payload
          context.push(
            '/otp?email=${Uri.encodeComponent(_emailController.text.trim())}',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage =
            'Unable to send verification code. Please try again.';
        if (e.toString().contains('rate limit')) {
          errorMessage =
              'Too many attempts. Please wait a few minutes before trying again.';
        } else if (e.toString().contains('Invalid email')) {
          errorMessage = 'Please enter a valid email address.';
        } else if (e.toString().contains('over_email_send_rate_limit')) {
          errorMessage =
              'Too many attempts. Please wait a few minutes before trying again';
        } else if (e.toString().toLowerCase().contains('no address')) {
          errorMessage = 'No internet connection. Please check your network.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
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
      appBar: AppBar(
        title: const Text('Create Your Shield'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Secure Your Family',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ShieldColors.activeTeal,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Initialize your family shield with an encrypted root account.',
                style: TextStyle(color: ShieldColors.textLabel),
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _emailController,
                textCapitalization: TextCapitalization.none,
                onChanged: (value) {
                  final lowerCaseValue = value.toLowerCase();
                  if (value != lowerCaseValue) {
                    _emailController.value = _emailController.value.copyWith(
                      text: lowerCaseValue,
                      selection: TextSelection.collapsed(
                        offset: lowerCaseValue.length,
                      ),
                    );
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'EMAIL ADDRESS',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your email address';
                  }

                  final emailRegex = RegExp(
                    r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$',
                  );

                  if (!emailRegex.hasMatch(value.trim())) {
                    return 'Please enter a valid email address';
                  }

                  return null;
                },
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('CREATE ACCOUNT'),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    const Text(
                      'By creating an account, you agree to our ',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    GestureDetector(
                      onTap: () => _launchUrl(
                        'https://well-check.com/terms-conditions/',
                      ),
                      child: const Text(
                        'Terms of Service',
                        style: TextStyle(
                          fontSize: 12,
                          color: ShieldColors.activeTeal,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const Text(
                      ' and ',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    GestureDetector(
                      onTap: () =>
                          _launchUrl('https://well-check.com/privacy-policy/'),
                      child: const Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontSize: 12,
                          color: ShieldColors.activeTeal,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const Text(
                      '.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// class RegistrationScreen extends ConsumerStatefulWidget {
//   const RegistrationScreen({super.key});
//
//   @override
//   ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
// }
//
// class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
//   final _emailController = TextEditingController();
//   final _emailFocus = FocusNode();
//   final _phoneFocus = FocusNode();
//   bool _isLoading = false;
//   final _formKey = GlobalKey<FormState>();
//   OtpMethod _otpMethod = OtpMethod.email;
//   final _phoneController = TextEditingController();
//
//   @override
//   void dispose() {
//     _phoneController.dispose();
//     _emailController.dispose();
//     super.dispose();
//   }
//
//   Future<void> _launchUrl(String url) async {
//     try {
//       final uri = Uri.parse(url);
//       if (await canLaunchUrl(uri)) {
//         await launchUrl(uri, mode: LaunchMode.externalApplication);
//       }
//     } catch (e) {
//       print(e.toString());
//     }
//   }
//
//   Future<void> _handleRegister() async {
//     setState(() => _isLoading = true);
//     try {
//       if (_formKey.currentState!.validate()) {
//         final authRepo = ref.read(authRepositoryProvider);
//         final isSms = _otpMethod == OtpMethod.sms;
//         final email = _emailController.text.trim();
//         final phone = _phoneController.text.trim();
//         await authRepo.signInWithMagicLink(
//           _emailController.text.trim(),
//           '',
//           isSms,
//           phone,
//         );
//
//         // if (mounted) {
//         //   ScaffoldMessenger.of(context).showSnackBar(
//         //     const SnackBar(
//         //       content: Text('Registration PIN sent to your email.'),
//         //     ),
//         //   );
//         //   // Force navigate to OTP verification view with the email payload
//         //   context.push(
//         //     '/otp?email=${Uri.encodeComponent(_emailController.text.trim())}',
//         //   );
//         // }
//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Text(
//                 isSms
//                     ? 'Registration PIN sent to your phone.'
//                     : 'Registration PIN sent to your email.',
//               ),
//             ),
//           );
//           context.push(
//             '/otp?email=${Uri.encodeComponent(email)}'
//             '&phone=${Uri.encodeComponent(phone)}'
//             '&sms=$isSms',
//           );
//         }
//       }
//     } catch (e) {
//       if (mounted) {
//         String errorMessage =
//             'Unable to send verification code. Please try again.';
//         if (e.toString().contains('rate limit')) {
//           errorMessage =
//               'Too many attempts. Please wait a few minutes before trying again.';
//         } else if (e.toString().contains('Invalid email')) {
//           errorMessage = 'Please enter a valid email address.';
//         } else if (e.toString().contains('over_email_send_rate_limit')) {
//           errorMessage =
//               'Too many attempts. Please wait a few minutes before trying again';
//         } else if (e.toString().toLowerCase().contains('no address')) {
//           errorMessage = 'No internet connection. Please check your network.';
//         }
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text(errorMessage),
//             backgroundColor: ShieldColors.urgentRed,
//           ),
//         );
//       }
//     } finally {
//       if (mounted) setState(() => _isLoading = false);
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Create Your Shield'),
//         centerTitle: true,
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(24.0),
//         child: Form(
//           key: _formKey,
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 'Secure Your Family',
//                 style: Theme.of(context).textTheme.headlineSmall?.copyWith(
//                   fontWeight: FontWeight.bold,
//                   color: ShieldColors.activeTeal,
//                 ),
//               ),
//               const SizedBox(height: 8),
//               const Text(
//                 'Initialize your family shield with an encrypted root account.',
//                 style: TextStyle(color: ShieldColors.textLabel),
//               ),
//               const SizedBox(height: 24),
//               Text(
//                 'VERIFY WITH',
//                 style: Theme.of(context).textTheme.labelMedium?.copyWith(
//                   color: ShieldColors.textLabel,
//                 ),
//               ),
//               const SizedBox(height: 8),
//               SizedBox(
//                 width: double.infinity,
//                 child: SegmentedButton<OtpMethod>(
//                   showSelectedIcon: false,
//                   style: ButtonStyle(
//                     side: WidgetStatePropertyAll(
//                       BorderSide(color: Colors.grey.shade300),
//                     ),
//                     backgroundColor: WidgetStateProperty.resolveWith((states) {
//                       return states.contains(WidgetState.selected)
//                           ? Theme.of(context).colorScheme.primary
//                           : Colors.transparent;
//                     }),
//                     foregroundColor: WidgetStateProperty.resolveWith((states) {
//                       return states.contains(WidgetState.selected)
//                           ? Colors.white
//                           : Colors.grey.shade700;
//                     }),
//                     shape: WidgetStatePropertyAll(
//                       RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(10),
//                       ),
//                     ),
//                     padding: const WidgetStatePropertyAll(
//                       EdgeInsets.symmetric(vertical: 12),
//                     ),
//                   ),
//                   segments: const [
//                     ButtonSegment(
//                       value: OtpMethod.email,
//                       icon: Icon(Icons.email_outlined),
//                       label: Text('Email OTP'),
//                     ),
//                     ButtonSegment(
//                       value: OtpMethod.sms,
//                       icon: Icon(Icons.sms_outlined),
//                       label: Text('SMS OTP'),
//                     ),
//                   ],
//                   selected: {_otpMethod},
//                   onSelectionChanged: _isLoading
//                       ? null
//                       : (selection) {
//                           setState(() => _otpMethod = selection.first);
//                           FocusManager.instance.primaryFocus?.unfocus();
//                           if (_otpMethod == OtpMethod.email) {
//                             _emailFocus.requestFocus();
//                           }
//                           if (_otpMethod == OtpMethod.sms) {
//                             _phoneFocus.requestFocus();
//                           }
//                         },
//                 ),
//               ),
//
//               if (_otpMethod == OtpMethod.email) ...[
//                 const SizedBox(height: 24),
//                 TextFormField(
//                   controller: _emailController,
//                   focusNode: _emailFocus,
//                   textCapitalization: TextCapitalization.none,
//                   onChanged: (value) {
//                     final lowerCaseValue = value.toLowerCase();
//                     if (value != lowerCaseValue) {
//                       _emailController.value = _emailController.value.copyWith(
//                         text: lowerCaseValue,
//                         selection: TextSelection.collapsed(
//                           offset: lowerCaseValue.length,
//                         ),
//                       );
//                     }
//                   },
//                   decoration: const InputDecoration(
//                     labelText: 'EMAIL ADDRESS',
//                     prefixIcon: Icon(Icons.email_outlined),
//                   ),
//                   validator: (value) {
//                     if (value == null || value.trim().isEmpty) {
//                       return 'Please enter your email address';
//                     }
//
//                     final emailRegex = RegExp(
//                       r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$',
//                     );
//
//                     if (!emailRegex.hasMatch(value.trim())) {
//                       return 'Please enter a valid email address';
//                     }
//
//                     return null;
//                   },
//                   keyboardType: TextInputType.emailAddress,
//                 ),
//               ],
//               if (_otpMethod == OtpMethod.sms) ...[
//                 const SizedBox(height: 24),
//                 TextFormField(
//                   focusNode: _phoneFocus,
//                   controller: _phoneController,
//                   keyboardType: TextInputType.phone,
//                   decoration: InputDecoration(
//                     labelText: 'PHONE NUMBER',
//                     hintText: '+919876543210',
//                     hintStyle: TextStyle(color: Colors.grey.shade400),
//                     prefixIcon: Icon(Icons.phone_outlined),
//                   ),
//                   validator: (value) {
//                     if (_otpMethod != OtpMethod.sms) return null;
//                     if (value == null || value.trim().isEmpty) {
//                       return 'Please enter your phone number';
//                     }
//                     if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value.trim())) {
//                       return 'Use international format, e.g. +919876543210';
//                     }
//                     return null;
//                   },
//                 ),
//               ],
//               // const SizedBox(height: 32),
//               const SizedBox(height: 32),
//               // TextFormField(
//               //   controller: _emailController,
//               //   textCapitalization: TextCapitalization.none,
//               //   onChanged: (value) {
//               //     final lowerCaseValue = value.toLowerCase();
//               //     if (value != lowerCaseValue) {
//               //       _emailController.value = _emailController.value.copyWith(
//               //         text: lowerCaseValue,
//               //         selection: TextSelection.collapsed(
//               //           offset: lowerCaseValue.length,
//               //         ),
//               //       );
//               //     }
//               //   },
//               //   decoration: const InputDecoration(
//               //     labelText: 'EMAIL ADDRESS',
//               //     prefixIcon: Icon(Icons.email_outlined),
//               //   ),
//               //   validator: (value) {
//               //     if (value == null || value.trim().isEmpty) {
//               //       return 'Please enter your email address';
//               //     }
//               //
//               //     final emailRegex = RegExp(
//               //       r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$',
//               //     );
//               //
//               //     if (!emailRegex.hasMatch(value.trim())) {
//               //       return 'Please enter a valid email address';
//               //     }
//               //
//               //     return null;
//               //   },
//               //   keyboardType: TextInputType.emailAddress,
//               // ),
//               // const SizedBox(height: 32),
//               SizedBox(
//                 width: double.infinity,
//                 child: ElevatedButton(
//                   onPressed: _isLoading ? null : _handleRegister,
//                   child: _isLoading
//                       ? const SizedBox(
//                           width: 20,
//                           height: 20,
//                           child: CircularProgressIndicator(
//                             color: Colors.white,
//                             strokeWidth: 2,
//                           ),
//                         )
//                       : const Text('CREATE ACCOUNT'),
//                 ),
//               ),
//               const SizedBox(height: 24),
//               Center(
//                 child: Wrap(
//                   alignment: WrapAlignment.center,
//                   children: [
//                     const Text(
//                       'By creating an account, you agree to our ',
//                       style: TextStyle(fontSize: 12, color: Colors.grey),
//                     ),
//                     GestureDetector(
//                       onTap: () => _launchUrl(
//                         'https://well-check.com/terms-conditions/',
//                       ),
//                       child: const Text(
//                         'Terms of Service',
//                         style: TextStyle(
//                           fontSize: 12,
//                           color: ShieldColors.activeTeal,
//                           decoration: TextDecoration.underline,
//                         ),
//                       ),
//                     ),
//                     const Text(
//                       ' and ',
//                       style: TextStyle(fontSize: 12, color: Colors.grey),
//                     ),
//                     GestureDetector(
//                       onTap: () =>
//                           _launchUrl('https://well-check.com/privacy-policy/'),
//                       child: const Text(
//                         'Privacy Policy',
//                         style: TextStyle(
//                           fontSize: 12,
//                           color: ShieldColors.activeTeal,
//                           decoration: TextDecoration.underline,
//                         ),
//                       ),
//                     ),
//                     const Text(
//                       '.',
//                       style: TextStyle(fontSize: 12, color: Colors.grey),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
