import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/data/safety_repository.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/navigation/shield_router.dart';
import 'package:well_check_v3/features/safety/widgets/breathing_shield.dart';

class GlobalAlertOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const GlobalAlertOverlay({super.key, required this.child});

  @override
  ConsumerState<GlobalAlertOverlay> createState() => _GlobalAlertOverlayState();
}

class _GlobalAlertOverlayState extends ConsumerState<GlobalAlertOverlay> {
  bool _isAlertActive = false;
  String? _activeEventId;

  @override
  void dispose() {
    super.dispose();
  }

  void _triggerFullAlert(Map<String, dynamic> event) async {
    if (_isAlertActive) return;

    setState(() {
      _isAlertActive = true;
      _activeEventId = event['id'] as String?;
    });

    // Rapid haptic pulse
    HapticFeedback.vibrate();

    if (mounted) {
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: ShieldColors.urgentRed.withValues(alpha: 0.95),
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, anim1, anim2) {
          return _SirenDialog(
            eventId: _activeEventId ?? '',
            onDismiss: () {
              setState(() {
                _isAlertActive = false;
                _activeEventId = null;
              });
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // React to new events stream
    final profileAsync = ref.watch(currentUserProfileProvider);

    if (profileAsync.hasValue && profileAsync.value != null) {
      final familyId = profileAsync.value!.familyId;
      ref.listen<
        AsyncValue<List<Map<String, dynamic>>>
      >(familyEventsProvider(familyId), (previous, next) {
        if (next.hasValue && next.value != null) {
          final events = next.value!;
          if (events.isNotEmpty) {
            final latestEvent = events.first;

            final isResolved = latestEvent['metadata']?['status'] == 'resolved';
            if (latestEvent['event_type'] == 'sos' && !_isAlertActive && !isResolved) {
              final createdAt = DateTime.tryParse(latestEvent['created_at'] ?? '');
              if (createdAt != null &&
                  DateTime.now()
                          .toUtc()
                          .difference(createdAt.toUtc())
                          .inMinutes <
                      2) {
                _triggerFullAlert(latestEvent);
              }
            }
          }
        }
      });
    }

    return widget.child;
  }
}

/// Full-screen SOS siren dialog with acknowledgment broadcast
class _SirenDialog extends ConsumerStatefulWidget {
  final String eventId;
  final VoidCallback onDismiss;

  const _SirenDialog({required this.eventId, required this.onDismiss});

  @override
  ConsumerState<_SirenDialog> createState() => _SirenDialogState();
}

class _SirenDialogState extends ConsumerState<_SirenDialog> {
  bool _isHandled = false;
  String? _handlerName;
  Timer? _pollTimer;
  Timer? _hapticTimer;

  @override
  void initState() {
    super.initState();
    _startAckPolling();
    _startHapticPulse();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _hapticTimer?.cancel();
    super.dispose();
  }

  void _startHapticPulse() {
    _hapticTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isHandled) {
        timer.cancel();
        return;
      }
      HapticFeedback.heavyImpact();
    });
  }

  void _startAckPolling() {
    if (widget.eventId.isEmpty) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final result = await Supabase.instance.client
            .from('well_events')
            .select('metadata')
            .eq('id', widget.eventId)
            .maybeSingle();

        if (result != null) {
          final meta = result['metadata'] as Map<String, dynamic>?;
          if (meta != null && meta['status'] == 'resolved') {
            timer.cancel();
            _hapticTimer?.cancel();
            if (mounted) {
              setState(() {
                _isHandled = true;
                _handlerName = meta['resolved_by_name'] as String? ?? 'A family member';
              });
              // Auto-dismiss after 5 seconds once handled
              Future.delayed(const Duration(seconds: 5), () {
                if (mounted) widget.onDismiss();
              });
            }
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _acknowledgeAlert() async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;

      // Broadcast acknowledgment to ALL family members via DB update
      await Supabase.instance.client
          .from('well_events')
          .update({
            'metadata': {
              'status': 'resolved',
              'resolved_at': DateTime.now().toUtc().toIso8601String(),
              'resolved_by': profile.userId,
              'resolved_by_name': profile.fullName ?? 'Unknown',
            },
          })
          .eq('id', widget.eventId);

      _hapticTimer?.cancel();
      HapticFeedback.mediumImpact();

      if (mounted) {
        setState(() {
          _isHandled = true;
          _handlerName = profile.fullName ?? 'You';
        });
        // Auto-dismiss after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) widget.onDismiss();
        });
      }
    } catch (e) {
      debugPrint('Failed to acknowledge SOS: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Breathing shield — red urgent or green resolved
              BreathingShield(
                color: _isHandled ? ShieldColors.safeZoneGreen : Colors.white,
                size: 140,
                isUrgent: !_isHandled,
                isDeescalating: _isHandled,
                child: Icon(
                  _isHandled
                      ? Icons.check_circle_outline_rounded
                      : Icons.warning_amber_rounded,
                  color: _isHandled
                      ? Colors.white
                      : ShieldColors.urgentRed,
                  size: 80,
                ),
              ),
              const SizedBox(height: 32),

              // Title
              Text(
                _isHandled ? '✅ SOS HANDLED' : '🚨 EMERGENCY SOS',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),

              // Subtitle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0),
                child: Text(
                  _isHandled
                      ? '$_handlerName is handling this emergency.\nYou can now dismiss this alert.'
                      : 'A family member has triggered an\nemergency alert on the Shield network.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 48),

              if (!_isHandled) ...[
                // "I WILL HANDLE THIS" button
                SizedBox(
                  width: 280,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _acknowledgeAlert,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: ShieldColors.urgentRed,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: ShieldDesign.roundedTwelve,
                      ),
                    ),
                    child: const Text(
                      'I WILL HANDLE THIS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'All family members will be notified\nthat you are responding.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ] else ...[
                // DISMISS button (green)
                SizedBox(
                  width: 280,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: widget.onDismiss,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ShieldColors.safeZoneGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: ShieldDesign.roundedTwelve,
                      ),
                    ),
                    child: const Text(
                      'DISMISS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Extract stream logic to a Provider
final familyEventsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, familyId) {
      final repo = ref.watch(safetyRepositoryProvider);
      return repo.streamFamilyEvents(familyId);
    });
