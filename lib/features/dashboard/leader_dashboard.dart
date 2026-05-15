import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/data/auth_repository.dart';
import 'package:well_check_v3/core/data/medication_provider.dart';
import 'package:well_check_v3/core/data/safe_zone_provider.dart';
import 'package:well_check_v3/core/data/tools_repository.dart';
import 'package:well_check_v3/features/dashboard/widgets/pending_actions_card.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/data/safety_repository.dart';
import 'package:well_check_v3/features/dashboard/widgets/shield_member_card.dart';
import 'package:well_check_v3/features/dashboard/widgets/invite_member_dialog.dart';
import 'package:well_check_v3/features/dashboard/widgets/command_center_sheet.dart';
import 'package:well_check_v3/features/dashboard/widgets/ai_wellness_card.dart';
import 'package:well_check_v3/features/profile/profile_settings_view.dart';
import 'package:well_check_v3/features/tools/safe_zone_config_screen.dart';

import '../../core/navigation/shield_router.dart';
import '../../core/notifications/push_notification_service.dart';
import '../safety/services/pulse_service.dart';

class LeaderDashboard extends ConsumerStatefulWidget {
  const LeaderDashboard({super.key});

  @override
  ConsumerState<LeaderDashboard> createState() => _LeaderDashboardState();
}

class _LeaderDashboardState extends ConsumerState<LeaderDashboard> {
  bool _sosCountdownActive = false;
  int _sosCountdown = 5;
  Timer? _sosTimer;
  bool isLoad = true;

  @override
  void initState() {
    initializeFCM();
    super.initState();
  }

  void initializeFCM() async {
    // await  PulseService().broadcastPulse(null);
    await PulseService().broadcastPulse(null);
    setState(() {
      isLoad = false;
    });
    if (!mounted) return;
    await PushNotificationService.initialize();
  }

  @override
  void dispose() {
    _sosTimer?.cancel();
    super.dispose();
  }

