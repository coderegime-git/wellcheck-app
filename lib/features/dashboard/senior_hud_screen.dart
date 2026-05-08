import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/data/safety_repository.dart';
import 'package:well_check_v3/core/ai/wellness_ai_provider.dart';
import 'package:well_check_v3/features/command_center/contacts_sheet.dart';
import 'package:well_check_v3/features/command_center/medications_sheet.dart';
import 'package:well_check_v3/features/command_center/calendar_sheet.dart';
import 'package:well_check_v3/features/messaging/family_chat_screen.dart';
import 'package:well_check_v3/features/profile/profile_settings_view.dart';
import 'package:well_check_v3/features/dashboard/widgets/pending_actions_card.dart';
import 'package:url_launcher/url_launcher.dart';

class SeniorHUD extends ConsumerStatefulWidget {
  const SeniorHUD({super.key});

  @override
  ConsumerState<SeniorHUD> createState() => _SeniorHUDState();
}

class _SeniorHUDState extends ConsumerState<SeniorHUD>
    with SingleTickerProviderStateMixin {
  bool _isCheckingIn = false;
  bool _sosCountdownActive = false;
  int _sosCountdown = 5;
  Timer? _sosTimer;

  // Voice assistant state
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isListening = false;
  bool _isProcessing = false;
  String _lastQuestion = '';
  String _lastResponse = '';
  String _statusText = 'Tap to speak';

  // Pulsing animation for mic aura
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initVoice();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initVoice() async {
    try {
      await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (_isListening && _lastQuestion.isNotEmpty) {
              _processWithAi(_lastQuestion);
            }
            if (mounted) {
              setState(() => _isListening = false);
              _pulseController.stop();
            }
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isListening = false;
              _statusText = 'Could not hear you. Tap to try again.';
            });
            _pulseController.stop();
          }
        },
      );
    } catch (e) {
      debugPrint('[Voice] Speech init failed: $e');
    }

    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _tts.setCompletionHandler(() {
        if (mounted) setState(() => _statusText = 'Tap to speak');
      });
    } catch (e) {
      debugPrint('[Voice] TTS init failed: $e');
    }
  }

  void _startListening() async {
    HapticFeedback.mediumImpact();
    await _tts.stop();

    if (_isListening) {
      _speech.stop();
      setState(() => _isListening = false);
      _pulseController.stop();
      return;
    }

    setState(() {
      _isListening = true;
      _lastQuestion = '';
      _lastResponse = '';
      _statusText = 'Listening...';
    });
    _pulseController.repeat(reverse: true);

    await _speech.listen(
      onResult: (result) {
        if (mounted) {
          setState(() => _lastQuestion = result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
    );
  }

  Future<void> _processWithAi(String question) async {
    setState(() {
      _isProcessing = true;
      _statusText = 'Thinking...';
    });

    try {
      final ai = ref.read(wellnessAiProvider);
      final profile = await ref.read(currentUserProfileProvider.future);

      if (profile == null) {
        setState(() {
          _lastResponse = 'I could not load your profile. Please try again.';
          _isProcessing = false;
          _statusText = 'Tap to speak';
        });
        return;
      }

      final response = await ai.chat(question, profile.familyId);

      if (mounted) {
        setState(() {
          _lastResponse = response;
          _isProcessing = false;
          _statusText = 'Speaking...';
        });
        await _tts.speak(response);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastResponse = 'Something went wrong. Please try again.';
          _isProcessing = false;
          _statusText = 'Tap to speak';
        });
      }
    }
  }

  @override
  void dispose() {
    _sosTimer?.cancel();
    _pulseController.dispose();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  // ── Check Status: update profile last_seen + GPS ──
  Future<void> _performCheckIn() async {
    setState(() => _isCheckingIn = true);
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile');

      // Get GPS
      Position? position;
      bool gpsSuccess = false;
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          var perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.denied) {
            perm = await Geolocator.requestPermission();
          }
          if (perm == LocationPermission.whileInUse ||
              perm == LocationPermission.always) {
            position = await Geolocator.getCurrentPosition(
              timeLimit: const Duration(seconds: 8),
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
              ),
            );
            gpsSuccess = true;
          }
        }
      } catch (_) {
        try {
          // fallback
          position = await Geolocator.getLastKnownPosition();
          if (position != null) gpsSuccess = true;
        } catch (_) {}
      }

      final lat = position?.latitude ?? 0.0;
      final lng = position?.longitude ?? 0.0;

      // Update profile with fresh last_seen
      await Supabase.instance.client
          .from('profiles')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', profile.userId);
      int level =
          100; // Safe default for simulators and aggressive background iOS policies
      try {
        final battery = Battery();
        level = await battery.batteryLevel;
      } catch (e) {
        debugPrint(
          'Battery info not available over isolate, using default: $e',
        );
      }
      // Insert well_event for family visibility
      await Supabase.instance.client.from('well_events').insert({
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'user_name': profile.fullName,
        'event_type': 'check_in',
        'title': 'Status Check-In',
        'description': 'checked in.',
        'latitude': lat,
        'longitude': lng,
        'battery_level': level, // Platform battery TBD
        // 'created_by': profile.userId,
      });

      // Also insert into check_ins table
      await Supabase.instance.client.from('check_ins').insert({
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'latitude': lat,
        'longitude': lng,
        'status_message': 'Status check-in from Protected Portal',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              gpsSuccess
                  ? '✓ Status broadcast to family!'
                  : '✓ Status broadcast (GPS unavailable)',
            ),
            backgroundColor: gpsSuccess
                ? ShieldColors.safeZoneGreen
                : Colors.orange,
          ),
        );
      }
    } catch (e) {
      print(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Check-in failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingIn = false);
    }
  }

  // ── SOS: 5-second haptic countdown then fire ──
  void _startSosCountdown() {
    if (_sosCountdownActive) {
      // Cancel if tapped again
      _sosTimer?.cancel();
      setState(() {
        _sosCountdownActive = false;
        _sosCountdown = 5;
      });
      return;
    }

    setState(() {
      _sosCountdownActive = true;
      _sosCountdown = 5;
    });

    _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      // Haptic tick
      HapticFeedback.heavyImpact();

      if (_sosCountdown <= 1) {
        timer.cancel();
        try {
          final profile = await ref.read(currentUserProfileProvider.future);
          if (profile == null) {
            debugPrint(
              '[SOS] Profile is null — user has no family_members row',
            );
            if (mounted) {
              setState(() {
                _sosCountdownActive = false;
                _sosCountdown = 5;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    '⚠️ SOS FAILED: No family profile found. Please re-join a family first.',
                  ),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 5),
                ),
              );
            }
            return;
          }

          await ref
              .read(safetyRepositoryProvider)
              .triggerSiren(
                profile.familyId,
                'Protected member pressed Emergency Help (5s countdown completed)',
              );

          if (mounted) {
            setState(() {
              _sosCountdownActive = false;
              _sosCountdown = 5;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🚨 EMERGENCY ALERT SENT! Help is on the way.'),
                backgroundColor: ShieldColors.urgentRed,
                duration: Duration(seconds: 5),
              ),
            );
          }
        } catch (e) {
          debugPrint('[SOS] triggerSiren failed: $e');
          if (mounted) {
            setState(() {
              _sosCountdownActive = false;
              _sosCountdown = 5;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('⚠️ SOS FAILED: $e'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          setState(() => _sosCountdown--);
        }
      }
    });
  }

  Future<void> _launchUrl(
    BuildContext context,
    String scheme,
    String path,
  ) async {
    final Uri url = Uri(scheme: scheme, path: path);
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch application.')),
        );
      }
    }
  }

  // ── RBAC: Stripped-down elder menu (no admin/monitor links) ──
  void _showElderMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: ShieldColors.backgroundWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'My Menu',
              style: Theme.of(
                ctx,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _elderMenuItem(ctx, Icons.family_restroom, 'View Family', () {
              Navigator.pop(ctx);
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const ContactsSheet(),
              );
            }),
            _elderMenuItem(ctx, Icons.medical_services, 'Medications', () {
              Navigator.pop(ctx);

              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const MedicationsSheet(),
              );
            }),
            _elderMenuItem(ctx, Icons.calendar_month, 'Calendar', () {
              Navigator.pop(ctx);
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const CalendarSheet(),
              );
            }),
            _elderMenuItem(ctx, Icons.chat, 'Family Chat', () {
              Navigator.pop(ctx);
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const FamilyChatScreen(),
              );
            }),
            _elderMenuItem(ctx, Icons.phone, 'Call Family', () {
              Navigator.pop(ctx);
              _launchUrl(context, 'tel', '5551234567');
            }),
            _elderMenuItem(ctx, Icons.person_outline, 'My Profile', () {
              Navigator.pop(ctx);
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const ProfileSettingsView(),
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _elderMenuItem(
    BuildContext ctx,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: ShieldColors.activeTeal.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: ShieldColors.activeTeal),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final firstName = profileAsync.value?.fullName?.split(' ').first ?? 'User';

    return Scaffold(
      backgroundColor: const Color(0xFF131A2A),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 32),
                      // Header with protected status
                      Text(
                        "$firstName's Portal",
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: ShieldColors.activeTeal.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'PROTECTED MEMBER',
                          style: TextStyle(
                            color: ShieldColors.activeTeal,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24.0),
                        child: PendingActionsCard(),
                      ),

                      const Spacer(flex: 2),

                      // AI Voice Assistant — animated pulsing aura
                      GestureDetector(
                        onTap: _startListening,
                        child: Column(
                          children: [
                            AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _isListening
                                      ? _pulseAnimation.value
                                      : 1.0,
                                  child: Container(
                                    width: 180,
                                    height: 180,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _isListening
                                            ? ShieldColors.urgentRed
                                            : _isProcessing
                                            ? const Color(0xFF6B4EE6)
                                            : ShieldColors.activeTeal,
                                        width: 3,
                                      ),
                                      color:
                                          (_isListening
                                                  ? ShieldColors.urgentRed
                                                  : _isProcessing
                                                  ? const Color(0xFF6B4EE6)
                                                  : ShieldColors.activeTeal)
                                              .withValues(alpha: 0.1),
                                    ),
                                    child: Icon(
                                      _isListening
                                          ? Icons.hearing
                                          : _isProcessing
                                          ? Icons.auto_awesome
                                          : Icons.mic,
                                      size: 56,
                                      color: _isListening
                                          ? ShieldColors.urgentRed
                                          : _isProcessing
                                          ? const Color(0xFF6B4EE6)
                                          : ShieldColors.activeTeal,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _statusText,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            // Show question and response
                            if (_lastQuestion.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: ShieldDesign.roundedTwelve,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '🗣️ ',
                                          style: TextStyle(fontSize: 14),
                                        ),
                                        Expanded(
                                          child: Text(
                                            _lastQuestion,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_lastResponse.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            '🤖 ',
                                            style: TextStyle(fontSize: 14),
                                          ),
                                          Expanded(
                                            child: Text(
                                              _lastResponse,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (_isProcessing)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: LinearProgressIndicator(
                                          backgroundColor: Colors.white24,
                                          color: Color(0xFF6B4EE6),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const Spacer(flex: 1),

                      // Action Buttons
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C2438),
                                borderRadius: ShieldDesign.roundedTwelve,
                              ),
                              child: Text(
                                'Welcome $firstName.\nYou are protected by the Family Shield.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                      height: 1.4,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // View Family
                            _actionButton(
                              icon: Icons.family_restroom,
                              label: 'View Family',
                              color: ShieldColors.activeTeal,
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => const ContactsSheet(),
                                );
                              },
                            ),
                            const SizedBox(height: 10),

                            // Check Status (manual check-in)
                            _actionButton(
                              icon: _isCheckingIn
                                  ? Icons.hourglass_top
                                  : Icons.health_and_safety,
                              label: _isCheckingIn
                                  ? 'Broadcasting...'
                                  : 'Check Status',
                              color: const Color(0xFF3366FF),
                              onPressed: _isCheckingIn ? null : _performCheckIn,
                            ),
                            const SizedBox(height: 10),

                            // Send Message
                            _actionButton(
                              icon: Icons.message_rounded,
                              label: 'Send Message',
                              color: const Color(0xFF1C2438),
                              border: true,
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  useSafeArea: true,

                                  backgroundColor: Colors.transparent,
                                  builder: (_) => const FamilyChatScreen(),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Bottom buttons — EMERGENCY + MENU (wrapped in SafeArea)
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24.0,
                            vertical: 8.0,
                          ),
                          child: Row(
                            children: [
                              // Emergency button with haptic countdown
                              Expanded(
                                child: SizedBox(
                                  height: 64,
                                  child: ElevatedButton(
                                    onPressed: _startSosCountdown,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _sosCountdownActive
                                          ? Colors.orange
                                          : ShieldColors.urgentRed,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            ShieldDesign.roundedTwelve,
                                      ),
                                      elevation: 8,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.warning_rounded,
                                          size: 28,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            _sosCountdownActive
                                                ? 'CANCEL ($_sosCountdown)'
                                                : 'EMERGENCY',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              letterSpacing: 1.5,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Menu button — rectangular style
                              SizedBox(
                                width: 64,
                                height: 64,
                                child: ElevatedButton(
                                  onPressed: _showElderMenu,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3366FF),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: ShieldDesign.roundedTwelve,
                                    ),
                                    elevation: 4,
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: const Icon(
                                    Icons.grid_view_rounded,
                                    color: Colors.white,
                                    size: 26,
                                  ),
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
          },
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    bool border = false,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: border ? const Color(0xFF1C2438) : color,
          foregroundColor: Colors.white,
          side: border
              ? const BorderSide(color: ShieldColors.activeTeal, width: 1.5)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: ShieldDesign.roundedTwelve,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
