import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/features/auth/login_screen.dart';

import '../../services/referral_service.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  void initState() {
    // _initDeepLinks();
    // WidgetsBinding.instance.addPostFrameCallback((_) async {
    //   await Future.delayed(Duration(seconds: 1));
    //   Navigator.push(
    //     context,
    //     MaterialPageRoute(builder: (context) => LoginScreen()),
    //   );
    // });
    super.initState();
  }

  bool deepLinkHandled = false;
  String? lastHandledLink;
  final _appLinks = AppLinks();
  StreamSubscription? sub;
  StreamSubscription<Uri>? _linkSub;

  Future<bool> _initDeepLinks() async {
    // bool handled = false;
    //
    // if (!deepLinkHandled) {
    //   // final uri = await _appLinks.getInitialLink();
    //   final uri = await _appLinks.getLatestLink();
    //   final lastestSt = await _appLinks.getInitialLinkString();
    //   print("lastestlastest");
    //   print(lastestSt);
    //   if (uri != null) {
    //     handled = await _handleDeepLink(uri);
    //   }
    //
    //   deepLinkHandled = true;
    // }
    //
    // _linkSub ??= _appLinks.uriLinkStream.listen(
    //   (uri) async {
    //     if (uri != null) {
    //       await _handleDeepLink(uri);
    //     }
    //   },
    //   onError: (err) {
    //     print("Deep link error: $err");
    //   },
    // );
    //
    // return handled;
    String? code = await ReferralService.instance.getReferralCode();
    debugPrint('Referral association code $code');
    return true;
  }

  _handleDeepLink(Uri uri) async {
    if (!mounted) return;
    //if (lastHandledLink == uri.toString()) return;
    lastHandledLink = uri.toString();
    print("lastHandledLink");
    print(lastHandledLink);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShieldColors.softMint,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Spacer(),
              // App Logo
              Container(
                width: 140,
                height: 140,
                decoration: const BoxDecoration(shape: BoxShape.circle),
                clipBehavior: Clip.antiAlias,
                child: Image.asset('assets/logo.png', fit: BoxFit.cover),
              ),
              const SizedBox(height: 48),
              Text(
                'Verified Safety,\nConnected Families.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ShieldColors.textBody,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Replace passive tracking with a\nreal-time safety pulse.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: ShieldColors.textLabel),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.push('/register'),
                  child: const Text('CREATE AN ACCOUNT'),
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => context.push('/login'),
                child: RichText(
                  text: const TextSpan(
                    text: 'Already have an account? ',
                    style: TextStyle(color: ShieldColors.textLabel),
                    children: [
                      TextSpan(
                        text: 'Sign In',
                        style: TextStyle(
                          color: ShieldColors.activeTeal,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
