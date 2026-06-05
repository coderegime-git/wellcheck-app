import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
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

import '../../core/data/medication_provider.dart';
import '../../core/data/tools_repository.dart';
import '../../core/notifications/push_notification_service.dart';
import '../safety/services/location_service.dart';
import '../safety/services/pulse_service.dart';

class SeniorHUD extends ConsumerStatefulWidget {
  const SeniorHUD({super.key});

  @override
  ConsumerState<SeniorHUD> createState() => _SeniorHUDState();
}

class _SeniorHUDState extends ConsumerState<SeniorHUD>
    with SingleTickerProviderStateMixin {
  bool _isCheckingIn = false;
  bool imOkayLoad = false;
  bool _sosCountdownActive = false;
  int _sosCountdown = 5;
  Timer? _sosTimer;
  bool _loadedMissedCheckin = false;
  bool load = true;

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
  String? _loggingMedicationId;
  Map<String, dynamic>? missedCheckIn;
  final notesController = TextEditingController();
  final notesFocus = FocusNode();
  late Stream<List<Map<String, dynamic>>> _missedStream;

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final granted = await LocationService.requestLocationPermissions(context);
      if (!granted) {
        // Optionally show a snackbar/dialog explaining why it's needed
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location access is required for your safety. Please enable it in Settings.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;
      print("asas");

      await PulseService().broadcastPulse(profile.userId);
    });
  }

  Future<List<Map<String, dynamic>>> getMissedCheckIns(String userId) async {
    final missed = await Supabase.instance.client
        .from('check_ins')
        .select()
        .eq('user_id', userId)
        .eq('status_message', 'Missed check-in')
        .order('created_at', ascending: false)
        .limit(1);

    return List<Map<String, dynamic>>.from(missed);
  }

  Stream<List<Map<String, dynamic>>> streamMissedCheckIns(String userId) {
    return Supabase.instance.client
        .from('check_ins')
        .stream(primaryKey: ['id'])
        .map((rows) {
          final missed = rows
              .where(
                (row) =>
                    row['user_id'] == userId &&
                    row['status_message'] == 'Missed check-in' &&
                    (row['acknowledged'] ?? false) == false,
              )
              .toList();

          missed.sort(
            (a, b) => DateTime.parse(
              b['created_at'],
            ).compareTo(DateTime.parse(a['created_at'])),
          );

          return missed.take(1).toList();
        });
  }

  Future<void> _logDose(Medication med) async {
    if (_loggingMedicationId != null) return;

    setState(() {
      _loggingMedicationId = med.id;
    });

    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;

      final now = DateTime.now().toUtc();
      int batteryLevel =
          100; // Safe default for simulators and aggressive background iOS policies
      try {
        final battery = Battery();
        batteryLevel = await battery.batteryLevel;
      } catch (e) {
        debugPrint(
          'Battery info not available over isolate, using default: $e',
        );
      }

      await Supabase.instance.client.from('dose_logs').insert({
        'medication_id': med.id,
        'user_id': med.assignedTo,
        'family_id': profile.familyId,
        'scheduled_at': now.toIso8601String(),
        'taken_at': now.toIso8601String(),
        'status': 'taken',
      });
      final medData = await Supabase.instance.client
          .from('medications')
          .select('scheduled_at, recurrence, days_of_week')
          .eq('id', med.id)
          .single();

      DateTime nextDate = DateTime.parse(medData['scheduled_at']);

      switch (medData['recurrence']) {
        case 'daily':
          nextDate = nextDate.add(const Duration(days: 1));
          break;

        case 'every_other_day':
          nextDate = nextDate.add(const Duration(days: 2));
          break;

        case 'weekly':
          final days = List<int>.from(medData['days_of_week'] ?? [])..sort();

          if (days.isEmpty) {
            nextDate = nextDate.add(const Duration(days: 7));
          } else {
            final currentDay = nextDate.weekday % 7;

            int? found;

            for (final d in days) {
              if (d > currentDay) {
                found = d;
                break;
              }
            }

            found ??= days.first + 7;

            nextDate = nextDate.add(Duration(days: found - currentDay));
          }

          break;

        case 'monthly':
          nextDate = DateTime(
            nextDate.year,
            nextDate.month + 1,
            nextDate.day,
            nextDate.hour,
            nextDate.minute,
          );
          break;

        default:
          break;
      }
      await Supabase.instance.client
          .from('medications')
          .update({
            'scheduled_at': nextDate.toUtc().toIso8601String(),

            'reminder_sent': false,
            'reminder_sent_at': null,
          })
          .eq('id', med.id);
      await Supabase.instance.client.from('well_events').insert({
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'event_type': 'medication_logged',
        'title': 'Medication Taken',
        'description':
            '${profile.fullName ?? 'Someone'} logged ${med.medicationName} (${med.dosage})',
        'battery_level': batteryLevel,
      });

      // IMPORTANT
      ref.invalidate(allDoseLogsProvider);
      ref.invalidate(familyMedicationsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ ${med.medicationName} dose logged!'),
            backgroundColor: ShieldColors.safeZoneGreen,
          ),
        );
      }

      // Send push
      final members = await Supabase.instance.client
          .from('family_members')
          .select('user_id')
          .eq('family_id', profile.familyId);

      for (final m in members) {
        final targetUserId = m['user_id'];

        if (targetUserId == profile.userId) continue;

        try {
          await Supabase.instance.client.functions.invoke(
            'push-router',
            body: {
              "target_user_id": targetUserId,
              "title": "Medications",
              "body":
                  "${profile.fullName ?? 'Someone'}: ${med.medicationName} dose logged",
              "action": "log_dose",
            },
          );
        } catch (e) {
          debugPrint("Push failed: $e");
        }
      }
    } catch (e) {
      debugPrint('[Medication] Error logging dose: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error logging dose: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loggingMedicationId = null;
        });
      }
    }
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
      await PulseService().broadcastPulse(null);
      if (!mounted) return;
      await PushNotificationService.initialize();
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
    final profile = await ref.read(currentUserProfileProvider.future);
    if (profile == null) return;
    _missedStream = streamMissedCheckIns(profile.userId);
    print("profile.userId");
    print("profile.userId");
    print(profile.userId);
    if (mounted) {
      setState(() {
        load = false;
      });
    }
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();

    // if (_loadedMissedCheckin) return;
    // _loadedMissedCheckin = true;
    //
    // _loadMissedCheckin();
  }

  // Future<void> _loadMissedCheckin() async {
  //   final profile = await ref.read(currentUserProfileProvider.future);
  //
  //   if (profile == null) return;
  //
  //   final missed = await getMissedCheckIn(profile.userId);
  //
  //   if (!mounted) return;
  //
  //   setState(() {
  //     missedCheckIn = missed;
  //   });
  // }

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
    double lat = 0.0;
    double lng = 0.0;
    int level = 100;
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

      lat = position?.latitude ?? 0.0;
      lng = position?.longitude ?? 0.0;

      // Update profile with fresh last_seen
      await Supabase.instance.client
          .from('profiles')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', profile.userId);
      // Safe default for simulators and aggressive background iOS policies
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
        'status_message': '${profile.fullName} -Status check-in',
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
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile');
      final members = await Supabase.instance.client
          .from('family_members')
          .select('user_id, role')
          .eq('family_id', profile.familyId);
      final response =
          await Supabase.instance.client.from('live_locations').upsert({
            'user_id': profile.userId,
            'family_id': profile.familyId,
            'user_name': profile.fullName,
            'latitude': lat,
            'longitude': lng,
            'battery_level': level,
            'role': profile.role,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id').select();
      for (final m in members) {
        final targetUserId = m['user_id'];
        if (targetUserId == profile.userId ||
            (m['role'] != "leader" && m['role'] != "monitor")) {
          continue;
        }
        try {
          await Supabase.instance.client.functions.invoke(
            'push-router',
            body: {
              "target_user_id": targetUserId,
              "title": "Check-In",
              "body": "${profile.fullName ?? 'Someone'}: Checked in just now",
              "action": "check_in",
            },
          );
        } catch (e) {
          print("Push failed: $e");
        }
      }
    }
  }

  // ── SOS: 5-second haptic countdown then fire ──
  void _startSosCountdown() async {
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
                notesController.text.isEmpty
                    ? 'Senior pressed Emergency Help'
                    : notesController.text.trim(),
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

          await Supabase.instance.client
              .from('check_ins')
              .update({'acknowledged': true})
              .eq('user_id', profile.userId)
              .eq('status_message', 'Missed check-in')
              .eq('acknowledged', false);
          final members = await Supabase.instance.client
              .from('family_members')
              .select('user_id')
              .eq('family_id', profile.familyId);

          for (final m in members) {
            final targetUserId = m['user_id'];

            if (targetUserId == profile.userId) continue;

            try {
              await Supabase.instance.client.functions.invoke(
                'push-router',
                body: {
                  "target_user_id": targetUserId,
                  "title": "Emergency Alert",
                  "body": "${profile.fullName} triggered an emergency alert",
                  "action": "emergency",
                  "sound": "sos_sound",
                },
              );
            } catch (e) {
              debugPrint("Push failed: $e");
            }
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
                builder: (_) => MedicationsSheet(fromLeader: false),
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
            //         _elderMenuItem(ctx, Icons.phone, 'Call Family', () {
            //
            // Navigator.pop(ctx);
            // showModalBottomSheet(
            // context: context,
            // isScrollControlled: true,
            // backgroundColor: Colors.transparent,
            // builder: (_) => const ContactsSheet(),
            // );
            //         }),
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

  Future<void> _imOkayPressed() async {
    try {
      setState(() {
        imOkayLoad = true;
      });
      final profile = await ref.read(currentUserProfileProvider.future);

      if (missedCheckIn == null) return;
      if (profile == null) return;

      await Supabase.instance.client.from('well_events').insert({
        'family_id': missedCheckIn!['family_id'],
        'user_id': profile.userId,
        'user_name': profile.fullName,
        'event_type': 'missed_checkin_acknowledged',
        'title': 'Missed Check-In Acknowledged',
        'description': notesController.text.trim().isEmpty
            ? 'User confirmed they are OK after missing a scheduled check-in.'
            : notesController.text.trim(),
      });

      await Supabase.instance.client
          .from('check_ins')
          .update({'acknowledged': true})
          .eq('user_id', profile.userId)
          .eq('status_message', 'Missed check-in')
          .eq('acknowledged', false);

      if (!mounted) return;

      setState(() {
        missedCheckIn = null;
        notesController.clear();
        imOkayLoad = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check-in acknowledged successfully')),
      );
    } catch (e) {
      debugPrint('Acknowledge missed check-in error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
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

      final defaultMsg = "Checked in from Current Location.";

      bool gpsSuccess = false;
      double lat = 0.0;
      double lng = 0.0;

      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission == LocationPermission.deniedForever) {
            throw Exception(
              'Location permissions are permanently denied, we cannot request permissions. Please enable in Settings.',
            );
          }

          if (permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always) {
            // First attempt: High accuracy, short timeout
            try {
              final position = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high,
                ),
                timeLimit: const Duration(seconds: 5),
              );
              lat = position.latitude;
              lng = position.longitude;
              gpsSuccess = true;
            } catch (_) {
              // Fallback 1: Low accuracy (Cell tower/Wi-Fi), very fast
              try {
                final position = await Geolocator.getCurrentPosition(
                  locationSettings: const LocationSettings(
                    accuracy: LocationAccuracy.low,
                  ),
                  timeLimit: const Duration(seconds: 4),
                );
                lat = position.latitude;
                lng = position.longitude;
                gpsSuccess = true;
              } catch (_) {
                // Fallback 2: Last known position
                final lastPos = await Geolocator.getLastKnownPosition();
                if (lastPos != null) {
                  lat = lastPos.latitude;
                  lng = lastPos.longitude;
                  gpsSuccess = true;
                }
              }
            }
          }
        } else {
          await Geolocator.openLocationSettings();
          throw Exception('GPS Location Services are disabled on this device.');
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('permanently denied') ||
            e.toString().contains('disabled')) {
          rethrow;
        }
      }
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile');
      final members = await Supabase.instance.client
          .from('family_members')
          .select('user_id, role')
          .eq('family_id', profile.familyId);
      final response =
          await Supabase.instance.client.from('live_locations').upsert({
            'user_id': profile.userId,
            'family_id': profile.familyId,
            'user_name': profile.fullName,
            'latitude': lat,
            'longitude': lng,
            'battery_level': level,
            'role': profile.role,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id').select();
      for (final m in members) {
        final targetUserId = m['user_id'];
        if (targetUserId == profile.userId ||
            (m['role'] != "leader" && m['role'] != "monitor")) {
          continue;
        }
        try {
          await Supabase.instance.client.functions.invoke(
            'push-router',
            body: {
              "target_user_id": targetUserId,
              "title": "Check-In",
              "body": "${profile.fullName ?? 'Someone'}: Checked in just now",
              "action": "check_in",
            },
          );
        } catch (e) {}
      }
    }
  }

  Future<void> _emergencyPressed() async {
    await ref
        .read(safetyRepositoryProvider)
        .triggerSiren(
          missedCheckIn!['family_id'],
          notesController.text.trim().isEmpty
              ? 'Emergency reported after missed check-in'
              : notesController.text.trim(),
        );

    setState(() {
      missedCheckIn = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final firstName = profileAsync.value?.fullName?.split(' ').first ?? 'User';
    final medicationsAsync = ref.watch(familyMedicationsProvider);
    final safetyRepo = ref.watch(safetyRepositoryProvider);
    final toolsRepo = ref.watch(toolsRepositoryProvider);

    return Scaffold(
      backgroundColor: load ? Colors.white : ShieldColors.activeTeal,
      body: load
          ? Center(
              child: CircularProgressIndicator(color: ShieldColors.activeTeal),
            )
          : GestureDetector(
              onTap: () {
                notesFocus.unfocus();
              },
              child: SafeArea(
                child: RefreshIndicator(
                  onRefresh: () async {
                    notesFocus.unfocus();
                    final medicationsAsync = ref.invalidate(
                      familyMedicationsProvider,
                    );
                    final safetyRepo = ref.invalidate(safetyRepositoryProvider);
                  },
                  child: SingleChildScrollView(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        final medicationsAsync = ref.invalidate(
                          familyMedicationsProvider,
                        );
                        final safetyRepo = ref.invalidate(
                          safetyRepositoryProvider,
                        );
                      },
                      child: Column(
                        children: [
                          // Header with protected status
                          Container(
                            color: ShieldColors.activeTeal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 15,
                            ),
                            child: Row(
                              children: [
                                Image.asset(
                                  'assets/logo.png',
                                  height: 40,
                                  width: 40,
                                ),
                                SizedBox(width: 6),
                                Column(
                                  children: [
                                    Text(
                                      "$firstName's Portal",
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
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
                                        color: ShieldColors.activeTeal
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'PROTECTED MEMBER',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Spacer(),
                                GestureDetector(
                                  onTap: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) =>
                                          const ProfileSettingsView(),
                                    );
                                  },
                                  child: Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.grey.shade300,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: profileAsync.value!.avatarUrl != null
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              26,
                                            ),
                                            child: Image.network(
                                              profileAsync.value!.avatarUrl ??
                                                  "",
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.person,
                                            color: Colors.grey,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Container(
                            decoration: BoxDecoration(
                              color: ShieldColors.surfaceLight,
                              borderRadius: BorderRadius.only(
                                topRight: Radius.circular(20),
                                topLeft: Radius.circular(20),
                              ),
                              border: Border.all(
                                color: ShieldColors.surfaceLight.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),

                            child: Column(
                              children: [
                                StreamBuilder<List<Map<String, dynamic>>>(
                                  stream: _missedStream,
                                  builder: (context, snapshot) {
                                    final missed = snapshot.data ?? [];

                                    print(
                                      "STREAM STATE: ${snapshot.connectionState}",
                                    );
                                    print("STREAM ERROR: ${snapshot.error}");
                                    print("STREAM DATA: ${snapshot.data}");

                                    // final missed = snapshot.data ?? [];

                                    print("MISSED COUNT: ${missed.length}");

                                    if (missed.isEmpty) {
                                      missedCheckIn = null;
                                      return const SizedBox();
                                    }

                                    missedCheckIn = missed.first;

                                    final latestMissed = missed.first;

                                    return Container(
                                      margin: const EdgeInsets.only(
                                        bottom: 16,
                                        right: 12,
                                        left: 12,
                                        top: 12,
                                      ),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        //  border: Border.all(color: Colors.orange),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(16),

                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: ShieldColors.tealWash,
                                            ),
                                            child: Icon(
                                              Icons
                                                  .notifications_active_outlined,
                                              color: ShieldColors.activeTeal,
                                              size: 32,
                                            ),
                                          ),
                                          const SizedBox(height: 12),

                                          Text(
                                            "You missed your\n scheduled check-in",
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 20,

                                              fontWeight: FontWeight.bold,
                                              color: ShieldColors.activeTeal,
                                            ),
                                          ),

                                          // SizedBox(height: 10),
                                          // const Row(
                                          //   children: [
                                          //     Icon(
                                          //       Icons.warning_amber_rounded,
                                          //       color: Colors.orange,
                                          //     ),
                                          //     SizedBox(width: 8),
                                          //     Expanded(
                                          //       child: Text(
                                          //         "You missed your scheduled check-in",
                                          //         style: TextStyle(
                                          //           fontSize: 16,
                                          //           fontWeight: FontWeight.bold,
                                          //         ),
                                          //       ),
                                          //     ),
                                          //   ],
                                          // ),
                                          const SizedBox(height: 18),

                                          Column(
                                            children: [
                                              GestureDetector(
                                                onTap: () async {
                                                  if (imOkayLoad) return;
                                                  await _imOkayPressed();

                                                  if (!mounted) return;

                                                  setState(() {
                                                    missedCheckIn = null;
                                                  });
                                                },
                                                child: Container(
                                                  width: double.infinity,
                                                  padding: EdgeInsets.all(14),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        ShieldColors.activeTeal,

                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: imOkayLoad
                                                      ? Center(
                                                          child:
                                                              CircularProgressIndicator(
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                        )
                                                      : Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .check_circle_outline,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                            SizedBox(width: 10),
                                                            SizedBox(
                                                              child: const Text(
                                                                "I'M OKAY",
                                                                style: TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                ),
                                              ),

                                              const SizedBox(height: 12),
                                              GestureDetector(
                                                onTap: () async {
                                                  _startSosCountdown();
                                                },
                                                child: Container(
                                                  width: double.infinity,
                                                  decoration: BoxDecoration(
                                                    color: Colors.red,

                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  padding: EdgeInsets.all(14),
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .sports_soccer_sharp,
                                                        color: Colors.white,
                                                      ),
                                                      SizedBox(width: 10),
                                                      SizedBox(
                                                        child: const Text(
                                                          "I NEED HELP",
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 12),

                                              TextField(
                                                controller: notesController,
                                                maxLines: 1,
                                                textAlign: TextAlign.start,
                                                focusNode: notesFocus,
                                                decoration: InputDecoration(
                                                  fillColor:
                                                      ShieldColors.tealWash,
                                                  hintText:
                                                      "Add a note (Optional)",

                                                  prefixIcon: Icon(
                                                    Icons.edit,
                                                    color: Colors.grey.shade500,
                                                    size: 15,
                                                  ),
                                                  enabledBorder:
                                                      OutlineInputBorder(
                                                        borderSide: BorderSide(
                                                          color: ShieldColors
                                                              .tealWash,
                                                        ),
                                                      ),
                                                  border: OutlineInputBorder(),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),

                                //  if (missedCheckIn != null)
                                const SizedBox(height: 24),
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 24.0,
                                  ),
                                  child: PendingActionsCard(),
                                ),

                                //   const Spacer(flex: 2),

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
                                                            ? ShieldColors
                                                                  .urgentRed
                                                            : _isProcessing
                                                            ? const Color(
                                                                0xFF6B4EE6,
                                                              )
                                                            : ShieldColors
                                                                  .activeTeal)
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
                                          color: Colors.grey.withValues(
                                            alpha: 0.9,
                                          ),
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
                                            color: Colors.grey.withValues(
                                              alpha: 0.5,
                                            ),
                                            borderRadius:
                                                ShieldDesign.roundedTwelve,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    '🗣️ ',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Text(
                                                      _lastQuestion,
                                                      style: TextStyle(
                                                        color: Colors
                                                            .grey
                                                            .shade500,
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
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: Text(
                                                        _lastResponse,
                                                        style: const TextStyle(
                                                          color: Colors.black,
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                              if (_isProcessing)
                                                const Padding(
                                                  padding: EdgeInsets.only(
                                                    top: 8,
                                                  ),
                                                  child:
                                                      LinearProgressIndicator(
                                                        backgroundColor:
                                                            Colors.black,
                                                        color: Color(
                                                          0xFF6B4EE6,
                                                        ),
                                                      ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                SizedBox(height: 25),
                                // const Spacer(flex: 1),

                                // Action Buttons
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24.0,
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1C2438),
                                          borderRadius:
                                              ShieldDesign.roundedTwelve,
                                        ),
                                        child: Text(
                                          'Welcome $firstName.\nYou are protected by the Family Shield.',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w500,
                                                height: 1.4,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      medicationsAsync.when(
                                        data: (medications) {
                                          final activeMeds = medications
                                              .where(
                                                (m) =>
                                                    m.isActive &&
                                                    m.assignedTo ==
                                                        profileAsync
                                                            .value!
                                                            .userId,
                                              )
                                              .toList();

                                          if (activeMeds.isEmpty) {
                                            return const SizedBox.shrink();
                                          }

                                          return Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 18,
                                            ),
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.2),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'MEDICATION MONITOR',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                        color: ShieldColors
                                                            .textLabel,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        letterSpacing: 1.2,
                                                      ),
                                                ),

                                                const SizedBox(height: 14),

                                                // ...activeMeds.map((med) {
                                                //   // final nextDose = med.nextDoseToday;
                                                //   DateTime? nextDose;
                                                //
                                                //   if (med
                                                //       .scheduleTimes
                                                //       .isNotEmpty) {
                                                //     final now =
                                                //         DateTime.now();
                                                //
                                                //     final upcomingDoses =
                                                //         <DateTime>[];
                                                //
                                                //     final startDate =
                                                //         med.startDate ?? now;
                                                //
                                                //     for (final time
                                                //         in med
                                                //             .scheduleTimes) {
                                                //       try {
                                                //         final parts = time
                                                //             .split(':');
                                                //
                                                //         final hour =
                                                //             int.parse(
                                                //               parts[0],
                                                //             );
                                                //         final minute =
                                                //             int.parse(
                                                //               parts[1],
                                                //             );
                                                //
                                                //         DateTime doseTime =
                                                //             DateTime(
                                                //               now.year,
                                                //               now.month,
                                                //               now.day,
                                                //               hour,
                                                //               minute,
                                                //             );
                                                //
                                                //         final frequency = med
                                                //             .frequency
                                                //             .toLowerCase();
                                                //
                                                //         // DAILY
                                                //         if (frequency
                                                //             .contains(
                                                //               'daily',
                                                //             )) {
                                                //           if (doseTime
                                                //               .isBefore(
                                                //                 now,
                                                //               )) {
                                                //             doseTime =
                                                //                 doseTime.add(
                                                //                   const Duration(
                                                //                     days: 1,
                                                //                   ),
                                                //                 );
                                                //           }
                                                //         }
                                                //         // EVERY OTHER DAY
                                                //         else if (frequency
                                                //             .contains(
                                                //               'every other',
                                                //             )) {
                                                //           final daysSinceStart =
                                                //               now
                                                //                   .difference(
                                                //                     startDate,
                                                //                   )
                                                //                   .inDays;
                                                //
                                                //           final shouldTakeToday =
                                                //               daysSinceStart %
                                                //                   2 ==
                                                //               0;
                                                //
                                                //           if (!shouldTakeToday ||
                                                //               doseTime
                                                //                   .isBefore(
                                                //                     now,
                                                //                   )) {
                                                //             doseTime =
                                                //                 doseTime.add(
                                                //                   const Duration(
                                                //                     days: 1,
                                                //                   ),
                                                //                 );
                                                //
                                                //             while (doseTime
                                                //                         .difference(
                                                //                           startDate,
                                                //                         )
                                                //                         .inDays %
                                                //                     2 !=
                                                //                 0) {
                                                //               doseTime =
                                                //                   doseTime.add(
                                                //                     const Duration(
                                                //                       days: 1,
                                                //                     ),
                                                //                   );
                                                //             }
                                                //           }
                                                //         }
                                                //         // WEEKLY
                                                //         else if (frequency
                                                //             .contains(
                                                //               'weekly',
                                                //             )) {
                                                //           doseTime = DateTime(
                                                //             now.year,
                                                //             now.month,
                                                //             now.day,
                                                //             hour,
                                                //             minute,
                                                //           );
                                                //
                                                //           while (doseTime
                                                //                       .weekday !=
                                                //                   startDate
                                                //                       .weekday ||
                                                //               doseTime
                                                //                   .isBefore(
                                                //                     now,
                                                //                   )) {
                                                //             doseTime =
                                                //                 doseTime.add(
                                                //                   const Duration(
                                                //                     days: 1,
                                                //                   ),
                                                //                 );
                                                //           }
                                                //         }
                                                //         // MONTHLY
                                                //         else if (frequency
                                                //             .contains(
                                                //               'monthly',
                                                //             )) {
                                                //           doseTime = DateTime(
                                                //             now.year,
                                                //             now.month,
                                                //             startDate.day,
                                                //             hour,
                                                //             minute,
                                                //           );
                                                //
                                                //           if (doseTime
                                                //               .isBefore(
                                                //                 now,
                                                //               )) {
                                                //             doseTime =
                                                //                 DateTime(
                                                //                   now.year,
                                                //                   now.month +
                                                //                       1,
                                                //                   startDate
                                                //                       .day,
                                                //                   hour,
                                                //                   minute,
                                                //                 );
                                                //           }
                                                //         }
                                                //         // AS NEEDED
                                                //         else if (frequency
                                                //             .contains(
                                                //               'as needed',
                                                //             )) {
                                                //           continue;
                                                //         }
                                                //
                                                //         upcomingDoses.add(
                                                //           doseTime,
                                                //         );
                                                //       } catch (e) {
                                                //         debugPrint(
                                                //           "Dose parse error: $e",
                                                //         );
                                                //       }
                                                //     }
                                                //
                                                //     upcomingDoses.sort();
                                                //
                                                //     if (upcomingDoses
                                                //         .isNotEmpty) {
                                                //       nextDose =
                                                //           upcomingDoses.first;
                                                //     }
                                                //   }
                                                //   String countdownText =
                                                //       'No upcoming dose';
                                                //   Color statusColor =
                                                //       Colors.grey;
                                                //
                                                //   Duration? diff;
                                                //
                                                //   if (nextDose != null) {
                                                //     diff = nextDose
                                                //         .difference(
                                                //           DateTime.now(),
                                                //         );
                                                //   }
                                                //   countdownText =
                                                //       '${diff?.inHours}h ${diff?.inMinutes.remainder(60)}m ${diff?.inSeconds.remainder(60)}s';
                                                //   return Container(
                                                //     margin:
                                                //         const EdgeInsets.only(
                                                //           bottom: 12,
                                                //         ),
                                                //     padding:
                                                //         const EdgeInsets.all(
                                                //           14,
                                                //         ),
                                                //     decoration: BoxDecoration(
                                                //       color:
                                                //           Colors.grey.shade50,
                                                //       borderRadius:
                                                //           BorderRadius.circular(
                                                //             16,
                                                //           ),
                                                //       border: Border.all(
                                                //         color: statusColor
                                                //             .withValues(
                                                //               alpha: 0.2,
                                                //             ),
                                                //       ),
                                                //     ),
                                                //     child: Row(
                                                //       mainAxisAlignment:
                                                //           MainAxisAlignment
                                                //               .spaceBetween,
                                                //       children: [
                                                //         Icon(
                                                //           Icons
                                                //               .local_hospital,
                                                //           color:
                                                //               Colors.purple,
                                                //           size: 28,
                                                //         ),
                                                //
                                                //         const SizedBox(
                                                //           width: 7,
                                                //         ),
                                                //
                                                //         Expanded(
                                                //           child: Row(
                                                //             children: [
                                                //               Expanded(
                                                //                 child: Column(
                                                //                   crossAxisAlignment:
                                                //                       CrossAxisAlignment
                                                //                           .start,
                                                //                   children: [
                                                //                     Text(
                                                //                       med.medicationName,
                                                //                       style: const TextStyle(
                                                //                         fontWeight:
                                                //                             FontWeight.bold,
                                                //                         fontSize:
                                                //                             15,
                                                //                       ),
                                                //                     ),
                                                //
                                                //                     const SizedBox(
                                                //                       height:
                                                //                           4,
                                                //                     ),
                                                //
                                                //                     Text(
                                                //                       '${med.dosage} • ${med.scheduleSummary}',
                                                //                       style: TextStyle(
                                                //                         color: Colors
                                                //                             .grey
                                                //                             .shade700,
                                                //                         fontSize:
                                                //                             12,
                                                //                       ),
                                                //                     ),
                                                //
                                                //                     const SizedBox(
                                                //                       height:
                                                //                           6,
                                                //                     ),
                                                //
                                                //                     // if (nextDose !=
                                                //                     //     null) ...[
                                                //                     //   const SizedBox(
                                                //                     //     height: 4,
                                                //                     //   ),
                                                //                     //
                                                //                     //   Text(
                                                //                     //     'At ${DateFormat.jm().format(nextDose)}',
                                                //                     //     style: TextStyle(
                                                //                     //       color: Colors
                                                //                     //           .grey
                                                //                     //           .shade600,
                                                //                     //       fontSize: 11,
                                                //                     //     ),
                                                //                     //   ),
                                                //                     // ],
                                                //                   ],
                                                //                 ),
                                                //               ),
                                                //               Expanded(
                                                //                 child: Column(
                                                //                   crossAxisAlignment:
                                                //                       CrossAxisAlignment
                                                //                           .end,
                                                //                   mainAxisAlignment:
                                                //                       MainAxisAlignment
                                                //                           .end,
                                                //                   children: [
                                                //                     Row(
                                                //                       mainAxisAlignment:
                                                //                           MainAxisAlignment.end,
                                                //                       children: [
                                                //                         if (nextDose !=
                                                //                             null)
                                                //                           TweenAnimationBuilder<
                                                //                             double
                                                //                           >(
                                                //                             tween:
                                                //                                 Tween<
                                                //                                   double
                                                //                                 >(
                                                //                                   begin: nextDose!
                                                //                                       .difference(
                                                //                                         DateTime.now(),
                                                //                                       )
                                                //                                       .inSeconds
                                                //                                       .toDouble(),
                                                //                                   end: 0,
                                                //                                 ),
                                                //                             duration: nextDose!.difference(
                                                //                               DateTime.now(),
                                                //                             ),
                                                //                             builder:
                                                //                                 (
                                                //                                   context,
                                                //                                   value,
                                                //                                   child,
                                                //                                 ) {
                                                //                                   final diff = Duration(
                                                //                                     seconds: value.toInt(),
                                                //                                   );
                                                //
                                                //                                   if (diff.isNegative ||
                                                //                                       diff.inSeconds <=
                                                //                                           0) {
                                                //                                     return const Text(
                                                //                                       "Time Reached",
                                                //                                       style: TextStyle(
                                                //                                         color: Colors.red,
                                                //                                         fontWeight: FontWeight.bold,
                                                //                                       ),
                                                //                                     );
                                                //                                   }
                                                //
                                                //                                   final hours = diff.inHours;
                                                //                                   final mins = diff.inMinutes.remainder(
                                                //                                     60,
                                                //                                   );
                                                //                                   final secs = diff.inSeconds.remainder(
                                                //                                     60,
                                                //                                   );
                                                //
                                                //                                   final text =
                                                //                                       '${hours.toString().padLeft(2, '0')}h '
                                                //                                       '${mins.toString().padLeft(2, '0')}m '
                                                //                                       '${secs.toString().padLeft(2, '0')}s';
                                                //
                                                //                                   return Text(
                                                //                                     text,
                                                //                                     style: TextStyle(
                                                //                                       color: ShieldColors.activeTeal,
                                                //                                       fontWeight: FontWeight.w600,
                                                //                                       fontSize: 12,
                                                //                                     ),
                                                //                                   );
                                                //                                 },
                                                //                           ),
                                                //                       ],
                                                //                     ),
                                                //                     Text(
                                                //                       "Until Next Dose",
                                                //                       style: TextStyle(
                                                //                         fontSize:
                                                //                             12,
                                                //                         fontWeight:
                                                //                             FontWeight.bold,
                                                //                         color:
                                                //                             ShieldColors.activeTeal,
                                                //                       ),
                                                //                     ),
                                                //                   ],
                                                //                 ),
                                                //               ),
                                                //             ],
                                                //           ),
                                                //         ),
                                                //       ],
                                                //     ),
                                                //   );
                                                // }),
                                                ...activeMeds.map((med) {
                                                  // final nextDose = med.nextDoseToday;
                                                  DateTime? nextDose;

                                                  final allLogsAsync = ref
                                                      .watch(
                                                        allDoseLogsProvider,
                                                      );
                                                  final logs =
                                                      allLogsAsync.value ?? [];

                                                  final now = DateTime.now();
                                                  final startDate =
                                                      med.startDate ?? now;

                                                  bool isTakenToday = false;

                                                  final medicationLogs = logs
                                                      .where(
                                                        (l) =>
                                                            l.medicationId ==
                                                                med.id &&
                                                            l.status ==
                                                                'taken' &&
                                                            l.takenAt != null &&
                                                            med.assignedTo ==
                                                                profileAsync
                                                                    .value
                                                                    ?.userId,
                                                      );

                                                  switch (med.recurrence) {
                                                    case 'daily':
                                                      isTakenToday =
                                                          medicationLogs.any(
                                                            (log) =>
                                                                log
                                                                        .takenAt!
                                                                        .year ==
                                                                    now.year &&
                                                                log
                                                                        .takenAt!
                                                                        .month ==
                                                                    now.month &&
                                                                log
                                                                        .takenAt!
                                                                        .day ==
                                                                    now.day,
                                                          );
                                                      break;

                                                    case 'every_other_day':
                                                      final diffDays = now
                                                          .difference(startDate)
                                                          .inDays;

                                                      final shouldTakeToday =
                                                          diffDays % 2 == 0;

                                                      isTakenToday =
                                                          shouldTakeToday &&
                                                          medicationLogs.any(
                                                            (log) =>
                                                                log
                                                                        .takenAt!
                                                                        .year ==
                                                                    now.year &&
                                                                log
                                                                        .takenAt!
                                                                        .month ==
                                                                    now.month &&
                                                                log
                                                                        .takenAt!
                                                                        .day ==
                                                                    now.day,
                                                          );
                                                      break;

                                                    case 'weekly':
                                                      isTakenToday =
                                                          medicationLogs.any((
                                                            log,
                                                          ) {
                                                            final d =
                                                                log.takenAt!;

                                                            return d.weekday ==
                                                                    now.weekday &&
                                                                d.year ==
                                                                    now.year;
                                                          });
                                                      break;

                                                    case 'monthly':
                                                      isTakenToday =
                                                          medicationLogs.any((
                                                            log,
                                                          ) {
                                                            final d =
                                                                log.takenAt!;

                                                            return d.day ==
                                                                    now.day &&
                                                                d.month ==
                                                                    now.month &&
                                                                d.year ==
                                                                    now.year;
                                                          });
                                                      break;
                                                  }

                                                  if (med
                                                      .scheduleTimes
                                                      .isNotEmpty) {
                                                    final upcomingDoses =
                                                        <DateTime>[];

                                                    for (final time
                                                        in med.scheduleTimes) {
                                                      try {
                                                        final parts = time
                                                            .split(':');

                                                        final hour = int.parse(
                                                          parts[0],
                                                        );

                                                        final minute =
                                                            int.parse(parts[1]);

                                                        DateTime doseTime =
                                                            DateTime(
                                                              now.year,
                                                              now.month,
                                                              now.day,
                                                              hour,
                                                              minute,
                                                            );

                                                        final frequency = med
                                                            .frequency
                                                            .toLowerCase();

                                                        // already logged → move next occurrence
                                                        if (isTakenToday) {
                                                          switch (med
                                                              .recurrence) {
                                                            case 'daily':
                                                              doseTime =
                                                                  doseTime.add(
                                                                    const Duration(
                                                                      days: 1,
                                                                    ),
                                                                  );
                                                              break;

                                                            case 'every_other_day':
                                                              doseTime =
                                                                  doseTime.add(
                                                                    const Duration(
                                                                      days: 2,
                                                                    ),
                                                                  );
                                                              break;

                                                            case 'weekly':
                                                              doseTime =
                                                                  doseTime.add(
                                                                    const Duration(
                                                                      days: 7,
                                                                    ),
                                                                  );
                                                              break;

                                                            case 'monthly':
                                                              doseTime = DateTime(
                                                                doseTime.year,
                                                                doseTime.month +
                                                                    1,
                                                                doseTime.day,
                                                                doseTime.hour,
                                                                doseTime.minute,
                                                              );
                                                              break;
                                                          }
                                                        }
                                                        // normal schedule
                                                        else {
                                                          if (frequency
                                                              .contains(
                                                                'daily',
                                                              )) {
                                                            if (doseTime
                                                                .isBefore(
                                                                  now,
                                                                )) {
                                                              doseTime =
                                                                  doseTime.add(
                                                                    const Duration(
                                                                      days: 1,
                                                                    ),
                                                                  );
                                                            }
                                                          } else if (frequency
                                                              .contains(
                                                                'every other',
                                                              )) {
                                                            final daysSinceStart =
                                                                now
                                                                    .difference(
                                                                      startDate,
                                                                    )
                                                                    .inDays;

                                                            final shouldTakeToday =
                                                                daysSinceStart %
                                                                    2 ==
                                                                0;

                                                            if (!shouldTakeToday ||
                                                                doseTime
                                                                    .isBefore(
                                                                      now,
                                                                    )) {
                                                              doseTime =
                                                                  doseTime.add(
                                                                    const Duration(
                                                                      days: 1,
                                                                    ),
                                                                  );

                                                              while (doseTime
                                                                          .difference(
                                                                            startDate,
                                                                          )
                                                                          .inDays %
                                                                      2 !=
                                                                  0) {
                                                                doseTime =
                                                                    doseTime.add(
                                                                      const Duration(
                                                                        days: 1,
                                                                      ),
                                                                    );
                                                              }
                                                            }
                                                          } else if (frequency
                                                              .contains(
                                                                'weekly',
                                                              )) {
                                                            while (doseTime
                                                                        .weekday !=
                                                                    startDate
                                                                        .weekday ||
                                                                doseTime
                                                                    .isBefore(
                                                                      now,
                                                                    )) {
                                                              doseTime =
                                                                  doseTime.add(
                                                                    const Duration(
                                                                      days: 1,
                                                                    ),
                                                                  );
                                                            }
                                                          } else if (frequency
                                                              .contains(
                                                                'monthly',
                                                              )) {
                                                            doseTime = DateTime(
                                                              now.year,
                                                              now.month,
                                                              startDate.day,
                                                              hour,
                                                              minute,
                                                            );

                                                            if (doseTime
                                                                .isBefore(
                                                                  now,
                                                                )) {
                                                              doseTime =
                                                                  DateTime(
                                                                    now.year,
                                                                    now.month +
                                                                        1,
                                                                    startDate
                                                                        .day,
                                                                    hour,
                                                                    minute,
                                                                  );
                                                            }
                                                          } else if (frequency
                                                              .contains(
                                                                'as needed',
                                                              )) {
                                                            continue;
                                                          }
                                                        }

                                                        upcomingDoses.add(
                                                          doseTime,
                                                        );
                                                      } catch (e) {
                                                        debugPrint(
                                                          "Dose parse error: $e",
                                                        );
                                                      }
                                                    }

                                                    upcomingDoses.sort();

                                                    if (upcomingDoses
                                                        .isNotEmpty) {
                                                      nextDose =
                                                          upcomingDoses.first;
                                                    }
                                                  }
                                                  return Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                          bottom: 12,
                                                        ),
                                                    padding:
                                                        const EdgeInsets.all(
                                                          14,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.grey.shade50,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                      border: Border.all(
                                                        color: Colors.black
                                                            .withValues(
                                                              alpha: 0.2,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        Icon(
                                                          Icons.local_hospital,
                                                          color: Colors.purple,
                                                          size: 26,
                                                        ),

                                                        const SizedBox(
                                                          width: 7,
                                                        ),

                                                        Expanded(
                                                          child: Row(
                                                            children: [
                                                              Expanded(
                                                                child: Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children: [
                                                                    Text(
                                                                      med.medicationName,
                                                                      style: const TextStyle(
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                        fontSize:
                                                                            15,
                                                                      ),
                                                                    ),

                                                                    const SizedBox(
                                                                      height: 4,
                                                                    ),

                                                                    Text(
                                                                      '${med.dosage} • ${med.scheduleSummary}',
                                                                      style: TextStyle(
                                                                        color: Colors
                                                                            .grey
                                                                            .shade700,
                                                                        fontSize:
                                                                            12,
                                                                      ),
                                                                    ),

                                                                    const SizedBox(
                                                                      height: 6,
                                                                    ),

                                                                    // if (nextDose !=
                                                                    //     null) ...[
                                                                    //   const SizedBox(
                                                                    //     height: 4,
                                                                    //   ),
                                                                    //
                                                                    //   Text(
                                                                    //     'At ${DateFormat.jm().format(nextDose)}',
                                                                    //     style: TextStyle(
                                                                    //       color: Colors
                                                                    //           .grey
                                                                    //           .shade600,
                                                                    //       fontSize: 11,
                                                                    //     ),
                                                                    //   ),
                                                                    // ],
                                                                  ],
                                                                ),
                                                              ),
                                                              Expanded(
                                                                child: Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .end,
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .end,
                                                                  children: [
                                                                    Row(
                                                                      mainAxisAlignment:
                                                                          MainAxisAlignment
                                                                              .end,
                                                                      children: [
                                                                        if (nextDose !=
                                                                            null)
                                                                          StreamBuilder(
                                                                            stream: Stream.periodic(
                                                                              const Duration(
                                                                                seconds: 1,
                                                                              ),
                                                                            ),
                                                                            builder:
                                                                                (
                                                                                  context,
                                                                                  snapshot,
                                                                                ) {
                                                                                  final diff =
                                                                                      nextDose?.difference(
                                                                                        DateTime.now(),
                                                                                      ) ??
                                                                                      Duration.zero;

                                                                                  // Prevent negative values
                                                                                  final safeDiff = diff.isNegative
                                                                                      ? Duration.zero
                                                                                      : diff;

                                                                                  final text =
                                                                                      '${safeDiff.inHours.toString().padLeft(2, '0')}h '
                                                                                      '${safeDiff.inMinutes.remainder(60).toString().padLeft(2, '0')}m '
                                                                                      '${safeDiff.inSeconds.remainder(60).toString().padLeft(2, '0')}s';

                                                                                  return Text(
                                                                                    text,
                                                                                    style: TextStyle(
                                                                                      color: ShieldColors.activeTeal,
                                                                                      fontWeight: FontWeight.w600,
                                                                                      fontSize: 12,
                                                                                    ),
                                                                                  );
                                                                                },
                                                                          ),
                                                                      ],
                                                                    ),
                                                                    Text(
                                                                      "Until Next Dose",
                                                                      style: TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                        color: ShieldColors
                                                                            .activeTeal,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      height:
                                                                          10,
                                                                    ),
                                                                    if (!isTakenToday)
                                                                      SizedBox(
                                                                        width:
                                                                            110,
                                                                        height:
                                                                            34,
                                                                        child: ElevatedButton(
                                                                          onPressed:
                                                                              _loggingMedicationId ==
                                                                                  med.id
                                                                              ? null
                                                                              : () => _logDose(med),

                                                                          style: ElevatedButton.styleFrom(
                                                                            backgroundColor:
                                                                                ShieldColors.activeTeal,
                                                                            foregroundColor:
                                                                                Colors.white,
                                                                            elevation:
                                                                                0,
                                                                            padding:
                                                                                EdgeInsets.zero,
                                                                            shape: RoundedRectangleBorder(
                                                                              borderRadius: BorderRadius.circular(
                                                                                10,
                                                                              ),
                                                                            ),
                                                                          ),

                                                                          child:
                                                                              _loggingMedicationId ==
                                                                                  med.id
                                                                              ? const SizedBox(
                                                                                  width: 14,
                                                                                  height: 14,
                                                                                  child: CircularProgressIndicator(
                                                                                    strokeWidth: 2,
                                                                                    color: Colors.white,
                                                                                  ),
                                                                                )
                                                                              : const Row(
                                                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                                                  children: [
                                                                                    Icon(
                                                                                      Icons.check_circle_outline,
                                                                                      size: 15,
                                                                                    ),
                                                                                    SizedBox(
                                                                                      width: 5,
                                                                                    ),
                                                                                    Text(
                                                                                      "Log Dose",
                                                                                      style: TextStyle(
                                                                                        fontSize: 11,
                                                                                        fontWeight: FontWeight.w600,
                                                                                      ),
                                                                                    ),
                                                                                  ],
                                                                                ),
                                                                        ),
                                                                      ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                }),
                                              ],
                                            ),
                                          );
                                        },
                                        loading: () => const Center(
                                          child: Padding(
                                            padding: EdgeInsets.all(20),
                                            child: CircularProgressIndicator(),
                                          ),
                                        ),
                                        error: (e, st) =>
                                            const SizedBox.shrink(),
                                      ),
                                      const SizedBox(height: 24),
                                      StreamBuilder<List<Map<String, dynamic>>>(
                                        stream: safetyRepo
                                            .streamMyCheckinSchedules(
                                              profileAsync.value!.userId,
                                            ),
                                        builder: (context, snapshot) {
                                          final schedules = snapshot.data ?? [];
                                          print("schedules");
                                          print(schedules);
                                          if (schedules.isEmpty) {
                                            return const SizedBox.shrink();
                                          }

                                          // Get next upcoming checkin
                                          DateTime? nextCheckin;
                                          Map<String, dynamic>?
                                          selectedSchedule;
                                          for (final s in schedules) {
                                            print(s);
                                            print('checkin_time');
                                            final time = s['checkin_time'];

                                            final next = _getNextCheckinTime(s);

                                            if (next == null) continue;
                                            if (nextCheckin == null ||
                                                next.isBefore(nextCheckin)) {
                                              nextCheckin = next;
                                              selectedSchedule = s;
                                            }
                                          }

                                          if (nextCheckin == null ||
                                              selectedSchedule == null) {
                                            return const SizedBox.shrink();
                                          }

                                          final scheduleId =
                                              selectedSchedule['id'];

                                          return _NextCheckinCard(
                                            nextCheckin: nextCheckin,
                                            profile: profileAsync.value,
                                            scheduleId: scheduleId,
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 18),

                                      _actionButton(
                                        icon: Icons.family_restroom,
                                        label: 'View Family',
                                        color: ShieldColors.activeTeal,
                                        onPressed: () {
                                          showModalBottomSheet(
                                            context: context,
                                            isScrollControlled: true,
                                            backgroundColor: Colors.transparent,
                                            builder: (_) =>
                                                const ContactsSheet(),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 18),
                                      Text(
                                        'YOUR SAFE ZONES',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.2,
                                            ),
                                      ),
                                      const SizedBox(height: 16),
                                      StreamBuilder<List<Map<String, dynamic>>>(
                                        stream: toolsRepo
                                            .streamAssignedSafeZones(
                                              profileAsync.value!.familyId,
                                              profileAsync.value!.userId,
                                            ),
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState ==
                                              ConnectionState.waiting) {
                                            return const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            );
                                          }
                                          final zones = snapshot.data ?? [];

                                          if (zones.isEmpty) {
                                            return Container(
                                              height: 120,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius:
                                                    ShieldDesign.roundedTwelve,
                                              ),
                                              child: const Text(
                                                'No Safe Zones Configured',
                                              ),
                                            );
                                          }

                                          return Column(
                                            children: zones.map((zone) {
                                              bool isInside =
                                                  zone['name']
                                                      .toString()
                                                      .toLowerCase()
                                                      .contains('school') ||
                                                  zone['name']
                                                      .toString()
                                                      .toLowerCase()
                                                      .contains('home');

                                              return Container(
                                                margin: const EdgeInsets.only(
                                                  bottom: 12,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isInside
                                                      ? ShieldColors
                                                            .safeZoneGreen
                                                            .withValues(
                                                              alpha: 0.1,
                                                            )
                                                      : Colors.white,
                                                  borderRadius: ShieldDesign
                                                      .roundedTwelve,
                                                  border: Border.all(
                                                    color: isInside
                                                        ? ShieldColors
                                                              .safeZoneGreen
                                                        : Colors.grey.shade300,
                                                  ),
                                                ),
                                                child: ListTile(
                                                  leading: Icon(
                                                    Icons.location_on,
                                                    color: isInside
                                                        ? ShieldColors
                                                              .safeZoneGreen
                                                        : Colors.grey,
                                                  ),
                                                  title: Text(
                                                    zone['name'],
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          ShieldColors.textBody,
                                                    ),
                                                  ),
                                                  subtitle: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      if (zone['address'] !=
                                                          null)
                                                        Text(
                                                          zone['address'],
                                                          style: TextStyle(
                                                            color: Colors.black,
                                                          ),
                                                        ),
                                                      Text(
                                                        'Radius: ${zone['radius_meters']}m',
                                                      ),
                                                    ],
                                                  ),
                                                  trailing: isInside
                                                      ? const Chip(
                                                          label: Text('ACTIVE'),
                                                          backgroundColor:
                                                              ShieldColors
                                                                  .safeZoneGreen,
                                                          labelStyle: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 10,
                                                          ),
                                                        )
                                                      : const Text(
                                                          'Away',
                                                          style: TextStyle(
                                                            color: Colors.grey,
                                                          ),
                                                        ),
                                                ),
                                              );
                                            }).toList(),
                                          );
                                        },
                                      ),

                                      const SizedBox(height: 14),
                                      // Check Status (manual check-in)
                                      _actionButton(
                                        icon: _isCheckingIn
                                            ? Icons.hourglass_top
                                            : Icons.health_and_safety,
                                        label: _isCheckingIn
                                            ? 'Broadcasting...'
                                            : 'Manual Check-In',
                                        color: const Color(0xFF3366FF),
                                        onPressed: _isCheckingIn
                                            ? null
                                            : _performCheckIn,
                                      ),
                                      const SizedBox(height: 18),

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
                                            builder: (_) =>
                                                const FamilyChatScreen(),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 20),

                                // Bottom buttons — EMERGENCY + MENU (wrapped in SafeArea)
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: Container(
        color: Colors.white,
        child: SafeArea(
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
                          borderRadius: ShieldDesign.roundedTwelve,
                        ),
                        elevation: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.warning_rounded, size: 28),
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

  DateTime? _getNextCheckinTime(Map<String, dynamic> schedule) {
    // use next generated occurrence if available
    if (schedule['scheduled_at'] != null) {
      final next = DateTime.parse(schedule['scheduled_at']).toLocal();

      if (next.isBefore(DateTime.now())) {
        return null;
      }

      return next;
    }

    // fallback for old records
    final datePart = DateTime.parse(schedule['checkin_date']);

    final parts = schedule['checkin_time'].split(':');

    final hour = int.parse(parts[0]);

    final minute = int.parse(parts[1]);

    final checkin = DateTime(
      datePart.year,
      datePart.month,
      datePart.day,
      hour,
      minute,
    );

    if (checkin.isBefore(DateTime.now())) {
      return null;
    }

    return checkin;
  }
}

class _NextCheckinCard extends ConsumerStatefulWidget {
  final DateTime nextCheckin;
  final profile;
  final String scheduleId;

  const _NextCheckinCard({
    super.key,
    required this.nextCheckin,
    required this.profile,
    required this.scheduleId,
  });

  @override
  ConsumerState<_NextCheckinCard> createState() => _NextCheckinCardState();
}

class _NextCheckinCardState extends ConsumerState<_NextCheckinCard> {
  bool _showCheckinPopup = false;
  bool isLoad = false;
  bool _sosCountdownActive = false;
  int _sosCountdown = 5;
  Timer? _sosTimer;

  void _startSosCountdown() {
    if (_sosCountdownActive) {
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
                'Senior initiated an emergency state',
              );

          if (mounted) {
            setState(() {
              _sosCountdownActive = false;
              _sosCountdown = 5;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🚨 EMERGENCY ALERT SENT!'),
                backgroundColor: ShieldColors.urgentRed,
                duration: Duration(seconds: 5),
              ),
            );
          }
          final members = await Supabase.instance.client
              .from('family_members')
              .select('user_id')
              .eq('family_id', profile.familyId);

          for (final m in members) {
            final targetUserId = m['user_id'];

            if (targetUserId == profile.userId) continue;

            try {
              await Supabase.instance.client.functions.invoke(
                'push-router',
                body: {
                  "target_user_id": targetUserId,
                  "title": "Emergency Alert",
                  "body": "${profile.fullName} triggered an emergency alert",
                  "action": "emergency",
                  "sound": "sos_sound",
                },
              );
            } catch (e) {
              debugPrint("Push failed: $e");
            }
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
        if (mounted) setState(() => _sosCountdown--);
      }
    });
  }

  void _checkScheduleTime(DateTime nextCheckin) {
    final now = DateTime.now();

    if (now.isAfter(nextCheckin) && !_showCheckinPopup) {
      _showCheckinPopup = true;

      // WidgetsBinding.instance.addPostFrameCallback((_) async {
      //   if (mounted) {
      //     var value = await _showCheckinDialog();
      //     print(value);
      //     print("valuevalue");
      //
      //     if (value == true) {
      //       if (isLoad) return;
      //       if (widget.profile == null) return;
      //       setState(() {
      //         isLoad = true;
      //       });
      //       int level =
      //           100; // Safe default for simulators and aggressive background iOS policies
      //       try {
      //         final battery = Battery();
      //         level = await battery.batteryLevel;
      //       } catch (e) {
      //         debugPrint(
      //           'Battery info not available over isolate, using default: $e',
      //         );
      //       }
      //
      //       final defaultMsg = "Checked in from Current Location.";
      //
      //       bool gpsSuccess = false;
      //       double lat = 0.0;
      //       double lng = 0.0;
      //
      //       try {
      //         bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      //         if (serviceEnabled) {
      //           LocationPermission permission =
      //               await Geolocator.checkPermission();
      //           if (permission == LocationPermission.denied) {
      //             permission = await Geolocator.requestPermission();
      //           }
      //           if (permission == LocationPermission.deniedForever) {
      //             setState(() {
      //               isLoad = false;
      //             });
      //             throw Exception(
      //               'Location permissions are permanently denied, we cannot request permissions. Please enable in Settings.',
      //             );
      //           }
      //
      //           if (permission == LocationPermission.whileInUse ||
      //               permission == LocationPermission.always) {
      //             // First attempt: High accuracy, short timeout
      //             try {
      //               final position = await Geolocator.getCurrentPosition(
      //                 locationSettings: const LocationSettings(
      //                   accuracy: LocationAccuracy.high,
      //                 ),
      //                 timeLimit: const Duration(seconds: 5),
      //               );
      //               lat = position.latitude;
      //               lng = position.longitude;
      //               gpsSuccess = true;
      //             } catch (_) {
      //               setState(() {
      //                 isLoad = false;
      //               });
      //               // Fallback 1: Low accuracy (Cell tower/Wi-Fi), very fast
      //               try {
      //                 final position = await Geolocator.getCurrentPosition(
      //                   locationSettings: const LocationSettings(
      //                     accuracy: LocationAccuracy.low,
      //                   ),
      //                   timeLimit: const Duration(seconds: 4),
      //                 );
      //                 lat = position.latitude;
      //                 lng = position.longitude;
      //                 gpsSuccess = true;
      //               } catch (_) {
      //                 setState(() {
      //                   isLoad = false;
      //                 });
      //                 // Fallback 2: Last known position
      //                 final lastPos = await Geolocator.getLastKnownPosition();
      //                 if (lastPos != null) {
      //                   lat = lastPos.latitude;
      //                   lng = lastPos.longitude;
      //                   gpsSuccess = true;
      //                 }
      //               }
      //             }
      //           }
      //         } else {
      //           setState(() {
      //             isLoad = false;
      //           });
      //           await Geolocator.openLocationSettings();
      //           throw Exception(
      //             'GPS Location Services are disabled on this device.',
      //           );
      //         }
      //       } catch (e) {
      //         setState(() {
      //           isLoad = false;
      //         });
      //         if (e is Exception &&
      //                 e.toString().contains('permanently denied') ||
      //             e.toString().contains('disabled')) {
      //           rethrow;
      //         }
      //       }
      //
      //       await Supabase.instance.client.from('check_ins').insert({
      //         'family_id': widget.profile.familyId,
      //         'user_id': widget.profile.userId,
      //         'latitude': lat,
      //         'longitude': lng,
      //         'status_message': "Scheduled check-in completed",
      //       });
      //
      //       // Also register this as a well_event to ensure it shows up securely on the stream!
      //       await Supabase.instance.client.from('well_events').insert({
      //         'family_id': widget.profile.familyId,
      //         'user_id': widget.profile.userId,
      //         'user_name': widget.profile.fullName,
      //         'event_type': 'check_in',
      //         'title': 'Manual Check-in',
      //         'description': 'Scheduled check-in completed',
      //         'latitude': lat,
      //         'longitude': lng,
      //         'battery_level': level,
      //       });
      //       final schedule = await Supabase.instance.client
      //           .from('checkin_schedules')
      //           .select('recurrence')
      //           .eq('id', widget.scheduleId)
      //           .single();
      //       final recurrence = schedule['recurrence'];
      //
      //       final isRecurring =
      //           recurrence == 'daily' ||
      //           recurrence == 'every_other_day' ||
      //           recurrence == 'weekly' ||
      //           recurrence == 'monthly';
      //
      //       DateTime? nextDate;
      //
      //       if (isRecurring) {
      //         final fullSchedule = await Supabase.instance.client
      //             .from('checkin_schedules')
      //             .select()
      //             .eq('id', widget.scheduleId)
      //             .single();
      //
      //         nextDate = DateTime.parse(fullSchedule['scheduled_at']);
      //
      //         switch (recurrence) {
      //           case 'daily':
      //             nextDate = nextDate.add(const Duration(days: 1));
      //             break;
      //
      //           case 'every_other_day':
      //             nextDate = nextDate.add(const Duration(days: 2));
      //             break;
      //
      //           case 'weekly':
      //             final days = List<int>.from(
      //               fullSchedule['days_of_week'] ?? [],
      //             );
      //
      //             if (days.isEmpty) {
      //               nextDate = nextDate.add(const Duration(days: 7));
      //             } else {
      //               final currentDay = nextDate.weekday % 7;
      //
      //               int? found;
      //
      //               for (final d in days) {
      //                 if (d > currentDay) {
      //                   found = d;
      //                   break;
      //                 }
      //               }
      //
      //               found ??= days.first + 7;
      //
      //               nextDate = nextDate.add(Duration(days: found - currentDay));
      //             }
      //
      //             break;
      //
      //           case 'monthly':
      //             nextDate = DateTime(
      //               nextDate.year,
      //               nextDate.month + 1,
      //               nextDate.day,
      //               nextDate.hour,
      //               nextDate.minute,
      //             );
      //             break;
      //         }
      //       }
      //
      //       await Supabase.instance.client
      //           .from('checkin_schedules')
      //           .update({
      //             if (!isRecurring) 'is_completed': true,
      //
      //             'completed_at': DateTime.now().toIso8601String(),
      //
      //             if (!isRecurring) 'status': 'completed',
      //
      //             if (isRecurring) ...{
      //               'status': 'pending',
      //               'scheduled_at': nextDate?.toIso8601String(),
      //               'reminder_sent': false,
      //               'reminder_sent_at': null,
      //             },
      //           })
      //           .eq('id', widget.scheduleId);
      //       if (!mounted) return;
      //
      //       ScaffoldMessenger.of(context).showSnackBar(
      //         SnackBar(content: Text("Scheduled check-in completed")),
      //       );
      //       final safety = ref.invalidate(safetyRepositoryProvider);
      //
      //       final profile = await ref.read(currentUserProfileProvider.future);
      //       if (profile == null) throw Exception('No profile');
      //       final response =
      //           await Supabase.instance.client.from('live_locations').upsert({
      //             'user_id': profile.userId,
      //             'family_id': profile.familyId,
      //             'user_name': profile.fullName,
      //             'latitude': lat,
      //             'longitude': lng,
      //             'role': profile.role,
      //
      //             'battery_level': level,
      //             'updated_at': DateTime.now().toIso8601String(),
      //           }, onConflict: 'user_id').select();
      //       final members = await Supabase.instance.client
      //           .from('family_members')
      //           .select('user_id, role')
      //           .eq('family_id', profile.familyId);
      //
      //       for (final m in members) {
      //         final targetUserId = m['user_id'];
      //
      //         if (targetUserId == profile.userId ||
      //             (m['role'] != "leader" && m['role'] != "monitor")) {
      //           continue;
      //         }
      //         try {
      //           await Supabase.instance.client.functions.invoke(
      //             'push-router',
      //             body: {
      //               "target_user_id": targetUserId,
      //               "title": "Check-In",
      //               "body":
      //                   "${profile.fullName ?? 'Someone'}: Checked in just now",
      //               "action": "check_in",
      //             },
      //           );
      //           setState(() {
      //             isLoad = false;
      //           });
      //         } catch (e) {
      //           print("Push failed: $e");
      //         }
      //       }
      //     } else if (value == false) {
      //       _startSosCountdown();
      //     }
      //   }
      // });
    }
  }

  Future<bool?> _showCheckinDialog() async {
    final result = await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return AlertDialog(
          title: const Text("Time To Check In"),
          content: const Text("Please confirm your status"),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text("I'M OK"),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text("I NEED HELP"),
            ),
          ],
        );
      },
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        Duration diff = widget.nextCheckin.difference(DateTime.now());

        if (diff.isNegative) {
          diff = Duration.zero;
        }

        final hours = diff.inHours.toString().padLeft(2, '0');

        final mins = diff.inMinutes.remainder(60).toString().padLeft(2, '0');

        final secs = diff.inSeconds.remainder(60).toString().padLeft(2, '0');

        _checkScheduleTime(widget.nextCheckin);

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00838F), Color(0xFF006064)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.check_circle_outline,
                    color: Colors.white,
                    size: 42,
                  ),
                  SizedBox(width: 10),
                  Text(
                    "Check In",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              Text(
                textAlign: TextAlign.center,
                "Next Check In at ${DateFormat('dd MMM yyyy, hh:mm a').format(widget.nextCheckin)}",
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _timeBox(hours, "HRS"),
                  const SizedBox(width: 16),

                  const Text(
                    ":",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(width: 16),

                  _timeBox(mins, "MINS"),

                  const SizedBox(width: 16),

                  const Text(
                    ":",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(width: 16),

                  _timeBox(secs, "SECS"),
                ],
              ),

              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF006064),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () async {
                    if (isLoad) return;
                    if (widget.profile == null) return;
                    setState(() {
                      isLoad = true;
                    });
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

                    final defaultMsg = "Checked in from Current Location.";

                    bool gpsSuccess = false;
                    double lat = 0.0;
                    double lng = 0.0;

                    try {
                      bool serviceEnabled =
                          await Geolocator.isLocationServiceEnabled();
                      if (serviceEnabled) {
                        LocationPermission permission =
                            await Geolocator.checkPermission();
                        if (permission == LocationPermission.denied) {
                          permission = await Geolocator.requestPermission();
                        }
                        if (permission == LocationPermission.deniedForever) {
                          setState(() {
                            isLoad = false;
                          });
                          throw Exception(
                            'Location permissions are permanently denied, we cannot request permissions. Please enable in Settings.',
                          );
                        }

                        if (permission == LocationPermission.whileInUse ||
                            permission == LocationPermission.always) {
                          // First attempt: High accuracy, short timeout
                          try {
                            final position =
                                await Geolocator.getCurrentPosition(
                                  locationSettings: const LocationSettings(
                                    accuracy: LocationAccuracy.high,
                                  ),
                                  timeLimit: const Duration(seconds: 5),
                                );
                            lat = position.latitude;
                            lng = position.longitude;
                            gpsSuccess = true;
                          } catch (_) {
                            setState(() {
                              isLoad = false;
                            });
                            // Fallback 1: Low accuracy (Cell tower/Wi-Fi), very fast
                            try {
                              final position =
                                  await Geolocator.getCurrentPosition(
                                    locationSettings: const LocationSettings(
                                      accuracy: LocationAccuracy.low,
                                    ),
                                    timeLimit: const Duration(seconds: 4),
                                  );
                              lat = position.latitude;
                              lng = position.longitude;
                              gpsSuccess = true;
                            } catch (_) {
                              setState(() {
                                isLoad = false;
                              });
                              // Fallback 2: Last known position
                              final lastPos =
                                  await Geolocator.getLastKnownPosition();
                              if (lastPos != null) {
                                lat = lastPos.latitude;
                                lng = lastPos.longitude;
                                gpsSuccess = true;
                              }
                            }
                          }
                        }
                      } else {
                        setState(() {
                          isLoad = false;
                        });
                        await Geolocator.openLocationSettings();
                        throw Exception(
                          'GPS Location Services are disabled on this device.',
                        );
                      }
                    } catch (e) {
                      setState(() {
                        isLoad = false;
                      });
                      if (e is Exception &&
                              e.toString().contains('permanently denied') ||
                          e.toString().contains('disabled')) {
                        rethrow;
                      }
                    }
                    final fullSchedule = await Supabase.instance.client
                        .from('checkin_schedules')
                        .select()
                        .eq('id', widget.scheduleId)
                        .single();

                    final recurrence = fullSchedule['recurrence'] as String?;
                    final scheduledAtUtc = DateTime.parse(
                      fullSchedule['scheduled_at'],
                    ).toUtc();
                    final nowUtc = DateTime.now().toUtc();

                    print("🕐 nowUtc: $nowUtc");
                    print("🕐 scheduledAtUtc: $scheduledAtUtc");
                    print(
                      "🕐 diff: ${scheduledAtUtc.difference(nowUtc).inMinutes} mins away",
                    );

                    // ── Within 5 min early window? ───────────────────────────────────
                    final isWithin5MinEarly =
                        nowUtc.isAfter(
                          scheduledAtUtc.subtract(const Duration(minutes: 5)),
                        ) &&
                        nowUtc.isBefore(
                          scheduledAtUtc.add(const Duration(minutes: 1)),
                        );

                    final isRecurring =
                        isWithin5MinEarly &&
                        (recurrence == 'daily' ||
                            recurrence == 'every_other_day' ||
                            recurrence == 'weekly' ||
                            recurrence == 'monthly');

                    print("✅ isWithin5MinEarly: $isWithin5MinEarly");
                    print("✅ isRecurring: $isRecurring");
                    print("✅ recurrence: $recurrence");

                    // ── Insert check_in ──────────────────────────────────────────────
                    await Supabase.instance.client.from('check_ins').insert({
                      'family_id': widget.profile.familyId,
                      'user_id': widget.profile.userId,
                      'latitude': lat,
                      'longitude': lng,
                      'status_message': isWithin5MinEarly
                          ? "Scheduled check-in completed"
                          : "Manual check-in",
                    });

                    // ── Insert well_event ────────────────────────────────────────────
                    await Supabase.instance.client.from('well_events').insert({
                      'family_id': widget.profile.familyId,
                      'user_id': widget.profile.userId,
                      'user_name': widget.profile.fullName,
                      'event_type': 'check_in',
                      'title': isWithin5MinEarly
                          ? 'Scheduled Check-in'
                          : 'Manual Check-in',
                      'description': isWithin5MinEarly
                          ? 'Scheduled check-in completed'
                          : 'Manual check-in outside schedule window',
                      'latitude': lat,
                      'longitude': lng,
                      'battery_level': level,
                    });

                    // ── Compute next date if recurring ───────────────────────────────
                    // ❌ DELETE the old `final schedule = ...` fetch here — REMOVE IT
                    // ❌ DELETE the second `fullSchedule` fetch inside if(isRecurring) — REMOVE IT

                    DateTime? nextDate;

                    if (isRecurring) {
                      nextDate =
                          scheduledAtUtc; // ✅ reuse already fetched value

                      switch (recurrence) {
                        // continues below...
                        case 'daily':
                          nextDate = nextDate.add(const Duration(days: 1));
                          break;

                        case 'every_other_day':
                          nextDate = nextDate.add(const Duration(days: 2));
                          break;

                        case 'weekly':
                          final days = List<int>.from(
                            fullSchedule['days_of_week'] ?? [],
                          );

                          if (days.isEmpty) {
                            nextDate = nextDate.add(const Duration(days: 7));
                          } else {
                            final currentDay = nextDate.weekday % 7;

                            int? found;

                            for (final d in days) {
                              if (d > currentDay) {
                                found = d;
                                break;
                              }
                            }

                            found ??= days.first + 7;

                            nextDate = nextDate.add(
                              Duration(days: found - currentDay),
                            );
                          }

                          break;

                        case 'monthly':
                          nextDate = DateTime(
                            nextDate.year,
                            nextDate.month + 1,
                            nextDate.day,
                            nextDate.hour,
                            nextDate.minute,
                          );
                          break;
                      }
                    }

                    await Supabase.instance.client
                        .from('checkin_schedules')
                        .update(
                          isRecurring
                              ? {
                                  'status': 'pending',
                                  'completed_at': DateTime.now()
                                      .toIso8601String(),
                                  'scheduled_at': nextDate!.toIso8601String(),
                                  'reminder_sent': false,
                                  'reminder_sent_at': null,
                                }
                              : isWithin5MinEarly
                              ? {
                                  'is_completed': true,
                                  'completed_at': DateTime.now()
                                      .toIso8601String(),
                                  'status': 'completed',
                                }
                              : {
                                  // ✅ Manual check-in — just log the time, keep status as-is
                                  'completed_at': DateTime.now()
                                      .toIso8601String(),
                                },
                        )
                        .eq('id', widget.scheduleId);
                    if (!mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          !isWithin5MinEarly
                              ? "Manual check-in completed"
                              : "Scheduled check-in completed",
                        ),
                      ),
                    );
                    final safety = ref.invalidate(safetyRepositoryProvider);

                    final profile = await ref.read(
                      currentUserProfileProvider.future,
                    );
                    if (profile == null) throw Exception('No profile');
                    final response = await Supabase.instance.client
                        .from('live_locations')
                        .upsert({
                          'user_id': profile.userId,
                          'family_id': profile.familyId,
                          'user_name': profile.fullName,
                          'role': profile.role,
                          'latitude': lat,
                          'longitude': lng,
                          'battery_level': level,
                          'updated_at': DateTime.now().toIso8601String(),
                        }, onConflict: 'user_id')
                        .select();
                    final members = await Supabase.instance.client
                        .from('family_members')
                        .select('user_id, role')
                        .eq('family_id', profile.familyId);

                    for (final m in members) {
                      final targetUserId = m['user_id'];

                      if (targetUserId == profile.userId ||
                          (m['role'] != "leader" && m['role'] != "monitor")) {
                        continue;
                      }
                      try {
                        await Supabase.instance.client.functions.invoke(
                          'push-router',
                          body: {
                            "target_user_id": targetUserId,
                            "title": "Check-In",
                            "body":
                                "${profile.fullName ?? 'Someone'}: Checked in just now",
                            "action": "check_in",
                          },
                        );
                        setState(() {
                          isLoad = false;
                        });
                      } catch (e) {
                        print("Push failed: $e");
                      }
                    }
                  },

                  child: isLoad
                      ? SizedBox(
                          height: 25,
                          width: 25,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : const Text(
                          "CHECK IN NOW",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _timeBox(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}
