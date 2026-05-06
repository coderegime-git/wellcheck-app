import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

import '../../core/navigation/shield_router.dart';

class LeaderDashboard extends ConsumerStatefulWidget {
  const LeaderDashboard({super.key});

  @override
  ConsumerState<LeaderDashboard> createState() => _LeaderDashboardState();
}

class _LeaderDashboardState extends ConsumerState<LeaderDashboard> {
  bool _sosCountdownActive = false;
  int _sosCountdown = 5;
  Timer? _sosTimer;

  @override
  void dispose() {
    _sosTimer?.cancel();
    super.dispose();
  }

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
                'Leader manually initiated an emergency state',
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

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    return Scaffold(
      backgroundColor: ShieldColors.activeTeal,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Image.asset('assets/logo.png', height: 40, width: 40),
                  SizedBox(width: 6),
                  Text(
                    "Well-Check",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: ShieldColors.backgroundWhite,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
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
                                profile?.fullName?.split(' ').first ?? 'Leader';
                            return Text(
                              'Welcome, $firstName.',
                              style: Theme.of(context).textTheme.titleMedium
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
                                  ?.copyWith(color: ShieldColors.textLabel),
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
                          return profile != null && profile!.avatarUrl != null
                              ? CircleAvatar(
                                  radius: 35,
                                  backgroundColor: ShieldColors.activeTeal,

                                  backgroundImage: NetworkImage(
                                    profile!.avatarUrl ?? "",
                                  ),
                                )
                              : CircleAvatar(
                                  backgroundColor: ShieldColors.activeTeal,

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
                              builder: (context) => const InviteMemberDialog(),
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
                                        DateTime.now().difference(dt).inHours <
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
                                            backgroundColor: Colors.transparent,
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
                                            decoration: const BoxDecoration(
                                              color: ShieldColors.urgentRed,
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
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                      margin: const EdgeInsets.only(bottom: 8),
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
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                Icons.check_circle,
                                                color:
                                                    ShieldColors.safeZoneGreen,
                                              ),
                                              onPressed: () => safetyRepo
                                                  .approveMember(member['id']),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.cancel,
                                                color: Colors.grey,
                                              ),
                                              onPressed: () => safetyRepo
                                                  .rejectMember(member['id']),
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

                          // Active Members Stream
                          Text(
                            'Shield Members',
                            style: Theme.of(context).textTheme.titleLarge
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
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
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
                                fontSize: 14,
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
                  flex: 3,
                  child: SizedBox(
                    height: 60,
                    child: ElevatedButton(
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,

                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => const CommandCenterSheet(),
                        );
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
                                fontSize: 14,
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
                // Profile icon button
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    color: Colors.white,
                  ),
                  height: 60,
                  width: 60,
                  child: GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const ProfileSettingsView(),
                      );
                    },

                    child: profileAsync.value?.avatarUrl != null
                        ? Container(
                            padding: EdgeInsets.all(10),
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(30),
                              //  borderRadius: ShieldDesign.roundedTwelve,
                              child: Image.network(
                                profileAsync.value!.avatarUrl!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                        : const Icon(Icons.person_outline, size: 26),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    final type = (evt['event_type'] as String?) ?? 'unknown';
    final title =
        evt['title'] as String? ?? type.replaceAll('_', ' ').toUpperCase();
    final description = evt['description'] as String?;
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
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: color,
          fontSize: 13,
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
