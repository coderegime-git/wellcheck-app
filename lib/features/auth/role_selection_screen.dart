import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/navigation/shield_router.dart';
import 'package:well_check_v3/core/data/auth_repository.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';

import '../safety/services/pulse_service.dart';

class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Define Your Role')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Welcome to Shield',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ShieldColors.activeTeal,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Are you establishing a new protection network, or joining an existing one?',
                style: TextStyle(color: ShieldColors.textLabel),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              _RoleCard(
                title: 'Start a New Family Shield',
                subtitle: 'Become the Leader and invite your loved ones.',
                icon: Icons.shield_outlined,
                onTap: () => _createFamilyAndGo(context, ref),
              ),
              const SizedBox(height: 16),
              _RoleCard(
                title: 'Join with Code',
                subtitle: 'I have a 6-digit invite PIN from a Family Leader.',
                icon: Icons.pin_outlined,
                onTap: () => context.push('/join-with-code'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createFamilyAndGo(BuildContext context, WidgetRef ref) async {
    try {
      ref.read(userRoleProvider.notifier).setRole(ShieldRole.leader);
      final authRepo = ref.read(authRepositoryProvider);

      await authRepo.createFamilyWithRole('My Family Shield', 'leader');
      ref.invalidate(currentUserProfileProvider);
      await  PulseService().broadcastPulse(null);

      if (context.mounted) {
        context.go('/profile-setup');
      }
    } catch (e) {
      print(e.toString());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed setting role: $e'),
            backgroundColor: ShieldColors.urgentRed,
          ),
        );
        // Fallback go to profile setup
        context.go('/profile-setup');
      }
    }
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(icon, size: 32, color: ShieldColors.activeTeal),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
