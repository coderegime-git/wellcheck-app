import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

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
                width: 150,
                height: 150,
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
