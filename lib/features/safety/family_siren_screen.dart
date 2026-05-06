import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';

class FamilySirenScreen extends ConsumerWidget {
  final String? eventId;

  const FamilySirenScreen({super.key, this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ShieldColors.urgentRed,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Pulsing SOS Visual
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 1.0, end: 1.2),
                duration: const Duration(seconds: 1),
                curve: Curves.easeInOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.campaign_outlined,
                          size: 100,
                          color: ShieldColors.urgentRed,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 64),
              const Text(
                'SIREN OVERRIDE\nACTIVE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'MAX VOLUME FORCED.\nEMERGENCY BROADCASTING.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    // Resolve the SOS event in the database
                    if (eventId != null && eventId!.isNotEmpty) {
                      try {
                        final profile = await ref
                            .read(currentUserProfileProvider.future);
                        await Supabase.instance.client
                            .from('well_events')
                            .update({
                              'metadata': {
                                'status': 'resolved',
                                'resolved_at':
                                    DateTime.now().toUtc().toIso8601String(),
                                'resolved_by':
                                    profile?.userId ?? 'unknown',
                                'resolved_by_name':
                                    profile?.fullName ?? 'Siren Operator',
                              },
                            })
                            .eq('id', eventId!);
                      } catch (e) {
                        debugPrint('Failed to resolve SOS event: $e');
                      }
                    }

                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: ShieldColors.urgentRed,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                  ),
                  child: const Text(
                    'ACKNOWLEDGE & SILENCE',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
