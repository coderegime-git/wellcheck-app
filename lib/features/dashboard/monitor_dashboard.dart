import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/data/safety_repository.dart';
import 'package:well_check_v3/features/dashboard/widgets/shield_member_card.dart';
import 'package:well_check_v3/features/dashboard/widgets/command_center_sheet.dart';
import 'package:well_check_v3/features/dashboard/widgets/ai_wellness_card.dart';
import 'package:well_check_v3/features/profile/profile_settings_view.dart';
import 'package:well_check_v3/features/dashboard/widgets/pending_actions_card.dart';

class MonitorDashboard extends ConsumerStatefulWidget {
  const MonitorDashboard({super.key});

  @override
  ConsumerState<MonitorDashboard> createState() => _MonitorDashboardState();
}

class _MonitorDashboardState extends ConsumerState<MonitorDashboard> {
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF6B4EE6),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            profileAsync.when(
              data: (profile) => FutureBuilder<String>(
                future: profile != null
                    ? ref
                          .read(safetyRepositoryProvider)
                          .getFamilyName(profile.familyId)
                    : Future.value('My Family Shield'),
                builder: (context, snap) => Text(
                  snap.data ?? 'My Family Shield',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: ShieldColors.textBody,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (e, st) => const SizedBox.shrink(),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF3F0FF),
                borderRadius: ShieldDesign.roundedTwelve,
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.notifications_none,
                  color: Color(0xFF6B4EE6),
                ),
                onPressed: () {
                  // Show notifications stream
                  final profile = profileAsync.value;
                  if (profile == null) return;
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => _MonitorNotificationsSheet(
                      familyId: profile.familyId,
                      safetyRepo: ref.read(safetyRepositoryProvider),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: profileAsync.when(
          data: (profile) {
            if (profile == null) {
              return const Center(child: Text('No profile found.'));
            }

            final safetyRepo = ref.watch(safetyRepositoryProvider);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Alert Banner Stream
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: safetyRepo.streamFamilyEvents(profile.familyId),
                    builder: (context, snapshot) {
                      final events = snapshot.data ?? [];
                      final recentSos = events
                          .where((e) => e['event_type'] == 'sos')
                          .toList();

                      if (recentSos.isEmpty) return const SizedBox.shrink();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 32),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: ShieldColors.urgentRed.withValues(alpha: 0.1),
                          borderRadius: ShieldDesign.roundedTwelve,
                          border: Border.all(
                            color: ShieldColors.urgentRed.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.notifications_active_outlined,
                              color: ShieldColors.urgentRed,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'ACTIVE ALERT: Immediate Attention Required',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: ShieldColors.urgentRed,
                                      fontWeight: FontWeight.bold,
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
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: ShieldColors.textLabel,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // REAL Map with member pins
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: safetyRepo.streamActiveMembers(profile.familyId),
                    builder: (context, memberSnap) {
                      final members = memberSnap.data ?? [];
                      return _TacticalMap(
                        members: members,
                        safetyRepo: safetyRepo,
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Live member cards from Realtime stream
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: safetyRepo.streamActiveMembers(profile.familyId),
                    builder: (context, memberSnapshot) {
                      if (memberSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
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
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error: $e')),
        ),
      ),
      bottomNavigationBar: SafeArea(
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
                        builder: (_) => const CommandCenterSheet(),
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
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Profile
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
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child:
                      profileAsync.value != null &&
                          profileAsync.value!.avatarUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(26),
                          child: Image.network(
                            profileAsync.value!.avatarUrl!,
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(Icons.person, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                        name.toString().split(' ').first,
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
                final events = snapshot.data ?? [];
                if (events.isEmpty) {
                  return const Center(
                    child: Text(
                      'No notifications.',
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

                    IconData icon = Icons.notifications;
                    if (type == 'sos') icon = Icons.warning;
                    if (type == 'check_in') icon = Icons.how_to_reg;

                    return ListTile(
                      leading: Icon(
                        icon,
                        size: 20,
                        color: ShieldColors.activeTeal,
                      ),
                      title: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
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
