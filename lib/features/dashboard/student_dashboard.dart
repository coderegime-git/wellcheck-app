import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/safety_repository.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/data/tools_repository.dart';
import 'package:well_check_v3/features/profile/profile_settings_view.dart';
import 'package:well_check_v3/features/messaging/family_chat_screen.dart';
import 'package:well_check_v3/features/dashboard/widgets/command_center_sheet.dart';
import 'package:well_check_v3/features/dashboard/widgets/pending_actions_card.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/data/medication_provider.dart';
import '../../core/notifications/push_notification_service.dart';

class StudentDashboard extends ConsumerStatefulWidget {
  const StudentDashboard({super.key});

  @override
  ConsumerState<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends ConsumerState<StudentDashboard> {
  bool _sosCountdownActive = false;
  int _sosCountdown = 5;
  Timer? _sosTimer;
  Stream<List<Map<String, dynamic>>>? _safeZonesStream;
  Stream<List<Map<String, dynamic>>>? _activeMembersStream;
  bool isLoad = false;
  bool emergencyLoad = false;
  bool isCheckIn = false;

  @override
  void initState() {
    initializeFCM();
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final safetyRepo = ref.invalidate(safetyRepositoryProvider);
  }

  void initializeFCM() async {
    await PushNotificationService.initialize();
  }

  @override
  void dispose() {
    _sosTimer?.cancel();
    super.dispose();
  }

  // void _startSosCountdown() {
  //   if (_sosCountdownActive) {
  //     _sosTimer?.cancel();
  //     setState(() {
  //       _sosCountdownActive = false;
  //       _sosCountdown = 5;
  //     });
  //     return;
  //   }
  //
  //   setState(() {
  //     _sosCountdownActive = true;
  //     _sosCountdown = 5;
  //   });
  //
  //   _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
  //     HapticFeedback.heavyImpact();
  //
  //     if (_sosCountdown <= 1) {
  //       timer.cancel();
  //       try {
  //         final profile = await ref.read(currentUserProfileProvider.future);
  //         if (profile == null) {
  //           debugPrint(
  //             '[SOS] Profile is null — user has no family_members row',
  //           );
  //           if (mounted) {
  //             setState(() {
  //               _sosCountdownActive = false;
  //               _sosCountdown = 5;
  //             });
  //             ScaffoldMessenger.of(context).showSnackBar(
  //               const SnackBar(
  //                 content: Text(
  //                   '⚠️ SOS FAILED: No family profile found. Please re-join a family first.',
  //                 ),
  //                 backgroundColor: Colors.orange,
  //                 duration: Duration(seconds: 5),
  //               ),
  //             );
  //           }
  //           return;
  //         }
  //
  //         await ref
  //             .read(safetyRepositoryProvider)
  //             .triggerSiren(
  //           profile.familyId,
  //           'Minor pressed Emergency SOS (5s countdown completed)',
  //         );
  //
  //         if (mounted) {
  //           setState(() {
  //             _sosCountdownActive = false;
  //             _sosCountdown = 5;
  //           });
  //           ScaffoldMessenger.of(context).showSnackBar(
  //             const SnackBar(
  //               content: Text('🚨 EMERGENCY ALERT SENT!'),
  //               backgroundColor: ShieldColors.urgentRed,
  //               duration: Duration(seconds: 5),
  //             ),
  //           );
  //         }
  //       } catch (e) {
  //         debugPrint('[SOS] triggerSiren failed: $e');
  //         if (mounted) {
  //           setState(() {
  //             _sosCountdownActive = false;
  //             _sosCountdown = 5;
  //           });
  //           ScaffoldMessenger.of(context).showSnackBar(
  //             SnackBar(
  //               content: Text('⚠️ SOS FAILED: $e'),
  //               backgroundColor: Colors.orange,
  //               duration: const Duration(seconds: 5),
  //             ),
  //           );
  //         }
  //       }
  //     } else {
  //       if (mounted) setState(() => _sosCountdown--);
  //     }
  //   });
  // }
  void _startSosCountdown() {
    if (emergencyLoad) return;

    if (_sosCountdownActive) {
      _sosTimer?.cancel();
      setState(() {
        _sosCountdownActive = false;
        _sosCountdown = 5;
      });
      return;
    }

    setState(() {
      emergencyLoad = true;
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
                emergencyLoad = false;

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
                '${profile.fullName}- Student manually initiated an emergency state',
              );

          if (mounted) {
            setState(() {
              emergencyLoad = false;

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
              emergencyLoad = false;

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

    return Scaffold(
      backgroundColor: isLoad || emergencyLoad
          ? Colors.white
          : ShieldColors.activeTeal,
      body: isLoad || emergencyLoad
          ? Center(child: CircularProgressIndicator())
          : GestureDetector(
              onTap: () {
                FocusScope.of(context).unfocus();
              },
              child: SafeArea(
                child: profileAsync.when(
                  data: (profile) {
                    if (profile == null) {
                      return const Center(child: Text('No profile found.'));
                    }

                    final toolsRepo = ref.watch(toolsRepositoryProvider);
                    final safetyRepo = ref.watch(safetyRepositoryProvider);

                    return Column(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 18),
                          margin: EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Image.asset(
                                'assets/logo.png',
                                height: 40,
                                width: 40,
                              ),
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
                              GestureDetector(
                                onTap: () {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (_) => const ProfileSettingsView(),
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
                                  child: profile.avatarUrl != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            26,
                                          ),
                                          child: Image.network(
                                            profile.avatarUrl!,
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
                        SizedBox(height: 6),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 27,
                          ),
                          decoration: BoxDecoration(
                            color: ShieldColors.softMint,

                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(24),
                              topRight: Radius.circular(24),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Hi, ${profile.fullName?.split(' ').first ?? 'there'}!',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: ShieldColors.textBody,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "You're safe & connected",
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            color: ShieldColors.textLabel,
                                          ),
                                    ),
                                  ],
                                ),
                              ),

                              // Profile avatar — taps to open ProfileSettingsView
                            ],
                          ),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18.0,
                            ),

                            decoration: BoxDecoration(
                              color: ShieldColors.softMint,
                            ),
                            child: RefreshIndicator(
                              onRefresh: () async {
                                ref.invalidate(familyMedicationsProvider);
                                ref.invalidate(safetyRepositoryProvider);
                              },
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header
                                    const SizedBox(height: 10),

                                    const PendingActionsCard(),
                                    const SizedBox(height: 10),

                                    medicationsAsync.when(
                                      data: (medications) {
                                        final activeMeds = medications
                                            .where(
                                              (m) =>
                                                  m.isActive &&
                                                  m.assignedTo ==
                                                      profile.userId,
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
                                                      color: ShieldColors
                                                          .textLabel,
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                          doseTime = doseTime
                                                              .add(
                                                                const Duration(
                                                                  days: 1,
                                                                ),
                                                              );
                                                        }
                                                      }
                                                      // EVERY OTHER DAY
                                                      else if (frequency
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
                                                            doseTime.isBefore(
                                                              now,
                                                            )) {
                                                          doseTime = doseTime
                                                              .add(
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
                                                      else if (frequency
                                                          .contains('weekly')) {
                                                        doseTime = DateTime(
                                                          now.year,
                                                          now.month,
                                                          now.day,
                                                          hour,
                                                          minute,
                                                        );

                                                        while (doseTime
                                                                    .weekday !=
                                                                startDate
                                                                    .weekday ||
                                                            doseTime.isBefore(
                                                              now,
                                                            )) {
                                                          doseTime = doseTime
                                                              .add(
                                                                const Duration(
                                                                  days: 1,
                                                                ),
                                                              );
                                                        }
                                                      }
                                                      // MONTHLY
                                                      else if (frequency
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
                                                      else if (frequency
                                                          .contains(
                                                            'as needed',
                                                          )) {
                                                        continue;
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
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                    border: Border.all(
                                                      color: statusColor
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
                                    const SizedBox(height: 24),
                                    StreamBuilder<List<Map<String, dynamic>>>(
                                      stream: safetyRepo
                                          .streamMyCheckinSchedules(
                                            profile.userId,
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
                                          profile: profile,
                                          scheduleId: scheduleId,
                                        );
                                      },
                                    ),
                                    // Safe Zones Status
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
                                      stream: toolsRepo.streamSafeZones(
                                        profile.familyId,
                                      ),
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState ==
                                            ConnectionState.waiting) {
                                          return const Center(
                                            child: CircularProgressIndicator(),
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
                                                    ? ShieldColors.safeZoneGreen
                                                          .withValues(
                                                            alpha: 0.1,
                                                          )
                                                    : Colors.white,
                                                borderRadius:
                                                    ShieldDesign.roundedTwelve,
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
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        ShieldColors.textBody,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  'Radius: ${zone['radius_meters']}m',
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
                                    // Action Buttons
                                    SizedBox(
                                      width: double.infinity,
                                      height: 56,
                                      child: isCheckIn
                                          ? Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            )
                                          : ElevatedButton.icon(
                                              onPressed: () async {
                                                if (isCheckIn) return;
                                                setState(() {
                                                  isCheckIn = true;
                                                });
                                                // Fetch real GPS
                                                double lat = 0.0;
                                                double lng = 0.0;
                                                bool gpsSuccess = false;
                                                try {
                                                  LocationPermission perm =
                                                      await Geolocator.checkPermission();
                                                  print(perm);
                                                  if (perm ==
                                                      LocationPermission
                                                          .denied) {
                                                    perm =
                                                        await Geolocator.requestPermission();
                                                    print(perm);
                                                    print("adds");
                                                  } else if (perm ==
                                                      LocationPermission
                                                          .deniedForever) {
                                                    print(
                                                      "openLocationSettings",
                                                    );

                                                    await Geolocator.openLocationSettings();
                                                  }
                                                  if (perm !=
                                                          LocationPermission
                                                              .denied &&
                                                      perm !=
                                                          LocationPermission
                                                              .deniedForever) {
                                                    final pos =
                                                        await Geolocator.getCurrentPosition(
                                                          desiredAccuracy:
                                                              LocationAccuracy
                                                                  .medium,
                                                          timeLimit:
                                                              const Duration(
                                                                seconds: 8,
                                                              ),
                                                        );
                                                    lat = pos.latitude;
                                                    lng = pos.longitude;
                                                    gpsSuccess = true;
                                                  }
                                                } catch (e) {
                                                  setState(() {
                                                    isCheckIn = false;
                                                  });
                                                  print("fdfdf");
                                                  // fallback to last known if timeout
                                                  try {
                                                    final lastPos =
                                                        await Geolocator.getLastKnownPosition();
                                                    if (lastPos != null) {
                                                      lat = lastPos.latitude;
                                                      lng = lastPos.longitude;
                                                      gpsSuccess = true;
                                                    }
                                                  } catch (_) {
                                                    setState(() {
                                                      isCheckIn = false;
                                                    });
                                                  }
                                                }
                                                int level =
                                                    100; // Safe default for simulators and aggressive background iOS policies
                                                try {
                                                  final battery = Battery();
                                                  level = await battery
                                                      .batteryLevel;
                                                } catch (e) {
                                                  setState(() {
                                                    isCheckIn = false;
                                                  });
                                                  debugPrint(
                                                    'Battery info not available over isolate, using default: $e',
                                                  );
                                                }

                                                await safetyRepo.submitPulse(
                                                  familyId: profile.familyId,
                                                  latitude: lat,
                                                  longitude: lng,
                                                  batteryLevel: level,
                                                  //userName: profile.fullName??"",
                                                  type: 'check_in',
                                                );
                                                setState(() {
                                                  isCheckIn = false;
                                                });
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        gpsSuccess
                                                            ? 'Checked in successfully!'
                                                            : 'Checked in (GPS unavailable)',
                                                      ),
                                                      backgroundColor:
                                                          gpsSuccess
                                                          ? ShieldColors
                                                                .safeZoneGreen
                                                          : Colors.orange,
                                                    ),
                                                  );
                                                }
                                              },
                                              icon: const Icon(
                                                Icons.check_circle_outline,
                                                size: 24,
                                              ),
                                              label: const Text(
                                                'Check In',
                                                style: TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    ShieldColors.activeTeal,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: ShieldDesign
                                                      .roundedTwelve,
                                                ),
                                                elevation: 4,
                                              ),
                                            ),
                                    ),
                                    const SizedBox(height: 12),
                                    // Message Family — now opens in-app chat
                                    SizedBox(
                                      width: double.infinity,
                                      height: 56,
                                      child: ElevatedButton.icon(
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
                                        icon: const Icon(
                                          Icons.chat_bubble_outline,
                                          size: 24,
                                        ),
                                        label: const Text(
                                          'Message Family',
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor:
                                              ShieldColors.textBody,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                ShieldDesign.roundedTwelve,
                                          ),
                                          elevation: 2,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 32),

                                    // Family Status — BUG FIX: show name instead of role
                                    Text(
                                      'FAMILY STATUS',
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
                                      stream: safetyRepo.streamActiveMembers(
                                        profile.familyId,
                                      ),
                                      builder: (context, memberSnapshot) {
                                        if (memberSnapshot.connectionState ==
                                            ConnectionState.waiting) {
                                          return const Center(
                                            child: CircularProgressIndicator(),
                                          );
                                        }
                                        final members =
                                            memberSnapshot.data ?? [];
                                        final parents = members
                                            .where(
                                              (m) =>
                                                  m['role'] == 'leader' ||
                                                  m['role'] == 'monitor',
                                            )
                                            .toList();

                                        if (parents.isEmpty) {
                                          return const Text(
                                            'No parents online.',
                                          );
                                        }

                                        return Column(
                                          children: parents
                                              .map(
                                                (member) => Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 12,
                                                      ),
                                                  child: ParentLocationRow(
                                                    // FIX: Display name, not role
                                                    name:
                                                        member['full_name'] ??
                                                        'Family Member',
                                                    location:
                                                        'Active on Shield',
                                                    // Assuming 'memberLoc' was intended to be this static string or derived elsewhere
                                                    isOnline: true,
                                                    // Assuming 'isOnline' was intended to be this static boolean or derived elsewhere
                                                    avatarUrl:
                                                        member['avatar_url']
                                                            as String?,
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 100),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, st) => Center(child: Text('Error: $e')),
                ),
              ),
            ),
      // Elder-portal style anchored bottom bar
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
                  flex: 3,
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
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _sosCountdownActive
                                  ? 'CANCEL ($_sosCountdown)'
                                  : 'EMERGENCY',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
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
                // MENU button (command center)
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 60,
                    child: ElevatedButton(
                      onPressed: () {
                        print("dss");
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => CommandCenterSheet(),
                        );
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
                          Icon(Icons.grid_view_rounded, size: 20),
                          SizedBox(width: 2),
                          Text(
                            'MENU',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
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

class ParentLocationRow extends StatelessWidget {
  final String name;
  final String location;
  final bool isOnline;
  final String? avatarUrl;

  const ParentLocationRow({
    super.key,
    required this.name,
    required this.location,
    required this.isOnline,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Colors.grey.shade200,
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
          child: avatarUrl == null
              ? Icon(Icons.person, color: Colors.grey.shade400)
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ShieldColors.textBody,
                ),
              ),
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    location,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: isOnline ? const Color(0xFF00E676) : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
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

  // void _startSosCountdown() {
  //   if (_sosCountdownActive) {
  //     _sosTimer?.cancel();
  //     setState(() {
  //       _sosCountdownActive = false;
  //       _sosCountdown = 5;
  //     });
  //     return;
  //   }
  //
  //   setState(() {
  //     _sosCountdownActive = true;
  //     _sosCountdown = 5;
  //   });
  //
  //   _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
  //     HapticFeedback.heavyImpact();
  //
  //     if (_sosCountdown <= 1) {
  //       timer.cancel();
  //       try {
  //         final profile = await ref.read(currentUserProfileProvider.future);
  //         if (profile == null) {
  //           debugPrint(
  //             '[SOS] Profile is null — user has no family_members row',
  //           );
  //           if (mounted) {
  //             setState(() {
  //               _sosCountdownActive = false;
  //               _sosCountdown = 5;
  //             });
  //             ScaffoldMessenger.of(context).showSnackBar(
  //               const SnackBar(
  //                 content: Text(
  //                   '⚠️ SOS FAILED: No family profile found. Please re-join a family first.',
  //                 ),
  //                 backgroundColor: Colors.orange,
  //                 duration: Duration(seconds: 5),
  //               ),
  //             );
  //           }
  //           return;
  //         }
  //
  //         await ref
  //             .read(safetyRepositoryProvider)
  //             .triggerSiren(
  //               profile.familyId,
  //               'Monitor initiated an emergency state',
  //             );
  //
  //         if (mounted) {
  //           setState(() {
  //             _sosCountdownActive = false;
  //             _sosCountdown = 5;
  //           });
  //           ScaffoldMessenger.of(context).showSnackBar(
  //             const SnackBar(
  //               content: Text('🚨 EMERGENCY ALERT SENT!'),
  //               backgroundColor: ShieldColors.urgentRed,
  //               duration: Duration(seconds: 5),
  //             ),
  //           );
  //           final safety = ref.invalidate(safetyRepositoryProvider);
  //         }
  //       } catch (e) {
  //         debugPrint('[SOS] triggerSiren failed: $e');
  //         if (mounted) {
  //           setState(() {
  //             _sosCountdownActive = false;
  //             _sosCountdown = 5;
  //           });
  //           ScaffoldMessenger.of(context).showSnackBar(
  //             SnackBar(
  //               content: Text('⚠️ SOS FAILED: $e'),
  //               backgroundColor: Colors.orange,
  //               duration: const Duration(seconds: 5),
  //             ),
  //           );
  //         }
  //       }
  //     } else {
  //       if (mounted) setState(() => _sosCountdown--);
  //     }
  //   });
  // }
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
                '${profile.fullName}- Student manually initiated an emergency state',
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
              'family_id': widget.profile.familyId,
              'user_id': widget.profile.userId,
              'latitude': lat,
              'longitude': lng,
              'status_message': "Scheduled check-in completed",
            });

            // Also register this as a well_event to ensure it shows up securely on the stream!
            await Supabase.instance.client.from('well_events').insert({
              'family_id': widget.profile.familyId,
              'user_id': widget.profile.userId,
              'user_name': widget.profile.fullName,
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

                    await Supabase.instance.client.from('check_ins').insert({
                      'family_id': widget.profile.familyId,
                      'user_id': widget.profile.userId,
                      'latitude': lat,
                      'longitude': lng,
                      'status_message': "Scheduled check-in completed",
                    });

                    // Also register this as a well_event to ensure it shows up securely on the stream!
                    await Supabase.instance.client.from('well_events').insert({
                      'family_id': widget.profile.familyId,
                      'user_id': widget.profile.userId,
                      'user_name': widget.profile.fullName,
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

//
// class StudentDashboard extends ConsumerStatefulWidget {
//   const StudentDashboard({super.key});
//
//   @override
//   ConsumerState<StudentDashboard> createState() => _StudentDashboardState();
// }
//
// class _StudentDashboardState extends ConsumerState<StudentDashboard> {
//   bool _sosCountdownActive = false;
//   int _sosCountdown = 5;
//   Timer? _sosTimer;
//   Stream<List<Map<String, dynamic>>>? _safeZonesStream;
//   Stream<List<Map<String, dynamic>>>? _activeMembersStream;
//   StreamController<List<Map<String, dynamic>>>? _membersController;
//   StreamController<List<Map<String, dynamic>>>? _zonesController;
//   String? _lastFamilyId;
//   StreamSubscription? _membersSub;
//   StreamSubscription? _zonesSub;
//
//   @override
//   void initState() {
//     initializeFCM();
//     super.initState();
//   }
//
//   void _initStreams(String familyId) {
//     if (_lastFamilyId == familyId) return;
//     _lastFamilyId = familyId;
//
//     // Cancel old subscriptions
//     _membersSub?.cancel();
//     _zonesSub?.cancel();
//     _membersController?.close();
//     _zonesController?.close();
//
//     // Create fresh broadcast controllers
//     _membersController =
//     StreamController<List<Map<String, dynamic>>>.broadcast();
//     _zonesController = StreamController<List<Map<String, dynamic>>>.broadcast();
//
//     final toolsRepo = ref.read(toolsRepositoryProvider);
//     final safetyRepo = ref.read(safetyRepositoryProvider);
//
//     // Pipe Supabase stream into our controller
//     _zonesSub = toolsRepo.streamSafeZones(familyId).listen((data) {
//       if (!(_zonesController?.isClosed ?? true)) {
//         _zonesController?.add(data);
//       }
//     }, onError: (e) => debugPrint('[Zones] Stream error: $e'));
//
//     _membersSub = safetyRepo.streamActiveMembers(familyId).listen((data) {
//       if (!(_membersController?.isClosed ?? true)) {
//         _membersController?.add(data);
//       }
//     }, onError: (e) => debugPrint('[Members] Stream error: $e'));
//   }
// @override
//   // void didChangeDependencies() {
//   //   super.didChangeDependencies();
//   //   if (_safeZonesStream == null) {
//   //     final toolsRepo = ref.read(toolsRepositoryProvider);
//   //     final safetyRepo = ref.read(safetyRepositoryProvider);
//   //     final profile = ref.read(currentUserProfileProvider).value;
//   //     if (profile != null) {
//   //       _safeZonesStream = toolsRepo
//   //           .streamSafeZones(profile.familyId)
//   //           .asBroadcastStream();
//   //       _activeMembersStream = safetyRepo
//   //           .streamActiveMembers(profile.familyId)
//   //           .asBroadcastStream();
//   //     }
//   //   }
//   // }
//
//   void initializeFCM() async {
//     await PushNotificationService.initialize();
//     // WidgetsBinding.instance.addPostFrameCallback((_) {
//     //   if (_safeZonesStream == null) {
//     //     final toolsRepo = ref.read(toolsRepositoryProvider);
//     //     final safetyRepo = ref.read(safetyRepositoryProvider);
//     //     final profile = ref.read(currentUserProfileProvider).value;
//     //     if (profile != null) {
//     //       _safeZonesStream = toolsRepo
//     //           .streamSafeZones(profile.familyId)
//     //           .asBroadcastStream();
//     //       _activeMembersStream = safetyRepo
//     //           .streamActiveMembers(profile.familyId)
//     //           .asBroadcastStream();
//     //     }
//     //   }
//     // });
//   }
//
//   @override
//   void dispose() {
//     _sosTimer?.cancel();
//     _membersSub?.cancel();
//     _zonesSub?.cancel();
//     _membersController?.close();
//     _zonesController?.close();
//     super.dispose();
//   }
//
//   void _startSosCountdown() {
//     if (_sosCountdownActive) {
//       _sosTimer?.cancel();
//       setState(() {
//         _sosCountdownActive = false;
//         _sosCountdown = 5;
//       });
//       return;
//     }
//
//     setState(() {
//       _sosCountdownActive = true;
//       _sosCountdown = 5;
//     });
//
//     _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
//       HapticFeedback.heavyImpact();
//
//       if (_sosCountdown <= 1) {
//         timer.cancel();
//         try {
//           final profile = await ref.read(currentUserProfileProvider.future);
//           if (profile == null) {
//             debugPrint(
//               '[SOS] Profile is null — user has no family_members row',
//             );
//             if (mounted) {
//               setState(() {
//                 _sosCountdownActive = false;
//                 _sosCountdown = 5;
//               });
//               ScaffoldMessenger.of(context).showSnackBar(
//                 const SnackBar(
//                   content: Text(
//                     '⚠️ SOS FAILED: No family profile found. Please re-join a family first.',
//                   ),
//                   backgroundColor: Colors.orange,
//                   duration: Duration(seconds: 5),
//                 ),
//               );
//             }
//             return;
//           }
//
//           await ref
//               .read(safetyRepositoryProvider)
//               .triggerSiren(
//             profile.familyId,
//             'Minor pressed Emergency SOS (5s countdown completed)',
//           );
//
//           if (mounted) {
//             setState(() {
//               _sosCountdownActive = false;
//               _sosCountdown = 5;
//             });
//             ScaffoldMessenger.of(context).showSnackBar(
//               const SnackBar(
//                 content: Text('🚨 EMERGENCY ALERT SENT!'),
//                 backgroundColor: ShieldColors.urgentRed,
//                 duration: Duration(seconds: 5),
//               ),
//             );
//           }
//         } catch (e) {
//           debugPrint('[SOS] triggerSiren failed: $e');
//           if (mounted) {
//             setState(() {
//               _sosCountdownActive = false;
//               _sosCountdown = 5;
//             });
//             ScaffoldMessenger.of(context).showSnackBar(
//               SnackBar(
//                 content: Text('⚠️ SOS FAILED: $e'),
//                 backgroundColor: Colors.orange,
//                 duration: const Duration(seconds: 5),
//               ),
//             );
//           }
//         }
//       } else {
//         if (mounted) setState(() => _sosCountdown--);
//       }
//     });
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final profileAsync = ref.watch(currentUserProfileProvider);
//     final medicationsAsync = ref.watch(familyMedicationsProvider);
//
//     return Scaffold(
//       backgroundColor: ShieldColors.activeTeal,
//       body: SafeArea(
//         child: profileAsync.when(
//           data: (profile) {
//             if (profile == null) {
//               return const Center(child: Text('No profile found.'));
//             }
//             _initStreams(profile.familyId);
//             // final toolsRepo = ref.watch(toolsRepositoryProvider);
//             // final safetyRepo = ref.watch(safetyRepositoryProvider);
//
//             return Column(
//               children: [
//                 Container(
//                   padding: EdgeInsets.symmetric(horizontal: 18),
//                   margin: EdgeInsets.symmetric(vertical: 10),
//                   child: Row(
//                     children: [
//                       Image.asset('assets/logo.png', height: 40, width: 40),
//                       SizedBox(width: 6),
//                       Text(
//                         "Well-Check",
//                         style: Theme.of(context).textTheme.headlineSmall
//                             ?.copyWith(
//                           color: ShieldColors.backgroundWhite,
//                           fontWeight: FontWeight.bold,
//                           fontSize: 16,
//                         ),
//                       ),
//                       Spacer(),
//                       GestureDetector(
//                         onTap: () {
//                           showModalBottomSheet(
//                             context: context,
//                             isScrollControlled: true,
//                             backgroundColor: Colors.transparent,
//                             builder: (_) => const ProfileSettingsView(),
//                           );
//                         },
//                         child: Container(
//                           width: 52,
//                           height: 52,
//                           decoration: BoxDecoration(
//                             shape: BoxShape.circle,
//                             color: Colors.grey.shade300,
//                             border: Border.all(color: Colors.white, width: 2),
//                           ),
//                           child: profile.avatarUrl != null
//                               ? ClipRRect(
//                             borderRadius: BorderRadius.circular(26),
//                             child: Image.network(
//                               profile.avatarUrl!,
//                               fit: BoxFit.cover,
//                             ),
//                           )
//                               : const Icon(Icons.person, color: Colors.grey),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//                 SizedBox(height: 6),
//                 Container(
//                   padding: EdgeInsets.symmetric(horizontal: 18, vertical: 27),
//                   decoration: BoxDecoration(
//                     color: ShieldColors.softMint,
//
//                     borderRadius: BorderRadius.only(
//                       topLeft: Radius.circular(24),
//                       topRight: Radius.circular(24),
//                     ),
//                   ),
//                   child: Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                     children: [
//                       Expanded(
//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Text(
//                               'Hi, ${profile.fullName?.split(' ').first ?? 'there'}!',
//                               style: Theme.of(context).textTheme.headlineMedium
//                                   ?.copyWith(
//                                 fontWeight: FontWeight.bold,
//                                 color: ShieldColors.textBody,
//                               ),
//                               maxLines: 1,
//                               overflow: TextOverflow.ellipsis,
//                             ),
//                             const SizedBox(height: 4),
//                             Text(
//                               "You're safe & connected",
//                               style: Theme.of(context).textTheme.bodyLarge
//                                   ?.copyWith(color: ShieldColors.textLabel),
//                             ),
//                           ],
//                         ),
//                       ),
//
//                       // Profile avatar — taps to open ProfileSettingsView
//                     ],
//                   ),
//                 ),
//                 Expanded(
//                   child: Container(
//                     decoration: BoxDecoration(color: ShieldColors.softMint),
//                     child: ListView(
//                       padding: const EdgeInsets.symmetric(horizontal: 18.0),
//                       children: [
//                         // Header
//                         const SizedBox(height: 10),
//
//                         const PendingActionsCard(),
//                         const SizedBox(height: 24),
//
//                         medicationsAsync.when(
//                           data: (medications) {
//                             final activeMeds = medications
//                                 .where(
//                                   (m) =>
//                               m.isActive &&
//                                   m.assignedTo == profile.userId,
//                             )
//                                 .toList();
//
//                             if (activeMeds.isEmpty) {
//                               return const SizedBox.shrink();
//                             }
//
//                             return Container(
//                               margin: const EdgeInsets.only(bottom: 18),
//                               padding: const EdgeInsets.all(16),
//                               decoration: BoxDecoration(
//                                 color: Colors.white,
//                                 borderRadius: BorderRadius.circular(20),
//                                 boxShadow: [
//                                   BoxShadow(
//                                     color: Colors.black.withValues(alpha: 0.04),
//                                     blurRadius: 10,
//                                     offset: const Offset(0, 4),
//                                   ),
//                                 ],
//                               ),
//                               child: Column(
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 children: [
//                                   Text(
//                                     'MEDICATION MONITOR',
//                                     style: Theme.of(context)
//                                         .textTheme
//                                         .labelMedium
//                                         ?.copyWith(
//                                       color: ShieldColors.textLabel,
//                                       fontWeight: FontWeight.bold,
//                                       letterSpacing: 1.2,
//                                     ),
//                                   ),
//
//                                   const SizedBox(height: 14),
//
//                                   ...activeMeds.map((med) {
//                                     // final nextDose = med.nextDoseToday;
//                                     DateTime? nextDose;
//
//                                     if (med.scheduleTimes.isNotEmpty) {
//                                       final now = DateTime.now();
//
//                                       final upcomingDoses = <DateTime>[];
//
//                                       final startDate = med.startDate ?? now;
//
//                                       for (final time in med.scheduleTimes) {
//                                         try {
//                                           final parts = time.split(':');
//
//                                           final hour = int.parse(parts[0]);
//                                           final minute = int.parse(parts[1]);
//
//                                           DateTime doseTime = DateTime(
//                                             now.year,
//                                             now.month,
//                                             now.day,
//                                             hour,
//                                             minute,
//                                           );
//
//                                           final frequency = med.frequency
//                                               .toLowerCase();
//
//                                           // DAILY
//                                           if (frequency.contains('daily')) {
//                                             if (doseTime.isBefore(now)) {
//                                               doseTime = doseTime.add(
//                                                 const Duration(days: 1),
//                                               );
//                                             }
//                                           }
//                                           // EVERY OTHER DAY
//                                           else if (frequency.contains(
//                                             'every other',
//                                           )) {
//                                             final daysSinceStart = now
//                                                 .difference(startDate)
//                                                 .inDays;
//
//                                             final shouldTakeToday =
//                                                 daysSinceStart % 2 == 0;
//
//                                             if (!shouldTakeToday ||
//                                                 doseTime.isBefore(now)) {
//                                               doseTime = doseTime.add(
//                                                 const Duration(days: 1),
//                                               );
//
//                                               while (doseTime
//                                                   .difference(startDate)
//                                                   .inDays %
//                                                   2 !=
//                                                   0) {
//                                                 doseTime = doseTime.add(
//                                                   const Duration(days: 1),
//                                                 );
//                                               }
//                                             }
//                                           }
//                                           // WEEKLY
//                                           else if (frequency.contains(
//                                             'weekly',
//                                           )) {
//                                             doseTime = DateTime(
//                                               now.year,
//                                               now.month,
//                                               now.day,
//                                               hour,
//                                               minute,
//                                             );
//
//                                             while (doseTime.weekday !=
//                                                 startDate.weekday ||
//                                                 doseTime.isBefore(now)) {
//                                               doseTime = doseTime.add(
//                                                 const Duration(days: 1),
//                                               );
//                                             }
//                                           }
//                                           // MONTHLY
//                                           else if (frequency.contains(
//                                             'monthly',
//                                           )) {
//                                             doseTime = DateTime(
//                                               now.year,
//                                               now.month,
//                                               startDate.day,
//                                               hour,
//                                               minute,
//                                             );
//
//                                             if (doseTime.isBefore(now)) {
//                                               doseTime = DateTime(
//                                                 now.year,
//                                                 now.month + 1,
//                                                 startDate.day,
//                                                 hour,
//                                                 minute,
//                                               );
//                                             }
//                                           }
//                                           // AS NEEDED
//                                           else if (frequency.contains(
//                                             'as needed',
//                                           )) {
//                                             continue;
//                                           }
//
//                                           upcomingDoses.add(doseTime);
//                                         } catch (e) {
//                                           debugPrint("Dose parse error: $e");
//                                         }
//                                       }
//
//                                       upcomingDoses.sort();
//
//                                       if (upcomingDoses.isNotEmpty) {
//                                         nextDose = upcomingDoses.first;
//                                       }
//                                     }
//                                     String countdownText = 'No upcoming dose';
//                                     Color statusColor = Colors.grey;
//
//                                     Duration? diff;
//
//                                     if (nextDose != null) {
//                                       diff = nextDose.difference(
//                                         DateTime.now(),
//                                       );
//                                     }
//                                     countdownText =
//                                     '${diff?.inHours}h ${diff?.inMinutes.remainder(60)}m ${diff?.inSeconds.remainder(60)}s';
//                                     return Container(
//                                       margin: const EdgeInsets.only(bottom: 12),
//                                       padding: const EdgeInsets.all(14),
//                                       decoration: BoxDecoration(
//                                         color: Colors.grey.shade50,
//                                         borderRadius: BorderRadius.circular(16),
//                                         border: Border.all(
//                                           color: statusColor.withValues(
//                                             alpha: 0.2,
//                                           ),
//                                         ),
//                                       ),
//                                       child: Row(
//                                         mainAxisAlignment:
//                                         MainAxisAlignment.spaceBetween,
//                                         children: [
//                                           Container(
//                                             // padding: const EdgeInsets.all(10),
//                                             decoration: BoxDecoration(
//                                               color: statusColor.withValues(
//                                                 alpha: 0.12,
//                                               ),
//                                               shape: BoxShape.circle,
//                                             ),
//                                             child: Icon(
//                                               Icons.add_box,
//                                               color: Colors.purple,
//                                               size: 28,
//                                             ),
//                                           ),
//
//                                           const SizedBox(width: 12),
//
//                                           Expanded(
//                                             child: Row(
//                                               children: [
//                                                 Expanded(
//                                                   child: Column(
//                                                     crossAxisAlignment:
//                                                     CrossAxisAlignment
//                                                         .start,
//                                                     children: [
//                                                       Text(
//                                                         med.medicationName,
//                                                         style: const TextStyle(
//                                                           fontWeight:
//                                                           FontWeight.bold,
//                                                           fontSize: 15,
//                                                         ),
//                                                       ),
//
//                                                       const SizedBox(height: 4),
//
//                                                       Text(
//                                                         '${med.dosage} • ${med.scheduleSummary}',
//                                                         style: TextStyle(
//                                                           color: Colors
//                                                               .grey
//                                                               .shade700,
//                                                           fontSize: 12,
//                                                         ),
//                                                       ),
//
//                                                       const SizedBox(height: 6),
//
//                                                       // if (nextDose !=
//                                                       //     null) ...[
//                                                       //   const SizedBox(
//                                                       //     height: 4,
//                                                       //   ),
//                                                       //
//                                                       //   Text(
//                                                       //     'At ${DateFormat.jm().format(nextDose)}',
//                                                       //     style: TextStyle(
//                                                       //       color: Colors
//                                                       //           .grey
//                                                       //           .shade600,
//                                                       //       fontSize: 11,
//                                                       //     ),
//                                                       //   ),
//                                                       // ],
//                                                     ],
//                                                   ),
//                                                 ),
//                                                 Expanded(
//                                                   child: Column(
//                                                     crossAxisAlignment:
//                                                     CrossAxisAlignment.end,
//                                                     mainAxisAlignment:
//                                                     MainAxisAlignment.end,
//                                                     children: [
//                                                       Row(
//                                                         mainAxisAlignment:
//                                                         MainAxisAlignment
//                                                             .end,
//                                                         children: [
//                                                           if (nextDose != null)
//                                                             TweenAnimationBuilder<
//                                                                 double
//                                                             >(
//                                                               tween: Tween<double>(
//                                                                 begin: nextDose!
//                                                                     .difference(
//                                                                   DateTime.now(),
//                                                                 )
//                                                                     .inSeconds
//                                                                     .toDouble(),
//                                                                 end: 0,
//                                                               ),
//                                                               duration: nextDose!
//                                                                   .difference(
//                                                                 DateTime.now(),
//                                                               ),
//                                                               builder:
//                                                                   (
//                                                                   context,
//                                                                   value,
//                                                                   child,
//                                                                   ) {
//                                                                 final diff =
//                                                                 Duration(
//                                                                   seconds:
//                                                                   value.toInt(),
//                                                                 );
//
//                                                                 if (diff.isNegative ||
//                                                                     diff.inSeconds <=
//                                                                         0) {
//                                                                   return const Text(
//                                                                     "Time Reached",
//                                                                     style: TextStyle(
//                                                                       color:
//                                                                       Colors.red,
//                                                                       fontWeight:
//                                                                       FontWeight.bold,
//                                                                     ),
//                                                                   );
//                                                                 }
//
//                                                                 final hours =
//                                                                     diff.inHours;
//                                                                 final mins = diff
//                                                                     .inMinutes
//                                                                     .remainder(
//                                                                   60,
//                                                                 );
//                                                                 final secs = diff
//                                                                     .inSeconds
//                                                                     .remainder(
//                                                                   60,
//                                                                 );
//
//                                                                 final text =
//                                                                     '${hours.toString().padLeft(2, '0')}h '
//                                                                     '${mins.toString().padLeft(2, '0')}m '
//                                                                     '${secs.toString().padLeft(2, '0')}s';
//
//                                                                 return Text(
//                                                                   text,
//                                                                   style: TextStyle(
//                                                                     color: ShieldColors
//                                                                         .activeTeal,
//                                                                     fontWeight:
//                                                                     FontWeight.w600,
//                                                                     fontSize:
//                                                                     12,
//                                                                   ),
//                                                                 );
//                                                               },
//                                                             ),
//                                                         ],
//                                                       ),
//                                                       Text(
//                                                         "Until Next Dose",
//                                                         style: TextStyle(
//                                                           fontSize: 12,
//                                                           fontWeight:
//                                                           FontWeight.bold,
//                                                           color: ShieldColors
//                                                               .activeTeal,
//                                                         ),
//                                                       ),
//                                                     ],
//                                                   ),
//                                                 ),
//                                               ],
//                                             ),
//                                           ),
//                                         ],
//                                       ),
//                                     );
//                                   }),
//                                 ],
//                               ),
//                             );
//                           },
//                           loading: () => const Center(
//                             child: Padding(
//                               padding: EdgeInsets.all(20),
//                               child: CircularProgressIndicator(),
//                             ),
//                           ),
//                           error: (e, st) => const SizedBox.shrink(),
//                         ),
//                         const SizedBox(height: 24),
//
//                         // Safe Zones Status
//                         Text(
//                           'YOUR SAFE ZONES',
//                           style: Theme.of(context).textTheme.labelMedium
//                               ?.copyWith(
//                             fontWeight: FontWeight.bold,
//                             letterSpacing: 1.2,
//                           ),
//                         ),
//                         const SizedBox(height: 16),
//                         StreamBuilder<List<Map<String, dynamic>>>(
//                           stream: _zonesController?.stream,
//                           builder: (context, snapshot) {
//                             if (snapshot.connectionState ==
//                                 ConnectionState.waiting) {
//                               return const Center(
//                                 child: CircularProgressIndicator(),
//                               );
//                             }
//                             final zones = snapshot.data ?? [];
//
//                             if (zones.isEmpty) {
//                               return Container(
//                                 height: 120,
//                                 alignment: Alignment.center,
//                                 decoration: BoxDecoration(
//                                   color: Colors.grey.shade200,
//                                   borderRadius: ShieldDesign.roundedTwelve,
//                                 ),
//                                 child: const Text('No Safe Zones Configured'),
//                               );
//                             }
//
//                             return Column(
//                               children: zones.map((zone) {
//                                 bool isInside =
//                                     zone['name']
//                                         .toString()
//                                         .toLowerCase()
//                                         .contains('school') ||
//                                         zone['name']
//                                             .toString()
//                                             .toLowerCase()
//                                             .contains('home');
//
//                                 return Container(
//                                   margin: const EdgeInsets.only(bottom: 12),
//                                   decoration: BoxDecoration(
//                                     color: isInside
//                                         ? ShieldColors.safeZoneGreen.withValues(
//                                       alpha: 0.1,
//                                     )
//                                         : Colors.white,
//                                     borderRadius: ShieldDesign.roundedTwelve,
//                                     border: Border.all(
//                                       color: isInside
//                                           ? ShieldColors.safeZoneGreen
//                                           : Colors.grey.shade300,
//                                     ),
//                                   ),
//                                   child: ListTile(
//                                     leading: Icon(
//                                       Icons.location_on,
//                                       color: isInside
//                                           ? ShieldColors.safeZoneGreen
//                                           : Colors.grey,
//                                     ),
//                                     title: Text(
//                                       zone['name'],
//                                       style: const TextStyle(
//                                         fontWeight: FontWeight.bold,
//                                         color: ShieldColors.textBody,
//                                       ),
//                                     ),
//                                     subtitle: Text(
//                                       'Radius: ${zone['radius_meters']}m',
//                                     ),
//                                     trailing: isInside
//                                         ? const Chip(
//                                       label: Text('ACTIVE'),
//                                       backgroundColor:
//                                       ShieldColors.safeZoneGreen,
//                                       labelStyle: TextStyle(
//                                         color: Colors.white,
//                                         fontSize: 10,
//                                       ),
//                                     )
//                                         : const Text(
//                                       'Away',
//                                       style: TextStyle(
//                                         color: Colors.grey,
//                                       ),
//                                     ),
//                                   ),
//                                 );
//                               }).toList(),
//                             );
//                           },
//                         ),
//                         const SizedBox(height: 24),
//
//                         // Action Buttons
//                         SizedBox(
//                           width: double.infinity,
//                           height: 56,
//                           child: ElevatedButton.icon(
//                             onPressed: () async {
//                               // Fetch real GPS
//                               double lat = 0.0;
//                               double lng = 0.0;
//                               bool gpsSuccess = false;
//                               try {
//                                 LocationPermission perm =
//                                 await Geolocator.checkPermission();
//                                 print(perm);
//                                 if (perm == LocationPermission.denied) {
//                                   perm = await Geolocator.requestPermission();
//                                   print(perm);
//                                   print("adds");
//                                 } else if (perm ==
//                                     LocationPermission.deniedForever) {
//                                   print("openLocationSettings");
//
//                                   await Geolocator.openLocationSettings();
//                                 }
//                                 if (perm != LocationPermission.denied &&
//                                     perm != LocationPermission.deniedForever) {
//                                   final pos =
//                                   await Geolocator.getCurrentPosition(
//                                     desiredAccuracy:
//                                     LocationAccuracy.medium,
//                                     timeLimit: const Duration(seconds: 8),
//                                   );
//                                   lat = pos.latitude;
//                                   lng = pos.longitude;
//                                   gpsSuccess = true;
//                                 }
//                               } catch (e) {
//                                 print("fdfdf");
//                                 // fallback to last known if timeout
//                                 try {
//                                   final lastPos =
//                                   await Geolocator.getLastKnownPosition();
//                                   if (lastPos != null) {
//                                     lat = lastPos.latitude;
//                                     lng = lastPos.longitude;
//                                     gpsSuccess = true;
//                                   }
//                                 } catch (_) {}
//                               }
//                               int level =
//                               100; // Safe default for simulators and aggressive background iOS policies
//                               try {
//                                 final battery = Battery();
//                                 level = await battery.batteryLevel;
//                               } catch (e) {
//                                 debugPrint(
//                                   'Battery info not available over isolate, using default: $e',
//                                 );
//                               }
//                               final safetyRepo = ref.read(
//                                 safetyRepositoryProvider,
//                               );
//
//                               await safetyRepo.submitPulse(
//                                 familyId: profile.familyId,
//                                 latitude: lat,
//                                 longitude: lng,
//                                 batteryLevel: level,
//                                 //userName: profile.fullName??"",
//                                 type: 'check_in',
//                               );
//                               if (context.mounted) {
//                                 ScaffoldMessenger.of(context).showSnackBar(
//                                   SnackBar(
//                                     content: Text(
//                                       gpsSuccess
//                                           ? 'Checked in successfully!'
//                                           : 'Checked in (GPS unavailable)',
//                                     ),
//                                     backgroundColor: gpsSuccess
//                                         ? ShieldColors.safeZoneGreen
//                                         : Colors.orange,
//                                   ),
//                                 );
//                               }
//                             },
//                             icon: const Icon(
//                               Icons.check_circle_outline,
//                               size: 24,
//                             ),
//                             label: const Text(
//                               'Check In',
//                               style: TextStyle(
//                                 fontSize: 17,
//                                 fontWeight: FontWeight.bold,
//                               ),
//                             ),
//                             style: ElevatedButton.styleFrom(
//                               backgroundColor: ShieldColors.activeTeal,
//                               foregroundColor: Colors.white,
//                               shape: RoundedRectangleBorder(
//                                 borderRadius: ShieldDesign.roundedTwelve,
//                               ),
//                               elevation: 4,
//                             ),
//                           ),
//                         ),
//                         const SizedBox(height: 12),
//                         // Message Family — now opens in-app chat
//                         SizedBox(
//                           width: double.infinity,
//                           height: 56,
//                           child: ElevatedButton.icon(
//                             onPressed: () {
//                               showModalBottomSheet(
//                                 context: context,
//                                 isScrollControlled: true,
//                                 useSafeArea: true,
//
//                                 backgroundColor: Colors.transparent,
//                                 builder: (_) => const FamilyChatScreen(),
//                               );
//                             },
//                             icon: const Icon(
//                               Icons.chat_bubble_outline,
//                               size: 24,
//                             ),
//                             label: const Text(
//                               'Message Family',
//                               style: TextStyle(
//                                 fontSize: 17,
//                                 fontWeight: FontWeight.bold,
//                               ),
//                             ),
//                             style: ElevatedButton.styleFrom(
//                               backgroundColor: Colors.white,
//                               foregroundColor: ShieldColors.textBody,
//                               shape: RoundedRectangleBorder(
//                                 borderRadius: ShieldDesign.roundedTwelve,
//                               ),
//                               elevation: 2,
//                             ),
//                           ),
//                         ),
//                         const SizedBox(height: 32),
//
//                         // Family Status — BUG FIX: show name instead of role
//                         Text(
//                           'FAMILY STATUS',
//                           style: Theme.of(context).textTheme.labelMedium
//                               ?.copyWith(
//                             fontWeight: FontWeight.bold,
//                             letterSpacing: 1.2,
//                           ),
//                         ),
//                         const SizedBox(height: 16),
//                         StreamBuilder<List<Map<String, dynamic>>>(
//                           stream: _membersController?.stream,
//                           builder: (context, memberSnapshot) {
//                             if (memberSnapshot.connectionState ==
//                                 ConnectionState.waiting) {
//                               return const Center(
//                                 child: CircularProgressIndicator(),
//                               );
//                             }
//                             final members = memberSnapshot.data ?? [];
//                             final parents = members
//                                 .where(
//                                   (m) =>
//                               m['role'] == 'leader' ||
//                                   m['role'] == 'monitor',
//                             )
//                                 .toList();
//
//                             if (parents.isEmpty) {
//                               return const Text('No parents online.');
//                             }
//
//                             return Column(
//                               children: parents
//                                   .map(
//                                     (member) => Padding(
//                                   padding: const EdgeInsets.only(
//                                     bottom: 12,
//                                   ),
//                                   child: ParentLocationRow(
//                                     // FIX: Display name, not role
//                                     name:
//                                     member['full_name'] ??
//                                         'Family Member',
//                                     location: 'Active on Shield',
//                                     // Assuming 'memberLoc' was intended to be this static string or derived elsewhere
//                                     isOnline: true,
//                                     // Assuming 'isOnline' was intended to be this static boolean or derived elsewhere
//                                     avatarUrl:
//                                     member['avatar_url'] as String?,
//                                   ),
//                                 ),
//                               )
//                                   .toList(),
//                             );
//                           },
//                         ),
//                         const SizedBox(height: 100),
//                       ],
//                     ),
//                   ),
//                 ),
//               ],
//             );
//           },
//           loading: () => const Center(child: CircularProgressIndicator()),
//           error: (e, st) => Center(child: Text('Error: $e')),
//         ),
//       ),
//       // Elder-portal style anchored bottom bar
//       bottomNavigationBar: Container(
//         color: Colors.white,
//         child: SafeArea(
//           top: false,
//           child: Padding(
//             padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
//             child: Row(
//               children: [
//                 // Large EMERGENCY button
//                 Expanded(
//                   flex: 3,
//                   child: AnimatedContainer(
//                     duration: const Duration(milliseconds: 300),
//                     height: 60,
//                     child: ElevatedButton(
//                       onPressed: _startSosCountdown,
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: _sosCountdownActive
//                             ? Colors.orange
//                             : ShieldColors.urgentRed,
//                         foregroundColor: Colors.white,
//                         shape: RoundedRectangleBorder(
//                           borderRadius: ShieldDesign.roundedTwelve,
//                         ),
//                         elevation: 6,
//                       ),
//                       child: Row(
//                         mainAxisAlignment: MainAxisAlignment.center,
//                         children: [
//                           const Icon(Icons.warning_rounded, size: 24),
//                           const SizedBox(width: 8),
//                           Flexible(
//                             child: Text(
//                               _sosCountdownActive
//                                   ? 'CANCEL ($_sosCountdown)'
//                                   : 'EMERGENCY',
//                               style: const TextStyle(
//                                 fontWeight: FontWeight.bold,
//                                 fontSize: 15,
//                                 letterSpacing: 1,
//                               ),
//                               overflow: TextOverflow.ellipsis,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 8),
//                 // MENU button (command center)
//                 Expanded(
//                   flex: 3,
//                   child: SizedBox(
//                     height: 60,
//                     child: ElevatedButton(
//                       onPressed: () {
//                         print("dss");
//                         showModalBottomSheet(
//                           context: context,
//                           isScrollControlled: true,
//                           backgroundColor: Colors.transparent,
//                           builder: (_) => const CommandCenterSheet(),
//                         );
//                       },
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: ShieldColors.activeTeal,
//                         foregroundColor: Colors.white,
//                         shape: RoundedRectangleBorder(
//                           borderRadius: ShieldDesign.roundedTwelve,
//                         ),
//                         elevation: 4,
//                       ),
//                       child: const Row(
//                         mainAxisAlignment: MainAxisAlignment.center,
//                         children: [
//                           Icon(Icons.grid_view_rounded, size: 20),
//                           SizedBox(width: 2),
//                           Text(
//                             'MENU',
//                             style: TextStyle(
//                               fontWeight: FontWeight.bold,
//                               fontSize: 14,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// class ParentLocationRow extends StatelessWidget {
//   final String name;
//   final String location;
//   final bool isOnline;
//   final String? avatarUrl;
//
//   const ParentLocationRow({
//     super.key,
//     required this.name,
//     required this.location,
//     required this.isOnline,
//     this.avatarUrl,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       children: [
//         CircleAvatar(
//           radius: 24,
//           backgroundColor: Colors.grey.shade200,
//           backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
//           child: avatarUrl == null
//               ? Icon(Icons.person, color: Colors.grey.shade400)
//               : null,
//         ),
//         const SizedBox(width: 16),
//         Expanded(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 name,
//                 style: Theme.of(context).textTheme.titleMedium?.copyWith(
//                   fontWeight: FontWeight.bold,
//                   color: ShieldColors.textBody,
//                 ),
//               ),
//               Row(
//                 children: [
//                   Icon(
//                     Icons.location_on_outlined,
//                     size: 14,
//                     color: Colors.grey.shade500,
//                   ),
//                   const SizedBox(width: 4),
//                   Text(
//                     location,
//                     style: Theme.of(context).textTheme.bodySmall?.copyWith(
//                       color: Colors.grey.shade600,
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//         Container(
//           width: 12,
//           height: 12,
//           decoration: BoxDecoration(
//             color: isOnline ? const Color(0xFF00E676) : Colors.grey,
//             shape: BoxShape.circle,
//           ),
//         ),
//       ],
//     );
//   }
// }
