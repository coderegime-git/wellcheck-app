import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/data/safety_repository.dart';
import 'package:well_check_v3/features/dashboard/widgets/shield_member_card.dart';
import 'package:well_check_v3/features/dashboard/widgets/command_center_sheet.dart';
import 'package:well_check_v3/features/dashboard/widgets/ai_wellness_card.dart';
import 'package:well_check_v3/features/profile/profile_settings_view.dart';
import 'package:well_check_v3/features/dashboard/widgets/pending_actions_card.dart';

import '../../core/data/medication_provider.dart';
import '../../core/notifications/push_notification_service.dart';

class MonitorDashboard extends ConsumerStatefulWidget {
  const MonitorDashboard({super.key});

  @override
  ConsumerState<MonitorDashboard> createState() => _MonitorDashboardState();
}

class _MonitorDashboardState extends ConsumerState<MonitorDashboard> {
  bool _sosCountdownActive = false;
  int _sosCountdown = 5;
  Timer? _sosTimer;
  Timer? _medicationTimer;
  bool isLoad = false;

  @override
  void initState() {
    initializeFCM();
    super.initState();
  }

  void initializeFCM() async {
    // _medicationTimer = Timer.periodic(
    //   const Duration(seconds: 1),
    //       (_) {
    //     if (mounted) {
    //       setState(() {});
    //     }
    //   },
    // );
    await PushNotificationService.initialize();
  }

