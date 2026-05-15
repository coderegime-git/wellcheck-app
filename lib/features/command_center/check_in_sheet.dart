import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/data/safety_repository.dart';
import '../../core/notifications/checkin_service.dart';

class CheckInSheet extends ConsumerStatefulWidget {
  const CheckInSheet({super.key});

  @override
  ConsumerState<CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends ConsumerState<CheckInSheet> {
  bool _isLoading = false;
  bool setCheckIn = false;
  final TextEditingController _statusController = TextEditingController();
  bool _isLoadingMembers = true;
  String? _selectedUserId;
  List<Map<String, dynamic>> _familyMembers = [];
  TimeOfDay? _selectedTime;
  DateTime? _selectedDate;

  @override
  void initState() {
    _fetchFamilyMembers();
    super.initState();
  }

  @override
  void dispose() {
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _fetchFamilyMembers() async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;

      final res = await Supabase.instance.client
          .from('family_members')
          .select('user_id, role, profiles(full_name)')
          .eq('family_id', profile.familyId);

      if (mounted) {
        setState(() {
          _familyMembers = List<Map<String, dynamic>>.from(res);
          _isLoadingMembers = false;
          if (_familyMembers.isNotEmpty) {
            final me = _familyMembers
                .where((m) => m['user_id'] == profile.userId)
                .toList();
            _selectedUserId = me.isNotEmpty
                ? me.first['user_id']
                : _familyMembers.first['user_id'];
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching members: $e');
      if (mounted) setState(() => _isLoadingMembers = false);
    }
  }

  Future<void> _performCheckIn() async {
    setState(() => _isLoading = true);

    try {
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
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile found');

      final msg = _statusController.text.trim();
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
          throw Exception('GPS Location Services are disabled on this device.');
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('permanently denied') ||
            e.toString().contains('disabled')) {
          rethrow;
        }
      }
      await Supabase.instance.client.from('check_ins').insert({
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'latitude': lat,
        'longitude': lng,
        'status_message': msg.isNotEmpty ? msg : defaultMsg,
      });

      // Also register this as a well_event to ensure it shows up securely on the stream!
      await Supabase.instance.client.from('well_events').insert({
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'user_name': profile.fullName,
        'event_type': 'check_in',
        'title': 'Manual Check-in',
        'description': msg.isNotEmpty ? msg : defaultMsg,
        'latitude': lat,
        'longitude': lng,
        'battery_level': level,
      });

      if (mounted) {
        ref.invalidate(safetyRepositoryProvider);
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              gpsSuccess
                  ? 'Check-in successful!'
                  : 'Check-in successful! (GPS unavailable)',
            ),
            backgroundColor: gpsSuccess
                ? ShieldColors.safeZoneGreen
                : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile');

      final members = await Supabase.instance.client
          .from('family_members')
          .select('user_id')
          .eq('family_id', profile.familyId);

      // 3. Send push
      for (final m in members) {
        final targetUserId = m['user_id'];

        if (targetUserId == profile.userId) continue;

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

  // void saveCheckIn() async {
  //   try {
  //     final profile = await ref.read(currentUserProfileProvider.future);
  //     if (profile == null) return;
  //     if (_selectedUserId == null) {
  //       debugPrint("User not selected");
  //       return;
  //     }
  //
  //     if (_selectedDate == null) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Date not selected'),
  //           backgroundColor: Colors.red,
  //         ),
  //       );
  //       debugPrint("Date not selected");
  //       return;
  //     }
  //
  //     if (_selectedTime == null) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Time not selected'),
  //           backgroundColor: Colors.red,
  //         ),
  //       );
  //       debugPrint("Time not selected");
  //       return;
  //     }
  //     setState(() {
  //       setCheckIn = true;
  //     });
  //     final inserted = await Supabase.instance.client
  //         .from('checkin_schedules')
  //         .insert({
  //           'family_id': profile.familyId,
  //           'assigned_user_id': _selectedUserId,
  //           'created_by': profile.userId,
  //           'checkin_date': _selectedDate?.toIso8601String(),
  //           'checkin_time':
  //               '${_selectedTime!.hour}:${_selectedTime!.minute}:00',
  //           'is_active': true,
  //           'is_completed': false,
  //           'status': 'pending',
  //         })
  //         .select()
  //         .single();
  //     // await Supabase.instance.client.functions.invoke(
  //     //   'push-router',
  //     //   body: {
  //     //     "target_user_id": _selectedUserId,
  //     //     "title": "New Check-in Scheduled",
  //     //     "body":
  //     //         "${profile.fullName} scheduled a check-in at ${_selectedTime!.format(context)}",
  //     //     "action": "checkin_schedule",
  //     //   },
  //     // );
  //     await Supabase.instance.client.functions.invoke(
  //       'push-router',
  //       body: {
  //         "target_user_id": _selectedUserId,
  //         "title": "Check-In Scheduled",
  //         "body": "A new check-in reminder has been assigned to you",
  //         "action": "schedule_checkin",
  //         "schedule": jsonEncode(inserted),
  //       },
  //     );
  //     final pending = await FlutterLocalNotificationsPlugin()
  //         .pendingNotificationRequests();
  //
  //     for (final n in pending) {
  //       print('ID: ${n.id}');
  //       print('Title: ${n.title}');
  //       print('Body: ${n.body}');
  //       print('Payload: ${n.payload}');
  //       print('-------------------');
  //     }
  //     debugPrint(inserted.toString());
  //     if (!mounted) return;
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text('Check In scheduled'),
  //         backgroundColor: Colors.teal,
  //       ),
  //     );
  //     context.pop();
  //     setState(() {
  //       setCheckIn = false;
  //     });
  //   } catch (e) {
  //     print(e.toString());
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text('Failed to scheduled'),
  //         backgroundColor: Colors.red,
  //       ),
  //     );
  //     setState(() {
  //       setCheckIn = false;
  //     });
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: MediaQuery.viewInsetsOf(context),
          child: Container(
            decoration: const BoxDecoration(
              color: ShieldColors.backgroundWhite,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              12,
              // MediaQuery.of(context).viewInsets.bottom + 32,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Manual Check-in',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: ShieldColors.textBody,
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          padding: EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.shade400,
                                offset: Offset(0, 0),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.black,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Instantly broadcast your safe location to the family network. Your current GPS coordinates will be captured.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _statusController,
                    decoration: InputDecoration(
                      labelText: 'Optional Status Message',
                      hintText: 'e.g. "Arrived at school safely!"',
                      border: OutlineInputBorder(
                        borderRadius: ShieldDesign.roundedTwelve,
                      ),
                      prefixIcon: const Icon(Icons.chat_bubble_outline),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _performCheckIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ShieldColors.activeTeal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: ShieldDesign.roundedTwelve,
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.how_to_reg),
                                SizedBox(width: 8),
                                Text(
                                  'Broadcast Check-In',
                                  style: TextStyle(
                                    fontSize: 16,
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
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: ShieldColors.activeTeal,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class ScheduleCheckInSheet extends ConsumerStatefulWidget {
  const ScheduleCheckInSheet({super.key});

  @override
  ConsumerState<ScheduleCheckInSheet> createState() =>
      _ScheduleCheckInSheetState();
}

class _ScheduleCheckInSheetState extends ConsumerState<ScheduleCheckInSheet> {
  bool _isLoading = false;
  bool setCheckIn = false;
  final TextEditingController _statusController = TextEditingController();
  bool _isLoadingMembers = true;
  String? _selectedUserId;
  String? _selectedUserName;
  List<Map<String, dynamic>> _familyMembers = [];
  TimeOfDay? _selectedTime;
  DateTime? _selectedDate;
  String _recurrence = 'daily';
  List<int> _selectedDays = [];

  final _dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  static const _recurrenceOptions = [
    ('daily', 'Daily'),
    ('every_other_day', 'Every Other Day'),
    ('weekly', 'Weekly'),
    ('monthly', 'Monthly'),
  ];

  @override
  void initState() {
    _fetchFamilyMembers();
    super.initState();
  }

  @override
  void dispose() {
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _fetchFamilyMembers() async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;

      final res = await Supabase.instance.client
          .from('family_members')
          .select('user_id, role, profiles(full_name)')
          .eq('family_id', profile.familyId);

      if (mounted) {
        setState(() {
          _familyMembers = List<Map<String, dynamic>>.from(res);
          _isLoadingMembers = false;
          if (_familyMembers.isNotEmpty) {
            final me = _familyMembers
                .where((m) => m['user_id'] == profile.userId)
                .toList();
            print(me);
            _selectedUserId = me.isNotEmpty
                ? me.first['user_id']
                : _familyMembers.first['user_id'];
            _selectedUserName = me.isNotEmpty
                ? me.first['profiles']['full_name']
                : _familyMembers.first['profile']['user_id'];
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching members: $e');
      if (mounted) setState(() => _isLoadingMembers = false);
    }
  }

  Future<void> _performCheckIn() async {
    setState(() => _isLoading = true);

    try {
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
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile found');

      final msg = _statusController.text.trim();
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
          throw Exception('GPS Location Services are disabled on this device.');
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('permanently denied') ||
            e.toString().contains('disabled')) {
          rethrow;
        }
      }
      await Supabase.instance.client.from('check_ins').insert({
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'latitude': lat,
        'longitude': lng,
        'status_message': msg.isNotEmpty ? msg : defaultMsg,
      });

      // Also register this as a well_event to ensure it shows up securely on the stream!
      await Supabase.instance.client.from('well_events').insert({
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'user_name': profile.fullName,
        'event_type': 'check_in',
        'title': 'Manual Check-in',
        'description': msg.isNotEmpty ? msg : defaultMsg,
        'latitude': lat,
        'longitude': lng,
        'battery_level': level,
      });

      if (mounted) {
        ref.invalidate(safetyRepositoryProvider);
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              gpsSuccess
                  ? 'Check-in successful!'
                  : 'Check-in successful! (GPS unavailable)',
            ),
            backgroundColor: gpsSuccess
                ? ShieldColors.safeZoneGreen
                : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile');

      final members = await Supabase.instance.client
          .from('family_members')
          .select('user_id')
          .eq('family_id', profile.familyId);

      // 3. Send push
      for (final m in members) {
        final targetUserId = m['user_id'];

        if (targetUserId == profile.userId) continue;

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

  void saveCheckIn() async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;

      if (_selectedUserId == null) {
        debugPrint("User not selected");
        return;
      }

      if (_selectedDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Date not selected'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (_selectedTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Time not selected'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      final selectedDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );

      if (selectedDateTime.isBefore(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a future date and time'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (_recurrence == 'weekly' && _selectedDays.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select at least one day'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      setState(() => setCheckIn = true);

      final localDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );

      final utcDateTime = localDateTime.toUtc();

      final inserted = await Supabase.instance.client
          .from('checkin_schedules')
          .insert({
            'family_id': profile.familyId,
            'assigned_user_id': _selectedUserId,
            'assigned_user_name': _selectedUserName,
            'created_by': profile.userId,
            'checkin_date': _selectedDate?.toIso8601String(),
            'checkin_time':
                '${_selectedTime!.hour}:${_selectedTime!.minute}:00',
            // NEW UTC FIELD
            'scheduled_at': utcDateTime.toIso8601String(),
            'recurrence': _recurrence,
            'is_active': true,
            'is_completed': false,
            'status': 'pending',
            'reminder_sent': false,
            'days_of_week': _selectedDays,
          })
          .select()
          .single();
      debugPrint("_selectedUserId");
      debugPrint(_selectedUserId);
      debugPrint("checkIn Local notification");

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
      await Supabase.instance.client.from('well_events').insert({
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'user_name': profile.fullName,
        'event_type': 'check_in',
        'title': '✅ Check-In Scheduled',
        'description': "Check-in schedule to ${_selectedUserName}",
        'latitude': 0,
        'longitude': 0,
        'battery_level': level,
      });
      final response = await Supabase.instance.client.functions.invoke(
        'checkin-reminder-cron',
        body: {"schedule_id": inserted["id"]},
      );

      debugPrint(response.data.toString());
      // Silent (just schedules locally on User B's device, no popup):

      // Visible (shows a notification AND schedules):
      final targetUser = await Supabase.instance.client
          .from('profiles')
          .select('fcm_token')
          .eq('id', _selectedUserId!)
          .maybeSingle();

      final fcmToken = targetUser?['fcm_token'];

      if (fcmToken != null && fcmToken.toString().isNotEmpty) {
        await Supabase.instance.client.functions.invoke(
          'push-router',
          body: {
            "target_user_id": _selectedUserId,
            "action": "schedule_checkin",
            "schedule": jsonEncode(inserted),
          },
        );

        await Supabase.instance.client.functions.invoke(
          'push-router',
          body: {
            "target_user_id": _selectedUserId,
            "title": "✅ Check-In Scheduled",
            "body": "You'll be reminded at ${_selectedTime!.format(context)}",
            "action": "schedule_checkin",
            "schedule": jsonEncode(inserted),
          },
        );
      } else {
        debugPrint('[CheckIn] Assigned user has no FCM token');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Check-in scheduled'),
          backgroundColor: Colors.teal,
        ),
      );
      context.pop();
    } catch (e) {
      debugPrint('[CheckIn] Error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to schedule'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => setCheckIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: MediaQuery.viewInsetsOf(context),
          child: Container(
            decoration: const BoxDecoration(
              color: ShieldColors.backgroundWhite,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              12,
              // MediaQuery.of(context).viewInsets.bottom + 32,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        'Check-In',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: ShieldColors.textBody,
                        ),
                      ),
                      Spacer(),

                      GestureDetector(
                        onTap: () async {
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          padding: EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.shade400,
                                offset: Offset(0, 0),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.black,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _sectionLabel('Assign To'),
                  if (_isLoadingMembers)
                    const Center(child: CircularProgressIndicator()),
                  if (_familyMembers.isEmpty)
                    Text("No Family member")
                  else if (_familyMembers.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: _selectedUserId,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: ShieldDesign.roundedTwelve,
                        ),
                        prefixIcon: const Icon(Icons.person),
                      ),
                      items: _familyMembers.map((m) {
                        final name = m['profiles']?['full_name'] ?? 'Unknown';

                        final role = m['role'];

                        return DropdownMenuItem<String>(
                          value: m['user_id'] as String,
                          child: Text('$name ($role)'),
                        );
                      }).toList(),

                      onChanged: (val) {
                        final selectedMember = _familyMembers.firstWhere(
                          (m) => m['user_id'] == val,
                        );

                        setState(() {
                          _selectedUserId = val;

                          _selectedUserName =
                              selectedMember['profiles']?['full_name'] ??
                              'Unknown';
                        });
                      },

                      validator: (val) => val == null ? 'Required' : null,
                    ),
                  SizedBox(height: 15),
                  _sectionLabel('Check-in Details'),
                  _sectionLabel('Schedule'),

                  DropdownButtonFormField<String>(
                    value: _recurrence,
                    decoration: InputDecoration(
                      labelText: 'Recurrence',
                      border: OutlineInputBorder(
                        borderRadius: ShieldDesign.roundedTwelve,
                      ),
                      prefixIcon: const Icon(Icons.repeat),
                    ),
                    items: _recurrenceOptions.map((r) {
                      return DropdownMenuItem(value: r.$1, child: Text(r.$2));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _recurrence = val;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 15),
                  if (_recurrence == 'weekly') ...[
                    const SizedBox(height: 12),

                    _sectionLabel('Repeat on'),

                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: List.generate(7, (i) {
                        final selected = _selectedDays.contains(i);

                        return FilterChip(
                          label: Text(_dayLabels[i]),

                          selected: selected,

                          selectedColor: ShieldColors.activeTeal.withValues(
                            alpha: 0.2,
                          ),

                          checkmarkColor: ShieldColors.activeTeal,

                          onSelected: (val) {
                            setState(() {
                              if (val) {
                                _selectedDays.add(i);
                              } else {
                                _selectedDays.remove(i);
                              }

                              _selectedDays.sort();
                            });
                          },
                        );
                      }),
                    ),
                  ],
                  const SizedBox(height: 15),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time),
                    title: Text(
                      _selectedTime == null
                          ? 'Select Time'
                          : _selectedTime!.format(context),
                    ),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );

                      if (picked != null) {
                        setState(() => _selectedTime = picked);
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,

                    leading: const Icon(Icons.calendar_month),
                    title: Text(
                      _selectedDate == null
                          ? 'Select Date'
                          : DateFormat('dd MMM yyyy').format(_selectedDate!),
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                        initialDate: DateTime.now(),
                      );

                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                  ),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: setCheckIn ? null : saveCheckIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ShieldColors.activeTeal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: ShieldDesign.roundedTwelve,
                        ),
                      ),
                      child: setCheckIn
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.how_to_reg),
                                SizedBox(width: 8),
                                Text(
                                  'Schedule Check-In',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: ShieldColors.activeTeal,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