  void _startSosCountdown() {
    if (isLoad) return;

    if (_sosCountdownActive) {
      _sosTimer?.cancel();
      setState(() {
        _sosCountdownActive = false;
        _sosCountdown = 5;
      });
      return;
    }

    setState(() {
      isLoad = true;
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
                isLoad = false;

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
                '${profile.fullName}- Leader manually initiated an emergency state',
              );

          if (mounted) {
            setState(() {
              isLoad = false;

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
                  },
                );
              } catch (e) {
                debugPrint("Push failed: $e");
              }
            }
          }
        } catch (e) {
          debugPrint('[SOS] triggerSiren failed: $e');
          if (mounted) {
            setState(() {
              isLoad = false;

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

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final medicationsAsync = ref.watch(familyMedicationsProvider);

    return isLoad
        ? Scaffold(
            backgroundColor: Colors.white,

            body: Center(child: CircularProgressIndicator()),
          )
        : Scaffold(
            backgroundColor: ShieldColors.activeTeal,
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 8),

                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Image.asset('assets/logo.png', height: 40, width: 40),
                        SizedBox(width: 6),
                        Text(
                          "Well-Check",
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: ShieldColors.backgroundWhite,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                        ),
                        Spacer(),
                        Container(
                          padding: EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: GestureDetector(
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => const ProfileSettingsView(),
                              );
                            },
                            child: Icon(
                              Icons.menu,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                  // Header — Bug 1: Responsive scaling, Bug 2: Working notification bell
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 16.0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              profileAsync.when(
                                data: (profile) {
                                  final firstName =
                                      profile?.fullName?.split(' ').first ??
                                      'Leader';
                                  return Text(
                                    'Welcome, $firstName.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: ShieldColors.textBody,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  );
                                },
                                loading: () => Text(
                                  'Welcome back...',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: ShieldColors.textBody,
                                      ),
                                ),
                                error: (e, st) => Text(
                                  'Welcome, Leader.',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: ShieldColors.textBody,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 4),

                              Row(
                                children: [
                                  Icon(
                                    Icons.privacy_tip,
                                    color: ShieldColors.activeTeal,
                                    size: 22,
                                  ),
                                  SizedBox(width: 5),
                                  Text(
                                    'The Shield is active',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: ShieldColors.textLabel,
                                        ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            profileAsync.when(
                              data: (profile) {
                                return profile != null &&
                                        profile!.avatarUrl != null
                                    ? CircleAvatar(
                                        radius: 35,
                                        backgroundColor:
                                            ShieldColors.activeTeal,

                                        backgroundImage: NetworkImage(
                                          profile!.avatarUrl ?? "",
                                        ),
                                      )
                                    : CircleAvatar(
                                        backgroundColor:
                                            ShieldColors.activeTeal,

                                        radius: 35,
                                        child: Icon(
                                          size: 35,
                                          Icons.person,
                                          color: Colors.white,
                                        ),
                                      );
                              },
                              loading: () => SizedBox.shrink(),
                              error: (e, st) => SizedBox.shrink(),
                            ),
                            SizedBox(width: 10),
                            Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: ShieldDesign.roundedTwelve,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: GestureDetector(
                                child: const Icon(
                                  size: 20,
                                  Icons.person_add_alt_1,
                                  color: ShieldColors.activeTeal,
                                ),
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) =>
                                        const InviteMemberDialog(),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Bug 2: Notification bell now shows recent events
                            Container(
                              padding: EdgeInsets.all(10),

                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: ShieldDesign.roundedTwelve,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: profileAsync.value == null
                                  ? GestureDetector(
                                      child: const Icon(
                                        size: 20,

                                        Icons.notifications_none,
                                        color: ShieldColors.textBody,
                                      ),
                                      onTap: () {},
                                    )
                                  : StreamBuilder<List<Map<String, dynamic>>>(
                                      stream: ref
                                          .watch(safetyRepositoryProvider)
                                          .streamFamilyEvents(
                                            profileAsync.value!.familyId,
                                          ),
                                      builder: (context, snapshot) {
                                        final events = snapshot.data ?? [];
                                        final hasRecent = events.any((e) {
                                          final dt = DateTime.tryParse(
                                            e['created_at'] ?? '',
                                          );
                                          return dt != null &&
                                              DateTime.now()
                                                      .difference(dt)
                                                      .inHours <
                                                  24;
                                        });
                                        return Stack(
                                          alignment: Alignment.topRight,
                                          children: [
                                            GestureDetector(
                                              child: const Icon(
                                                size: 20,

                                                Icons.notifications_none,
                                                color: ShieldColors.textBody,
                                              ),
                                              onTap: () {
                                                showModalBottomSheet(
                                                  context: context,
                                                  isScrollControlled: true,
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  builder: (ctx) =>
                                                      _NotificationsSheet(
                                                        familyId: profileAsync
                                                            .value!
                                                            .familyId,
                                                        safetyRepo: ref.read(
                                                          safetyRepositoryProvider,
                                                        ),
                                                      ),
                                                );
                                              },
                                            ),
                                            if (hasRecent)
                                              Positioned(
                                                right: 3,
                                                top: 0,
                                                child: Container(
                                                  width: 6,
                                                  height: 6,
                                                  decoration:
                                                      const BoxDecoration(
                                                        color: ShieldColors
                                                            .urgentRed,
                                                        shape: BoxShape.circle,
                                                      ),
                                                ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Leader Dashboard Content
                  Expanded(
                    child: profileAsync.when(
                      data: (profile) {
                        if (profile == null) {
                          return const Center(
                            child: Text('No profile found. Please register.'),
                          );
                        }

                        final safetyRepo = ref.watch(safetyRepositoryProvider);

                        return Container(
                          decoration: BoxDecoration(color: Colors.grey.shade50),
                          child: RefreshIndicator(
                            onRefresh: () async {
                              final safetyRepo = ref.invalidate(
                                safetyRepositoryProvider,
                              );
                            },
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const PendingActionsCard(),
                                  // Pending Members List
                                  StreamBuilder<List<Map<String, dynamic>>>(
                                    stream: safetyRepo.streamPendingMembers(
                                      profile.familyId,
                                    ),
                                    builder: (context, snapshot) {
                                      final pending = snapshot.data ?? [];
                                      if (pending.isEmpty) {
                                        return const SizedBox.shrink();
                                      }

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Pending Approvals (${pending.length})',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: ShieldColors.urgentRed,
                                                ),
                                          ),
                                          const SizedBox(height: 12),
                                          ...pending.map(
                                            (member) => Card(
                                              margin: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    ShieldDesign.roundedTwelve,
                                                side: const BorderSide(
                                                  color: ShieldColors.urgentRed,
                                                  width: 1,
                                                ),
                                              ),
                                              child: ListTile(
                                                leading: const Icon(
                                                  Icons.person_add_alt_1,
                                                  color: ShieldColors.urgentRed,
                                                ),
                                                title: Text(
                                                  member['full_name'] != null
                                                      ? '${member['full_name']} (${member['role']})'
                                                      : 'New ${member['role'] ?? 'Member'} Request',
                                                ),
                                                subtitle: Text(
                                                  'User ID: ${member['id'].toString().substring(0, 8)}...',
                                                ),
                                                trailing: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.check_circle,
                                                        color: ShieldColors
                                                            .safeZoneGreen,
                                                      ),
                                                      onPressed: () =>
                                                          safetyRepo
                                                              .approveMember(
                                                                member['id'],
                                                              ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.cancel,
                                                        color: Colors.grey,
                                                      ),
                                                      onPressed: () =>
                                                          safetyRepo
                                                              .rejectMember(
                                                                member['id'],
                                                              ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 24),
                                        ],
                                      );
                                    },
                                  ),
                                  StreamBuilder<List<Map<String, dynamic>>>(
                                    stream: safetyRepo.streamLeaderSchedules(
                                      profile.familyId,
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
                                      Map<String, dynamic>? selectedSchedule;
                                      String assignedUser = '';
                                      for (final s in schedules) {
                                        print(s);
                                        print('checkin_time');
                                        final time = s['checkin_time'];
                                        final name = s['assigned_user_name'];

                                        final next = _getNextCheckinTime(s);

                                        if (next == null) continue;
                                        if (nextCheckin == null ||
                                            next.isBefore(nextCheckin)) {
                                          nextCheckin = next;
                                          selectedSchedule = s;
                                          assignedUser = name;
                                        }
                                      }

                                      if (nextCheckin == null ||
                                          selectedSchedule == null) {
                                        return const SizedBox.shrink();
                                      }

                                      final scheduleId = selectedSchedule['id'];
                                      final assignedUserId =
                                          selectedSchedule['assigned_user_id'];
                                      print("nextCheckin$nextCheckin");
                                      return _NextCheckinCard(
                                        nextCheckin: nextCheckin,
                                        profile: profileAsync.value,
                                        scheduleId: scheduleId,
                                        assignedUser: assignedUser,
                                        assignedUserId: assignedUserId,
                                      );
                                    },
                                  ),
                                  SizedBox(height: 10),
                                  medicationsAsync.when(
                                    data: (medications) {
                                      final activeMeds = medications
                                          .where((m) => m.isActive)
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
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.04,
                                              ),
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
                                                    color:
                                                        ShieldColors.textLabel,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 1.2,
                                                  ),
                                            ),

                                            const SizedBox(height: 14),

                                            ...activeMeds.map((med) {
                                              // final nextDose = med.nextDoseToday;
                                              DateTime? nextDose;

                                              if (med
                                                  .scheduleTimes
                                                  .isNotEmpty) {
                                                final now = DateTime.now();

                                                final upcomingDoses =
                                                    <DateTime>[];

                                                final startDate =
                                                    med.startDate ?? now;

                                                for (final time
                                                    in med.scheduleTimes) {
                                                  try {
                                                    final parts = time.split(
                                                      ':',
                                                    );

                                                    final hour = int.parse(
                                                      parts[0],
                                                    );
                                                    final minute = int.parse(
                                                      parts[1],
                                                    );

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

                                                    // DAILY
                                                    if (frequency.contains(
                                                      'daily',
                                                    )) {
                                                      if (doseTime.isBefore(
                                                        now,
                                                      )) {
                                                        doseTime = doseTime.add(
                                                          const Duration(
                                                            days: 1,
                                                          ),
                                                        );
                                                      }
                                                    }
                                                    // EVERY OTHER DAY
                                                    else if (frequency.contains(
                                                      'every other',
                                                    )) {
                                                      final daysSinceStart = now
                                                          .difference(startDate)
                                                          .inDays;

                                                      final shouldTakeToday =
                                                          daysSinceStart % 2 ==
                                                          0;

                                                      if (!shouldTakeToday ||
                                                          doseTime.isBefore(
                                                            now,
                                                          )) {
                                                        doseTime = doseTime.add(
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
                                                          doseTime = doseTime
                                                              .add(
                                                                const Duration(
                                                                  days: 1,
                                                                ),
                                                              );
                                                        }
                                                      }
                                                    }
                                                    // WEEKLY
                                                    else if (frequency.contains(
                                                      'weekly',
                                                    )) {
                                                      doseTime = DateTime(
                                                        now.year,
                                                        now.month,
                                                        now.day,
                                                        hour,
                                                        minute,
                                                      );

                                                      while (doseTime.weekday !=
                                                              startDate
                                                                  .weekday ||
                                                          doseTime.isBefore(
                                                            now,
                                                          )) {
                                                        doseTime = doseTime.add(
                                                          const Duration(
                                                            days: 1,
                                                          ),
                                                        );
                                                      }
                                                    }
                                                    // MONTHLY
                                                    else if (frequency.contains(
                                                      'monthly',
                                                    )) {
                                                      doseTime = DateTime(
                                                        now.year,
                                                        now.month,
                                                        startDate.day,
                                                        hour,
                                                        minute,
                                                      );

                                                      if (doseTime.isBefore(
                                                        now,
                                                      )) {
                                                        doseTime = DateTime(
                                                          now.year,
                                                          now.month + 1,
                                                          startDate.day,
                                                          hour,
                                                          minute,
                                                        );
                                                      }
                                                    }
                                                    // AS NEEDED
                                                    else if (frequency.contains(
                                                      'as needed',
                                                    )) {
                                                      continue;
                                                    }

                                                    upcomingDoses.add(doseTime);
                                                  } catch (e) {
                                                    debugPrint(
                                                      "Dose parse error: $e",
                                                    );
                                                  }
                                                }

                                                upcomingDoses.sort();

                                                if (upcomingDoses.isNotEmpty) {
                                                  nextDose =
                                                      upcomingDoses.first;
                                                }
                                              }
                                              String countdownText =
                                                  'No upcoming dose';
                                              Color statusColor = Colors.grey;

                                              Duration? diff;

                                              if (nextDose != null) {
                                                diff = nextDose.difference(
                                                  DateTime.now(),
                                                );
                                              }
                                              countdownText =
                                                  '${diff?.inHours}h ${diff?.inMinutes.remainder(60)}m ${diff?.inSeconds.remainder(60)}s';
                                              return Container(
                                                margin: const EdgeInsets.only(
                                                  bottom: 12,
                                                ),
                                                padding: const EdgeInsets.all(
                                                  14,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                  border: Border.all(
                                                    color: statusColor
                                                        .withValues(alpha: 0.2),
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

                                                    const SizedBox(width: 7),

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
                                                                        FontWeight
                                                                            .bold,
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
                                                                            seconds:
                                                                                1,
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
                                                                        FontWeight
                                                                            .bold,
                                                                    color: ShieldColors
                                                                        .activeTeal,
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
                                    error: (e, st) => const SizedBox.shrink(),
                                  ),
                                  // Active Members Stream
                                  Text(
                                    'Shield Members',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: ShieldColors.textBody,
                                        ),
                                  ),
                                  const SizedBox(height: 16),

                                  StreamBuilder<List<Map<String, dynamic>>>(
                                    stream: safetyRepo.streamActiveMembers(
                                      profile.familyId,
                                    ),
                                    builder: (context, memberSnapshot) {
                                      if (memberSnapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const Center(
                                          child: CircularPulseIndicator(),
                                        );
                                      }

                                      final members = memberSnapshot.data ?? [];

                                      if (members.isEmpty) {
                                        return const Text(
                                          'No members found. Invite some!',
                                        );
                                      }

                                      return Column(
                                        children: members.map((member) {
                                          return _MemberStatusCard(
                                            member: member,
                                            safetyRepo: safetyRepo,
                                            currentUserId: profile.userId,
                                          );
                                        }).toList(),
                                      );
                                    },
                                  ),

                                  // Recent Events Stream — Bug 3: Improved formatting
                                  const SizedBox(height: 20),
                                  // Text(
                                  //   'Recent Activity',
                                  //   style: Theme.of(context).textTheme.titleLarge
                                  //       ?.copyWith(
                                  //         fontWeight: FontWeight.bold,
                                  //         color: ShieldColors.textBody,
                                  //       ),
                                  // ),
                                  // const SizedBox(height: 16),

                                  // StreamBuilder<List<Map<String, dynamic>>>(
                                  //   stream: safetyRepo.streamFamilyEvents(
                                  //     profile.familyId,
                                  //   ),
                                  //   builder: (context, eventSnapshot) {
                                  //     if (eventSnapshot.connectionState ==
                                  //         ConnectionState.waiting) {
                                  //       return const Center(
                                  //         child: CircularProgressIndicator(),
                                  //       );
                                  //     }
                                  //
                                  //     final events = eventSnapshot.data ?? [];
                                  //     if (events.isEmpty) {
                                  //       return const Padding(
                                  //         padding: EdgeInsets.symmetric(vertical: 32),
                                  //         child: Center(
                                  //           child: Column(
                                  //             children: [
                                  //               Icon(
                                  //                 Icons.history,
                                  //                 size: 48,
                                  //                 color: Colors.grey,
                                  //               ),
                                  //               SizedBox(height: 8),
                                  //               Text(
                                  //                 'No recent activity yet.\nCheck-ins, SOS events, and status updates will appear here.',
                                  //                 textAlign: TextAlign.center,
                                  //                 style: TextStyle(
                                  //                   color: ShieldColors.textLabel,
                                  //                 ),
                                  //               ),
                                  //             ],
                                  //           ),
                                  //         ),
                                  //       );
                                  //     }
                                  //
                                  //     return Container(
                                  //       decoration: BoxDecoration(
                                  //         color: Colors.white,
                                  //         borderRadius: ShieldDesign.roundedTwelve,
                                  //       ),
                                  //       child: ListView.separated(
                                  //         shrinkWrap: true,
                                  //         physics: const NeverScrollableScrollPhysics(),
                                  //         itemCount: events.length > 10
                                  //             ? 10
                                  //             : events.length,
                                  //         separatorBuilder: (context, index) =>
                                  //             const Divider(height: 1),
                                  //         itemBuilder: (context, index) {
                                  //           final evt = events[index];
                                  //           return _buildEventTile(evt);
                                  //         },
                                  //       ),
                                  //     );
                                  //   },
                                  // ),
                                  _buildRecentActivity(
                                    context,
                                    safetyRepo,
                                    profile.familyId,
                                  ),

                                  const SizedBox(height: 20),
                                  const AiWellnessCard(),
                                  const SizedBox(height: 100),
                                  // Space for bottom nav
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, st) => Center(child: Text('Error: $e')),
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: Container(
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      // Large EMERGENCY button
                      Expanded(
                        flex: 2,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: 60,
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
                              elevation: 6,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.warning_rounded, size: 24),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _sosCountdownActive
                                        ? 'CANCEL ($_sosCountdown)'
                                        : 'EMERGENCY',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      letterSpacing: 1,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // COMMAND CENTER button
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 60,
                          child: ElevatedButton(
                            onPressed: () async {
                              await showModalBottomSheet(
                                context: context,

                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (context) =>
                                    CommandCenterSheet(fromLeader: true),
                              );
                              //   ref.invalidate(safetyRepositoryProvider);
                              //  ref.invalidate(userRoleProvider);
                              //  ref.invalidate(currentUserProfileProvider);
                              // ref.invalidate(shieldRouterProvider);
                              // ref.invalidate(allDoseLogsProvider);
                              // ref.invalidate(familySafeZonesProvider);
                              // ref.invalidate(familyMedicationsProvider);
                              // ref.invalidate(toolsRepositoryProvider);
                              //   ref.invalidate(authRepositoryProvider);
                              //  ref.invalidate(safeZonesStreamProvider);
                              //  Navigator.push(context, MaterialPageRoute(builder: (context)=>CommandCenterSheet()));
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ShieldColors.activeTeal,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: ShieldDesign.roundedTwelve,
                              ),
                              elevation: 4,
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.grid_view_rounded, size: 22),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'MENU',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      letterSpacing: 1,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // const SizedBox(width: 8),
                      // // Profile icon button
                      // Container(
                      //   decoration: BoxDecoration(
                      //     borderRadius: BorderRadius.circular(30),
                      //     color: Colors.white,
                      //   ),
                      //   height: 60,
                      //   width: 60,
                      //   child: GestureDetector(
                      //     onTap: () {
                      //       showModalBottomSheet(
                      //         context: context,
                      //         isScrollControlled: true,
                      //         backgroundColor: Colors.transparent,
                      //         builder: (_) => const ProfileSettingsView(),
                      //       );
                      //     },
                      //
                      //     child: profileAsync.value?.avatarUrl != null
                      //         ? Container(
                      //             padding: EdgeInsets.all(10),
                      //             clipBehavior: Clip.antiAlias,
                      //             decoration: BoxDecoration(),
                      //             child: ClipRRect(
                      //               borderRadius: BorderRadius.circular(30),
                      //               //  borderRadius: ShieldDesign.roundedTwelve,
                      //               child: Image.network(
                      //                 profileAsync.value!.avatarUrl!,
                      //                 fit: BoxFit.cover,
                      //               ),
                      //             ),
                      //           )
                      //         : const Icon(Icons.person_outline, size: 26),
                      //   ),
                      // ),
                    ],
                  ),
                ),
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

  Widget _buildRecentActivity(BuildContext context, safetyRepo, familyId) {
    return Container(
      //padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart, color: Colors.green.shade600, size: 18),
              const SizedBox(width: 8),
              Text(
                'Recent Activity',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ShieldColors.textBody,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: safetyRepo.streamFamilyEvents(familyId),
            builder: (context, eventSnapshot) {
              if (eventSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final events = eventSnapshot.data ?? [];
              if (events.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.history, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text(
                          'No recent activity yet.\nCheck-ins, SOS events, and status updates will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: ShieldColors.textLabel),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final latestEvent = events.first;

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: ShieldDesign.roundedTwelve,
                  border: Border.all(color: Colors.grey.shade200, width: 0.5),
                ),
                child: Column(
                  children: [
                    _buildEventTile(latestEvent),
                    const Divider(height: 1),
                    _buildStatsSummary(events),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  int _computeAvgBpm(List<Map<String, dynamic>> events) {
    final bpmValues = events.map((e) => e['bpm']).whereType<num>().toList();

    if (bpmValues.isEmpty) return 0;

    final sum = bpmValues.fold<num>(0, (acc, val) => acc + val);
    return (sum / bpmValues.length).round();
  }

  Widget _buildStatsSummary(List<Map<String, dynamic>> events) {
    final avgBpm = _computeAvgBpm(events);
    final battery = events.first['battery_level'] ?? 0;
    final checkIns = events.where((e) => e['type'] == 'check_in').length;
    print(battery);
    print(events.first['battery_level']);
    print("batterybattery");
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _buildStatChip(
            icon: Icons.favorite,
            color: Colors.red,
            value: '$avgBpm',
            label: 'Avg BPM',
          ),
          _buildStatChip(
            icon: CupertinoIcons.battery_25_percent,
            color: Colors.green,
            value: '$battery%',
            label: 'Battery',
          ),
          _buildStatChip(
            icon: Icons.access_time_filled,
            color: Colors.blue,
            value: '$checkIns',
            label: 'Check-ins',
          ),
          _buildStatChip(
            icon: Icons.safety_check_rounded,
            color: Colors.teal,
            value: 'Active',
            label: 'Status',
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24, color: color),
                const SizedBox(width: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade900),
            ),
          ],
        ),
      ),
    );
  }

  /// Bug 3: Improved event tile with readable timestamps and icons
  Widget _buildEventTile(Map<String, dynamic> evt) {
    print(evt);
    print("evtevt");
    final type = (evt['event_type'] as String?) ?? 'unknown';
    final title =
        evt['title'] as String? ?? type.replaceAll('_', ' ').toUpperCase();
    final description = evt['description'] as String?;
    final fullName = evt['user_name'] as String?;
    final battery = evt['battery_level'];
    final createdAt = evt['created_at'] as String?;

    IconData icon = Icons.favorite_border;
    Color color = ShieldColors.activeTeal;

    switch (type) {
      case 'sos':
        icon = Icons.warning_amber_rounded;
        color = ShieldColors.urgentRed;
        break;
      case 'driving':
      case 'driving_alert':
        icon = Icons.directions_car;
        color = Colors.orange;
        break;
      case 'check_in':
        icon = Icons.how_to_reg;
        color = ShieldColors.safeZoneGreen;
        break;
      case 'medication_logged':
        icon = Icons.medical_services;
        color = Colors.purple;
        break;
      case 'campus_alert':
        icon = Icons.school;
        color = ShieldColors.alertRed;
        break;
      case 'status_update':
        icon = Icons.info_outline;
        color = Colors.blueGrey;
        break;
      case 'heartbeat':
        icon = Icons.favorite;
        color = ShieldColors.activeTeal;
        break;
      case 'safe_zone_enter':
        icon = Icons.verified_user;
        color = ShieldColors.safeZoneGreen;
        break;
      case 'vital_anomaly':
        icon = Icons.monitor_heart;
        color = ShieldColors.urgentRed;
        break;
    }

    String timeAgo = '';
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt);
        final diff = DateTime.now().difference(dt);
        if (diff.inMinutes < 1) {
          timeAgo = 'Just now';
        } else if (diff.inMinutes < 60) {
          timeAgo = '${diff.inMinutes}m ago';
        } else if (diff.inHours < 24) {
          timeAgo = '${diff.inHours}h ago';
        } else {
          timeAgo = DateFormat.MMMd().format(dt);
        }
      } catch (_) {
        timeAgo = '';
      }
    }

    return ListTile(
      leading: Icon(icon, color: color),
      // title: Row(
      //   children: [
      //     if(fullName!=null&&fullName!='')
      //     Expanded(
      //       child: Text('$fullName-'??"", style: TextStyle(
      //         fontWeight: FontWeight.bold,
      //         color: Colors.black,
      //         fontSize: 12,
      //       ),),
      //     ),
      //     Text(
      //       title,
      //       style: TextStyle(
      //         fontWeight: FontWeight.bold,
      //         color: color,
      //         fontSize: 13,
      //       ),
      //     ),
      //   ],
      // ),
      title: RichText(
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            if (fullName != null && fullName != '')
              TextSpan(
                text: '$fullName - ',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  fontSize: 12,
                ),
              ),

            TextSpan(
              text: title,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: ShieldColors.activeTeal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),

      subtitle: Text(
        description ?? (battery != null ? 'Battery: $battery%' : ''),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        timeAgo,
        style: const TextStyle(color: ShieldColors.textLabel, fontSize: 11),
      ),
    );
  }
}

/// Member cards with REAL data from latest events + live vitals
class _MemberStatusCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final SafetyRepository safetyRepo;
  final String currentUserId;

  const _MemberStatusCard({
    required this.member,
    required this.safetyRepo,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final userId = member['id'] as String;
    return StreamBuilder<Map<String, dynamic>?>(
      stream: safetyRepo.streamMemberLatestEvent(userId),
      builder: (context, eventSnapshot) {
        // Nest a second StreamBuilder to get live vitals
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: safetyRepo.streamMemberVitals(userId),
          builder: (context, vitalsSnapshot) {
            final lastEvent = eventSnapshot.data;
            print("lastEvent");
            print(lastEvent);
            final vitals = vitalsSnapshot.data ?? [];
            print("vitals");
            print(vitals);
            print(member);
            print("lastEvent");
            print(lastEvent);
            print('created_at');
            print(member['timestamp']);
            final role = member['role'] as String;
            final realName = member['full_name'] ?? 'Family Member';
            final isMe = userId == currentUserId;

            String displayName = isMe ? '$realName (You)' : realName;
            IconData statusIcon = Icons.info_outline;
            String statusText = 'Awaiting first pulse...';
            bool isAlert = false;
            List<Map<String, String>> metrics = [];

            // --- Derive status from latest event ---
            if (lastEvent != null) {
              final type = lastEvent['event_type'] as String;
              final battery = lastEvent['battery_level'];
              final createdAt = lastEvent['created_at'] as String?;

              String lastSeen = '';
              if (createdAt != null) {
                try {
                  final dt = DateTime.parse(createdAt);
                  final diff = DateTime.now().difference(dt);
                  if (diff.inMinutes < 5) {
                    lastSeen = 'Just now';
                  } else if (diff.inMinutes < 60) {
                    lastSeen = '${diff.inMinutes}m ago';
                  } else if (diff.inHours < 24) {
                    lastSeen = '${diff.inHours}h ago';
                  } else {
                    lastSeen = '${diff.inDays}d ago';
                  }
                } catch (_) {}
              }

              if (type == 'sos' &&
                  lastEvent['metadata']?['status'] != 'resolved') {
                isAlert = true;
                statusText = 'EMERGENCY: SOS ACTIVE';
                statusIcon = Icons.warning;
              } else if (type == 'driving' || type == 'driving_alert') {
                statusText = 'In Motion: Driving';
                statusIcon = Icons.directions_car;
              } else if (type == 'safe_zone_enter') {
                statusText = 'In Safe Zone';
                statusIcon = Icons.verified_user;
              } else if (type == 'check_in') {
                statusText = 'Checked In';
                statusIcon = Icons.how_to_reg;
              } else {
                statusText = lastSeen.isNotEmpty
                    ? 'Last seen $lastSeen'
                    : 'Online';
                statusIcon = Icons.check_circle_outline;
              }

              if (battery != null) {
                metrics.add({
                  'label': 'BATTERY',
                  'value': '$battery',
                  'unit': '%',
                });
              }

              final semLoc = lastEvent['metadata']?['semantic_location'];
              if (semLoc != null) {
                metrics.add({'label': 'LOC', 'value': '$semLoc', 'unit': ''});
              } else if (lastEvent['latitude'] != null) {
                metrics.add({
                  'label': 'LOC',
                  'value': 'GPS Active',
                  'unit': '',
                });
              }
            } else {
              statusText = 'No pulse data yet';
              statusIcon = Icons.radio_button_unchecked;
            }

            // --- Live Vitals from health_vitals table ---
            if (vitals.isNotEmpty) {
              // Extract latest heart rate
              final hrEntry = vitals
                  .where((v) => v['vital_type'] == 'HEART_RATE')
                  .toList();
              if (hrEntry.isNotEmpty) {
                final hrVal = hrEntry.first['value'];
                final hrNum = (hrVal is num)
                    ? hrVal.round()
                    : (double.tryParse(hrVal.toString())?.round() ?? 0);
                metrics.add({'label': 'HR', 'value': '$hrNum', 'unit': 'BPM'});
              }

              // Extract latest SpO2
              final spo2Entry = vitals
                  .where((v) => v['vital_type'] == 'BLOOD_OXYGEN')
                  .toList();
              if (spo2Entry.isNotEmpty) {
                final spo2Val = spo2Entry.first['value'];
                final spo2Num = (spo2Val is num)
                    ? spo2Val.round()
                    : (double.tryParse(spo2Val.toString())?.round() ?? 0);
                metrics.add({
                  'label': 'SpO2',
                  'value': '$spo2Num',
                  'unit': '%',
                });
              }
            } else if (role == 'senior') {
              // No vitals synced yet for senior
              metrics.add({
                'label': 'VITALS',
                'value': 'No wearable',
                'unit': '',
              });
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: ShieldMemberCard(
                name: displayName,
                status: role.toUpperCase(),
                metrics: metrics,
                subStatusIcon: statusIcon,
                subStatusText: statusText,
                isAlert: isAlert,
                avatarUrl: member['avatar_url'] as String?,
              ),
            );
          },
        );
      },
    );
  }
}

/// Bug 2: Notification bell bottom sheet
class _NotificationsSheet extends StatelessWidget {
  final String familyId;
  final SafetyRepository safetyRepo;

  const _NotificationsSheet({required this.familyId, required this.safetyRepo});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ShieldColors.backgroundWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
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
            'Notifications',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: safetyRepo.streamFamilyEvents(familyId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final events = snapshot.data ?? [];
                if (events.isEmpty) {
                  return const Center(
                    child: Text(
                      'No notifications yet.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: events.length > 20 ? 20 : events.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final evt = events[index];
                    final type = (evt['event_type'] as String?) ?? 'unknown';
                    final title =
                        evt['title'] as String? ?? type.replaceAll('_', ' ');
                    final desc = evt['description'] as String? ?? '';
                    final userName = evt['user_name'] as String? ?? '';
                    final createdAt = evt['created_at'] as String?;
                    print(evt);
                    print("evtevt");
                    String timeStr = '';
                    if (createdAt != null) {
                      try {
                        final dt = DateTime.parse(createdAt);
                        timeStr = DateFormat.jm().format(dt);
                      } catch (_) {}
                    }

                    IconData icon = Icons.notifications;
                    if (type == 'sos') icon = Icons.warning;
                    if (type == 'check_in') icon = Icons.how_to_reg;
                    if (type.contains('driving')) icon = Icons.directions_car;

                    return ListTile(
                      leading: Icon(
                        icon,
                        size: 20,
                        color: ShieldColors.activeTeal,
                      ),
                      title: Text.rich(
                        TextSpan(
                          children: [
                            if (userName.isNotEmpty)
                              TextSpan(
                                text: userName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (userName.isNotEmpty)
                              const TextSpan(text: ' - '),
                            TextSpan(
                              text: title,

                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      subtitle: desc.isNotEmpty
                          ? Text(
                              desc,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            )
                          : null,
                      trailing: Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CircularPulseIndicator extends StatelessWidget {
  const CircularPulseIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 40,
      height: 40,
      child: CircularProgressIndicator(color: ShieldColors.activeTeal),
    );
  }
}

class _NextCheckinCard extends ConsumerStatefulWidget {
  final DateTime nextCheckin;
  final UserProfile? profile;
  final String scheduleId;
  final String assignedUser;
  final String assignedUserId;

  const _NextCheckinCard({
    super.key,
    required this.nextCheckin,
    required this.profile,
    required this.scheduleId,
    required this.assignedUser,
    required this.assignedUserId,
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
                'Monitor initiated an emergency state',
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

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          var value = await _showCheckinDialog();
          print(value);
          print("valuevalue");

          if (value == true) {
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
              bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
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
                    setState(() {
                      isLoad = false;
                    });
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
                      setState(() {
                        isLoad = false;
                      });
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

            await Supabase.instance.client.from('check_ins').insert({
              'family_id': widget.profile?.familyId,
              'user_id': widget.profile?.userId,
              'latitude': lat,
              'longitude': lng,
              'status_message': "Scheduled check-in completed",
            });

            // Also register this as a well_event to ensure it shows up securely on the stream!
            await Supabase.instance.client.from('well_events').insert({
              'family_id': widget.profile?.familyId,
              'user_id': widget.profile?.userId,
              'user_name': widget.profile?.fullName,
              'event_type': 'check_in',
              'title': 'Manual Check-in',
              'description': 'Scheduled check-in completed',
              'latitude': lat,
              'longitude': lng,
              'battery_level': level,
            });
            final schedule = await Supabase.instance.client
                .from('checkin_schedules')
                .select('recurrence')
                .eq('id', widget.scheduleId)
                .single();
            final recurrence = schedule['recurrence'];

            final isRecurring =
                recurrence == 'daily' ||
                recurrence == 'every_other_day' ||
                recurrence == 'weekly' ||
                recurrence == 'monthly';

            DateTime? nextDate;

            if (isRecurring) {
              final fullSchedule = await Supabase.instance.client
                  .from('checkin_schedules')
                  .select()
                  .eq('id', widget.scheduleId)
                  .single();

              nextDate = DateTime.parse(fullSchedule['scheduled_at']);

              switch (recurrence) {
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
              }
            }

            await Supabase.instance.client
                .from('checkin_schedules')
                .update({
                  if (!isRecurring) 'is_completed': true,

                  'completed_at': DateTime.now().toIso8601String(),

                  if (!isRecurring) 'status': 'completed',

                  if (isRecurring) ...{
                    'status': 'pending',
                    'scheduled_at': nextDate?.toIso8601String(),
                    'reminder_sent': false,
                    'reminder_sent_at': null,
                  },
                })
                .eq('id', widget.scheduleId);
            if (!mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Scheduled check-in completed")),
            );
            final safety = ref.invalidate(safetyRepositoryProvider);

            final profile = await ref.read(currentUserProfileProvider.future);
            if (profile == null) throw Exception('No profile');

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
          } else if (value == false) {
            _startSosCountdown();
          }
        }
      });
    }
  }

  Future<bool?> _showCheckinDialog() async {
    final result = await showDialog(
      context: context,
      barrierDismissible: false,
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
        if (widget.profile?.userId == widget.assignedUserId) {
          _checkScheduleTime(widget.nextCheckin);
        }
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

              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(color: Colors.white70, fontSize: 18),
                  children: [
                    TextSpan(
                      text: widget.assignedUser,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    TextSpan(
                      text:
                          "- Next Check-In at ${DateFormat('dd MMM yyyy, hh:mm a').format(widget.nextCheckin)}",
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
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
              if (widget.profile?.userId == widget.assignedUserId)
                SizedBox(height: 10),
              if (widget.profile?.userId == widget.assignedUserId)
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

                      await Supabase.instance.client.from('check_ins').insert({
                        'family_id': widget.profile?.familyId,
                        'user_id': widget.profile?.userId,
                        'latitude': lat,
                        'longitude': lng,
                        'status_message': "Scheduled check-in completed",
                      });

                      // Also register this as a well_event to ensure it shows up securely on the stream!
                      await Supabase.instance.client
                          .from('well_events')
                          .insert({
                            'family_id': widget.profile?.familyId,
                            'user_id': widget.profile?.userId,
                            'user_name': widget.profile?.fullName,
                            'event_type': 'check_in',
                            'title': 'Manual Check-in',
                            'description': 'Scheduled check-in completed',
                            'latitude': lat,
                            'longitude': lng,
                            'battery_level': level,
                          });
                      final schedule = await Supabase.instance.client
                          .from('checkin_schedules')
                          .select('recurrence')
                          .eq('id', widget.scheduleId)
                          .single();
                      final recurrence = schedule['recurrence'];

                      final isRecurring =
                          recurrence == 'daily' ||
                          recurrence == 'every_other_day' ||
                          recurrence == 'weekly' ||
                          recurrence == 'monthly';

                      DateTime? nextDate;

                      if (isRecurring) {
                        final fullSchedule = await Supabase.instance.client
                            .from('checkin_schedules')
                            .select()
                            .eq('id', widget.scheduleId)
                            .single();

                        nextDate = DateTime.parse(fullSchedule['scheduled_at']);

                        switch (recurrence) {
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
                          .update({
                            if (!isRecurring) 'is_completed': true,

                            'completed_at': DateTime.now().toIso8601String(),

                            if (!isRecurring) 'status': 'completed',

                            if (isRecurring) ...{
                              'status': 'pending',
                              'scheduled_at': nextDate?.toIso8601String(),
                              'reminder_sent': false,
                              'reminder_sent_at': null,
                            },
                          })
                          .eq('id', widget.scheduleId);
                      if (!mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Scheduled check-in completed")),
                      );
                      final safety = ref.invalidate(safetyRepositoryProvider);

                      final profile = await ref.read(
                        currentUserProfileProvider.future,
                      );
                      if (profile == null) throw Exception('No profile');

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
              const SizedBox(height: 10),
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