  @override
  void dispose() {
    _sosTimer?.cancel();
    _medicationTimer?.cancel();
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
            '${profile.fullName}- Monitor initiated an emergency state',
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

    return Scaffold(
      backgroundColor: isLoad ? Colors.white : ShieldColors.activeTeal,
      // appBar: AppBar(
      //   backgroundColor: Colors.white,
      //   elevation: 0,
      //   surfaceTintColor: Colors.transparent,
      //   title: Column(
      //     crossAxisAlignment: CrossAxisAlignment.start,
      //     children: [
      //       Row(
      //         children: [
      //           const Icon(
      //             Icons.remove_red_eye_outlined,
      //             size: 14,
      //             color: Color(0xFF6B4EE6),
      //           ),
      //           const SizedBox(width: 4),
      //           Text(
      //             'MONITOR VIEW',
      //             style: Theme.of(context).textTheme.labelSmall?.copyWith(
      //               color: const Color(0xFF6B4EE6),
      //               fontWeight: FontWeight.bold,
      //               letterSpacing: 1.2,
      //             ),
      //           ),
      //         ],
      //       ),
      //       profileAsync.when(
      //         data: (profile) => FutureBuilder<String>(
      //           future: profile != null
      //               ? ref
      //                     .read(safetyRepositoryProvider)
      //                     .getFamilyName(profile.familyId)
      //               : Future.value('My Family Shield'),
      //           builder: (context, snap) => Text(
      //             snap.data ?? 'My Family Shield',
      //             style: Theme.of(context).textTheme.titleMedium?.copyWith(
      //               fontWeight: FontWeight.bold,
      //               color: ShieldColors.textBody,
      //             ),
      //             maxLines: 1,
      //             overflow: TextOverflow.ellipsis,
      //           ),
      //         ),
      //         loading: () => const SizedBox.shrink(),
      //         error: (e, st) => const SizedBox.shrink(),
      //       ),
      //     ],
      //   ),
      //   actions: [
      //     Padding(
      //       padding: const EdgeInsets.only(right: 16.0),
      //       child: Container(
      //         decoration: BoxDecoration(
      //           color: const Color(0xFFF3F0FF),
      //           borderRadius: ShieldDesign.roundedTwelve,
      //         ),
      //         child: IconButton(
      //           icon: const Icon(
      //             Icons.notifications_none,
      //             color: Color(0xFF6B4EE6),
      //           ),
      //           onPressed: () {
      //             // Show notifications stream
      //             final profile = profileAsync.value;
      //             if (profile == null) return;
      //             showModalBottomSheet(
      //               context: context,
      //               isScrollControlled: true,
      //               backgroundColor: Colors.transparent,
      //               builder: (ctx) => _MonitorNotificationsSheet(
      //                 familyId: profile.familyId,
      //                 safetyRepo: ref.read(safetyRepositoryProvider),
      //               ),
      //             );
      //           },
      //         ),
      //       ),
      //     ),
      //   ],
      // ),
      body: isLoad
          ? Center(child: CircularProgressIndicator())
          : SafeArea(
        child: profileAsync.when(
          data: (profile) {
            if (profile == null) {
              return const Center(child: Text('No profile found.'));
            }

            final safetyRepo = ref.watch(safetyRepositoryProvider);

            return Column(
              children: [
                SizedBox(height: 8),

                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12),
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
                        style: Theme
                            .of(context)
                            .textTheme
                            .headlineSmall
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
                SizedBox(height: 18),
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
                                    profile?.fullName
                                        ?.split(' ')
                                        .first ??
                                        'Leader';
                                return Text(
                                  'Welcome, $firstName.',
                                  style: Theme
                                      .of(context)
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
                              loading: () =>
                                  Text(
                                    'Welcome back...',
                                    style: Theme
                                        .of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: ShieldColors.textBody,
                                    ),
                                  ),
                              error: (e, st) =>
                                  Text(
                                    'Welcome, Leader.',
                                    style: Theme
                                        .of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: ShieldColors.textBody,
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.remove_red_eye_outlined,
                                  size: 14,
                                  color: Color(0xFF6B4EE6),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'MONITOR VIEW',
                                  style: Theme
                                      .of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                    color: const Color(0xFF6B4EE6),
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                            // Row(
                            //   children: [
                            //     Icon(
                            //       Icons.privacy_tip,
                            //       color: ShieldColors.activeTeal,
                            //       size: 22,
                            //     ),
                            //     SizedBox(width: 5),
                            //     Text(
                            //       'The Shield is active',
                            //       style: Theme.of(context).textTheme.bodySmall
                            //           ?.copyWith(color: ShieldColors.textLabel),
                            //       overflow: TextOverflow.ellipsis,
                            //     ),
                            //   ],
                            // ),
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

                          const SizedBox(width: 12),
                          // Bug 2: Notification bell now shows recent events
                          Container(
                            padding: EdgeInsets.all(10),

                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: ShieldDesign.roundedTwelve,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: 0.05,
                                  ),
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
                                : StreamBuilder<
                                List<Map<String, dynamic>>
                            >(
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
                                      DateTime
                                          .now()
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
                                        color:
                                        ShieldColors.textBody,
                                      ),
                                      onTap: () {
                                        showModalBottomSheet(
                                          context: context,
                                          isScrollControlled: true,
                                          backgroundColor:
                                          Colors.transparent,
                                          builder: (ctx) =>
                                              _MonitorNotificationsSheet(
                                                familyId:
                                                profileAsync
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
                                            shape:
                                            BoxShape.circle,
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
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      final safety = ref.invalidate(
                        safetyRepositoryProvider,
                      );
                      ref.invalidate(familyMedicationsProvider);
                    },
                    child: SingleChildScrollView(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                        ),
                        padding: const EdgeInsets.all(24.0),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Alert Banner Stream
                            StreamBuilder<List<Map<String, dynamic>>>(
                              stream: safetyRepo.streamFamilyEvents(
                                profile.familyId,
                              ),
                              builder: (context, snapshot) {
                                final events = snapshot.data ?? [];
                                final recentSos = events
                                    .where(
                                      (e) => e['event_type'] == 'sos',
                                )
                                    .toList();

                                if (recentSos.isEmpty)
                                  return const SizedBox.shrink();

                                return Container(
                                  margin: const EdgeInsets.only(
                                    bottom: 32,
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: ShieldColors.urgentRed
                                        .withValues(alpha: 0.1),
                                    borderRadius:
                                    ShieldDesign.roundedTwelve,
                                    border: Border.all(
                                      color: ShieldColors.urgentRed
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons
                                            .notifications_active_outlined,
                                        color: ShieldColors.urgentRed,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'ACTIVE ALERT: Immediate Attention Required',
                                          style: Theme
                                              .of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                            color: ShieldColors
                                                .urgentRed,
                                            fontWeight:
                                            FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                            const PendingActionsCard(),

                            Text(
                              'SHIELD MEMBERS - TACTICAL VIEW',
                              style: Theme
                                  .of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                color: ShieldColors.textLabel,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // REAL Map with member pins
                            StreamBuilder<List<Map<String, dynamic>>>(
                              stream: safetyRepo.streamActiveMembers(
                                profile.familyId,
                              ),
                              builder: (context, memberSnap) {
                                final members = memberSnap.data ?? [];
                                return _TacticalMap(
                                  members: members,
                                  safetyRepo: safetyRepo,
                                );
                              },
                            ),
                            const SizedBox(height: 14),

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
                                return _NextCheckinCard(
                                  nextCheckin: nextCheckin,
                                  profile: profileAsync.value,
                                  scheduleId: scheduleId,
                                  assignedUser: assignedUser,
                                  assignedUserId: assignedUserId,
                                );
                              },
                            ),
                            const SizedBox(height: 14),
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
                                        style: Theme
                                            .of(context)
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
                                        '${diff?.inHours}h ${diff?.inMinutes
                                            .remainder(60)}m ${diff?.inSeconds
                                            .remainder(60)}s';
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
                                                            '${med
                                                                .dosage} • ${med
                                                                .scheduleSummary}',
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .grey
                                                                  .shade700,
                                                              fontSize:
                                                              12,
                                                            ),
                                                          ),

                                                          if (med.assignedName != null) ...[
                                                            const SizedBox(height: 4),

                                                            Text(
                                                              'Assigned to: ${med.assignedName}',
                                                              style: TextStyle(
                                                                color: Colors.blueGrey,
                                                                fontSize: 12,
                                                                fontWeight: FontWeight.w500,
                                                              ),
                                                            ),
                                                          ],


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
                                                                  stream: Stream
                                                                      .periodic(
                                                                    const Duration(
                                                                      seconds:
                                                                      1,
                                                                    ),
                                                                  ),
                                                                  builder:
                                                                      (context,
                                                                      snapshot,) {
                                                                    final diff =
                                                                        nextDose
                                                                            ?.difference(
                                                                          DateTime
                                                                              .now(),
                                                                        ) ??
                                                                            Duration
                                                                                .zero;

                                                                    // Prevent negative values
                                                                    final safeDiff = diff
                                                                        .isNegative
                                                                        ? Duration
                                                                        .zero
                                                                        : diff;

                                                                    final text =
                                                                        '${safeDiff
                                                                        .inHours
                                                                        .toString()
                                                                        .padLeft(
                                                                        2,
                                                                        '0')}h '
                                                                        '${safeDiff
                                                                        .inMinutes
                                                                        .remainder(
                                                                        60)
                                                                        .toString()
                                                                        .padLeft(
                                                                        2,
                                                                        '0')}m '
                                                                        '${safeDiff
                                                                        .inSeconds
                                                                        .remainder(
                                                                        60)
                                                                        .toString()
                                                                        .padLeft(
                                                                        2,
                                                                        '0')}s';

                                                                    return Text(
                                                                      text,
                                                                      style: TextStyle(
                                                                        color: ShieldColors
                                                                            .activeTeal,
                                                                        fontWeight: FontWeight
                                                                            .w600,
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
                              loading: () =>
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                              error: (e, st) => const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 10),

                            //   const SizedBox(height: 24),

                            // Live member cards from Realtime stream
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

                                final members = memberSnapshot.data ?? [];
                                if (members.isEmpty) {
                                  return const Text('No members found.');
                                }

                                return Column(
                                  children: members.map((member) {
                                    return _LiveMemberCard(
                                      member: member,
                                      safetyRepo: safetyRepo,
                                      currentUserId: profile.userId,
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                            const SizedBox(height: 20),
                            const AiWellnessCard(),
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
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error: $e')),
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
                const SizedBox(width: 5),
                // MENU button
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 60,
                    child: ElevatedButton(
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => CommandCenterSheet(fromLeader: false),
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
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.grid_view_rounded, size: 20),
                          SizedBox(width: 6),
                          Text(
                            'MENU',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // const SizedBox(width: 8),
                // // Profile
                // GestureDetector(
                //   onTap: () {
                //     showModalBottomSheet(
                //       context: context,
                //       isScrollControlled: true,
                //       backgroundColor: Colors.transparent,
                //       builder: (_) => const ProfileSettingsView(),
                //     );
                //   },
                //   child: Container(
                //     width: 52,
                //     height: 52,
                //     decoration: BoxDecoration(
                //       shape: BoxShape.circle,
                //       color: Colors.grey.shade300,
                //       border: Border.all(color: Colors.white, width: 2),
                //     ),
                //     child:
                //         profileAsync.value != null &&
                //             profileAsync.value!.avatarUrl != null
                //         ? ClipRRect(
                //             borderRadius: BorderRadius.circular(26),
                //             child: Image.network(
                //               profileAsync.value!.avatarUrl!,
                //               fit: BoxFit.cover,
                //             ),
                //           )
                //         : const Icon(Icons.person, color: Colors.grey),
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
}

/// REAL tactical map showing member locations from latest events
class _TacticalMap extends StatelessWidget {
  final List<Map<String, dynamic>> members;
  final SafetyRepository safetyRepo;

  const _TacticalMap({required this.members, required this.safetyRepo});

  @override
  Widget build(BuildContext context) {
    // We gather pins from each member's latest event
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: ShieldDesign.roundedTwelve,
        border: Border.all(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.hardEdge,
      child: _MapContent(members: members, safetyRepo: safetyRepo),
    );
  }
}

class _MapContent extends StatefulWidget {
  final List<Map<String, dynamic>> members;
  final SafetyRepository safetyRepo;

  const _MapContent({required this.members, required this.safetyRepo});

  @override
  State<_MapContent> createState() => _MapContentState();
}

class _MapContentState extends State<_MapContent> {
  final List<Marker> _markers = [];
  LatLng _center = const LatLng(37.7749, -122.4194); // default SF
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  @override
  void didUpdateWidget(_MapContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.members.length != widget.members.length) {
      _loadPins();
    }
  }

  Future<void> _loadPins() async {
    final markers = <Marker>[];
    for (final member in widget.members) {
      final userId = member['id'] as String?;
      if (userId == null) continue;

      // Fetch latest event for this member
      try {
        final event = await widget.safetyRepo.getLatestEventForUser(userId);
        if (event != null) {
          final lat = event['latitude'] as num?;
          final lng = event['longitude'] as num?;
          if (lat != null && lng != null && lat != 0 && lng != 0) {
            final role = member['role'] as String? ?? '';
            final name = member['full_name'] ?? 'Member';
            final isSos = event['event_type'] == 'sos';

            markers.add(
              Marker(
                point: LatLng(lat.toDouble(), lng.toDouble()),
                width: 40,
                height: 50,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSos ? Icons.warning : Icons.location_on,
                      color: isSos ? ShieldColors.urgentRed : _roleColor(role),
                      size: 28,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        name
                            .toString()
                            .split(' ')
                            .first,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }
      } catch (_) {
        // Skip members without event data
      }
    }

    if (mounted) {
      setState(() {
        _markers.clear();
        _markers.addAll(markers);
        if (markers.isNotEmpty) {
          _center = markers.first.point;
        }
        _loaded = true;
      });
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'leader':
        return ShieldColors.activeTeal;
      case 'monitor':
        return const Color(0xFF6B4EE6);
      case 'senior':
        return Colors.orange;
      case 'student':
        return Colors.blue;
      case 'pet':
        return Colors.brown;
      default:
        return ShieldColors.activeTeal;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_markers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            const Text(
              'No location data yet.\nMembers will appear here after check-ins.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return FlutterMap(
      options: MapOptions(initialCenter: _center, initialZoom: 13.0),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.well_check_v3',
        ),
        MarkerLayer(markers: _markers),
      ],
    );
  }
}

/// Live member card with StreamBuilder on latest event
class _LiveMemberCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final SafetyRepository safetyRepo;
  final String currentUserId;

  const _LiveMemberCard({
    required this.member,
    required this.safetyRepo,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: safetyRepo.streamMemberLatestEvent(member['id']),
      builder: (context, snapshot) {
        final lastEvent = snapshot.data;
        final role = member['role'] as String;
        final realName = member['full_name'] ?? 'Family Member';
        final isMe = member['id'] == currentUserId;

        String displayName = isMe ? '$realName (You)' : realName;
        IconData statusIcon = Icons.radio_button_unchecked;
        String statusText = 'Awaiting first pulse...';
        bool isAlert = false;
        List<Map<String, String>> metrics = [];

        if (lastEvent != null) {
          final type = lastEvent['event_type'] as String;
          final battery = lastEvent['battery_level'];
          final createdAt = lastEvent['created_at'] as String?;

          // Last seen
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

          // Status from event type
          if (type == 'sos' && lastEvent['metadata']?['status'] != 'resolved') {
            isAlert = true;
            statusText = 'EMERGENCY: SOS ACTIVE';
            statusIcon = Icons.warning;
          } else if (type == 'driving' || type == 'driving_alert') {
            statusText = 'In Motion';
            statusIcon = Icons.directions_car;
          } else if (type == 'safe_zone_enter') {
            statusText = 'In Safe Zone';
            statusIcon = Icons.verified_user;
          } else if (type == 'check_in') {
            statusText = 'Checked In';
            statusIcon = Icons.how_to_reg;
          } else {
            statusText = lastSeen.isNotEmpty ? 'Last seen $lastSeen' : 'Online';
            statusIcon = Icons.check_circle_outline;
          }

          // Metrics from real data
          if (battery != null) {
            metrics.add({'label': 'BATTERY', 'value': '$battery', 'unit': '%'});
          }

          // Location
          final lat = lastEvent['latitude'];
          final lng = lastEvent['longitude'];
          final semLoc = lastEvent['metadata']?['semantic_location'];
          if (semLoc != null) {
            metrics.add({'label': 'LOC', 'value': '$semLoc', 'unit': ''});
          } else if (lat != null && lng != null) {
            metrics.add({'label': 'LOC', 'value': 'GPS Active', 'unit': ''});
          }
        } else {
          statusText = 'No data received yet';
        }

        if (role == 'senior' && metrics.isEmpty) {
          metrics.add({'label': 'VITALS', 'value': 'No wearable', 'unit': ''});
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
            isReadOnly: true,
            avatarUrl: member['avatar_url'] as String?,
          ),
        );
      },
    );
  }
}

/// Notifications sheet for Monitor
class _MonitorNotificationsSheet extends StatelessWidget {
  final String familyId;
  final SafetyRepository safetyRepo;

  const _MonitorNotificationsSheet({
    required this.familyId,
    required this.safetyRepo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ShieldColors.backgroundWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      constraints: BoxConstraints(
        maxHeight: MediaQuery
            .of(context)
            .size
            .height * 0.7,
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
            style: Theme
                .of(
              context,
            )
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: safetyRepo.streamFamilyEvents(familyId),
              builder: (context, snapshot) {
                final events = snapshot.data ?? [];
                if (events.isEmpty) {
                  return const Center(
                    child: Text(
                      'No notifications.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                // return ListView.separated(
                //   itemCount: events.length > 20 ? 20 : events.length,
                //   separatorBuilder: (context, index) =>
                //       const Divider(height: 1),
                //   itemBuilder: (context, index) {
                //     final evt = events[index];
                //     final type = (evt['event_type'] as String?) ?? 'unknown';
                //     final title =
                //         evt['title'] as String? ?? type.replaceAll('_', ' ');
                //     final desc = evt['description'] as String? ?? '';
                //
                //     IconData icon = Icons.notifications;
                //     if (type == 'sos') icon = Icons.warning;
                //     if (type == 'check_in') icon = Icons.how_to_reg;
                //
                //     return ListTile(
                //       leading: Icon(
                //         icon,
                //         size: 20,
                //         color: ShieldColors.activeTeal,
                //       ),
                //       title: Text(
                //         title,
                //         style: const TextStyle(
                //           fontSize: 13,
                //           fontWeight: FontWeight.w600,
                //         ),
                //       ),
                //       subtitle: desc.isNotEmpty
                //           ? Text(
                //               desc,
                //               maxLines: 1,
                //               overflow: TextOverflow.ellipsis,
                //               style: const TextStyle(fontSize: 11),
                //             )
                //           : null,
                //     );
                //   },
                // );
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
                      "- Next Check-In at ${DateFormat('dd MMM yyyy, hh:mm a')
                          .format(widget.nextCheckin)}",
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
              ), if (widget.profile?.userId == widget.assignedUserId)

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
                              "${profile.fullName ??
                                  'Someone'}: Checked in just now",
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
