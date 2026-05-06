import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/data/safety_repository.dart';
import 'package:well_check_v3/core/data/calendar_provider.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/features/dashboard/widgets/shield_member_card.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';

class PetDashboard extends ConsumerWidget {
  const PetDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final petName = profileAsync.value?.fullName ?? 'Pet';
    final safetyRepo = ref.read(safetyRepositoryProvider);

    return profileAsync.when(
      data: (profile) {
        if (profile == null) {
          return const Scaffold(body: Center(child: Text('No profile.')));
        }

        return Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              // Live Map Background showing pet's last location
              // Positioned(
              //   top: 0,
              //   left: 0,
              //   right: 0,
              //   height: MediaQuery.of(context).size.height * 0.42,
              //   child: StreamBuilder<Map<String, dynamic>?>(
              //     stream: safetyRepo.streamMemberLatestEvent(profile.userId),
              //     builder: (context, snapshot) {
              //       final event = snapshot.data;
              //       final lat =
              //           (event?['latitude'] as num?)?.toDouble() ?? 37.7749;
              //       final lng =
              //           (event?['longitude'] as num?)?.toDouble() ?? -122.4194;
              //       final hasLocation = event?['latitude'] != null;
              //
              //       return FlutterMap(
              //         options: MapOptions(
              //           initialCenter: LatLng(lat, lng),
              //           initialZoom: 15.0,
              //         ),
              //         children: [
              //           TileLayer(
              //             urlTemplate:
              //                 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              //             userAgentPackageName: 'com.anwiik.well_check_v3',
              //             additionalOptions: const {
              //               'User-Agent':
              //                   'well_check_v3/1.0 (com.anwiik.well_check_v3)',
              //             },
              //           ),
              //           if (hasLocation)
              //             MarkerLayer(
              //               markers: [
              //                 Marker(
              //                   point: LatLng(lat, lng),
              //                   width: 40,
              //                   height: 40,
              //                   child: Container(
              //                     decoration: BoxDecoration(
              //                       color: ShieldColors.urgentRed,
              //                       shape: BoxShape.circle,
              //                       boxShadow: [
              //                         BoxShadow(
              //                           color: ShieldColors.urgentRed
              //                               .withValues(alpha: 0.4),
              //                           blurRadius: 12,
              //                           spreadRadius: 4,
              //                         ),
              //                       ],
              //                     ),
              //                     child: const Icon(
              //                       Icons.pets,
              //                       color: Colors.white,
              //                       size: 22,
              //                     ),
              //                   ),
              //                 ),
              //               ],
              //             ),
              //         ],
              //       );
              //     },
              //   ),
              // ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: MediaQuery.of(context).size.height * 0.55,
                child: ClipRect(
                  child: StreamBuilder<Map<String, dynamic>?>(
                    stream: safetyRepo.streamMemberLatestEvent(profile.userId),
                    builder: (context, snapshot) {
                      final event = snapshot.data;
                      final lat =
                          (event?['latitude'] as num?)?.toDouble() ?? 13.0827;
                      final lng =
                          (event?['longitude'] as num?)?.toDouble() ?? 80.2707;
                      final hasLocation = event?['latitude'] != null;

                      return FlutterMap(
                        mapController: MapController(),
                        options: MapOptions(
                          initialCenter: LatLng(lat, lng),
                          initialZoom: 15.0,
                          keepAlive: true,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.anwiik.well_check_v3',
                            tileProvider: NetworkTileProvider(),
                            additionalOptions: const {
                              'User-Agent':
                                  'well_check_v3/1.0 (com.anwiik.well_check_v3)',
                            },
                          ),
                          if (hasLocation)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: LatLng(lat, lng),
                                  width: 40,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: ShieldColors.urgentRed,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: ShieldColors.urgentRed
                                              .withValues(alpha: 0.4),
                                          blurRadius: 12,
                                          spreadRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.pets,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              SafeArea(
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios_new,
                              color: Colors.black87,
                            ),
                            onPressed: () {
                              _logout(context);
                            },
                          ),
                          Column(
                            children: [
                              Text(
                                'LIVE TRACKING',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                      color: Colors.black87,
                                    ),
                              ),
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundColor: Colors.brown.shade200,
                                    child: const Icon(
                                      Icons.pets,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    petName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.refresh,
                              color: Colors.black87,
                            ),
                            onPressed: () {
                              ref.invalidate(currentUserProfileProvider);
                            },
                          ),
                        ],
                      ),
                    ),

                    //const Spacer(),
                    SizedBox(height: MediaQuery.of(context).size.height * 0.17),

                    // Live status pills from latest event
                    StreamBuilder<Map<String, dynamic>?>(
                      stream: safetyRepo.streamMemberLatestEvent(
                        profile.userId,
                      ),
                      builder: (context, snapshot) {
                        final event = snapshot.data;
                        final battery =
                            event?['battery_level']?.toString() ?? '--';
                        final hasGps = event?['latitude'] != null;

                        String zoneStatus = 'Unknown';
                        final eventType = event?['event_type'] as String?;
                        if (eventType == 'safe_zone_enter') {
                          zoneStatus = 'In Zone';
                        } else if (eventType == 'safe_zone_exit') {
                          zoneStatus = 'Outside';
                        } else if (eventType?.contains('heartbeat') ?? false) {
                          zoneStatus = hasGps ? 'GPS Active' : 'Idle';
                        } else {
                          zoneStatus = hasGps ? 'Tracked' : 'Idle';
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 24.0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildMapPill(
                                context,
                                Icons.battery_charging_full,
                                'Battery',
                                '$battery%',
                              ),
                              _buildMapPill(
                                context,
                                Icons.signal_cellular_alt,
                                'Signal',
                                hasGps ? 'Strong' : 'Weak',
                              ),
                              _buildMapPill(
                                context,
                                Icons.near_me_outlined,
                                'Status',
                                zoneStatus,
                                valueColor: ShieldColors.activeTeal,
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    // Bottom Panel
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Color(0xFF131A2A),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(32),
                            topRight: Radius.circular(32),
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Geofence Status Card
                              StreamBuilder<Map<String, dynamic>?>(
                                stream: safetyRepo.streamMemberLatestEvent(
                                  profile.userId,
                                ),
                                builder: (context, snapshot) {
                                  final event = snapshot.data;
                                  final inZone =
                                      event?['event_type'] == 'safe_zone_enter';
                                  return ShieldMemberCard(
                                    name: 'Geofence',
                                    status: inZone ? 'Active' : 'Monitoring',
                                    metrics: [
                                      {
                                        'label': 'STATUS',
                                        'value': inZone ? 'Secure' : 'Tracking',
                                        'unit': '',
                                      },
                                    ],
                                    subStatusIcon: Icons.shield_outlined,
                                    subStatusText: inZone
                                        ? 'Status: In Safe Zone'
                                        : 'Status: Monitoring Area',
                                    isAlert: false,
                                    isReadOnly: true,
                                  );
                                },
                              ),
                              const SizedBox(height: 24),

                              // Paws-Trail History — from real well_events
                              Text(
                                'PAWS-TRAIL',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                              ),
                              const SizedBox(height: 16),
                              StreamBuilder<List<Map<String, dynamic>>>(
                                stream: safetyRepo.streamFamilyEvents(
                                  profile.familyId,
                                ),
                                builder: (context, snapshot) {
                                  final events = (snapshot.data ?? [])
                                      .where(
                                        (e) => e['user_id'] == profile.userId,
                                      )
                                      .take(5)
                                      .toList();

                                  if (events.isEmpty) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Text(
                                        'No location trail yet. Events will appear here as tracking data comes in.',
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 13,
                                        ),
                                      ),
                                    );
                                  }

                                  return Column(
                                    children: events.asMap().entries.map((
                                      entry,
                                    ) {
                                      final evt = entry.value;
                                      final isFirst = entry.key == 0;
                                      final loc =
                                          evt['metadata']?['semantic_location']
                                              as String? ??
                                          evt['title'] as String? ??
                                          evt['event_type'] as String? ??
                                          'Unknown';
                                      final createdAt =
                                          evt['created_at'] as String?;
                                      String time = '';
                                      if (createdAt != null) {
                                        try {
                                          final dt = DateTime.parse(createdAt);
                                          final diff = DateTime.now()
                                              .difference(dt);
                                          if (diff.inMinutes < 60) {
                                            time = '${diff.inMinutes}m ago';
                                          } else if (diff.inHours < 24) {
                                            time = '${diff.inHours}h ago';
                                          } else {
                                            time = DateFormat.MMMd().format(dt);
                                          }
                                        } catch (_) {}
                                      }
                                      return _buildPawsTrailItem(
                                        context,
                                        loc,
                                        time,
                                        isFirst,
                                      );
                                    }).toList(),
                                  );
                                },
                              ),

                              const SizedBox(height: 24),

                              // Care Reminders — from real calendar_events
                              Text(
                                'CARE REMINDERS',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                              ),
                              const SizedBox(height: 16),
                              Consumer(
                                builder: (context, ref, _) {
                                  final eventsAsync = ref.watch(
                                    familyCalendarEventsProvider,
                                  );
                                  return eventsAsync.when(
                                    data: (events) {
                                      // Show upcoming care-related events
                                      final petEvents = events
                                          .where(
                                            (e) =>
                                                e.title.toLowerCase().contains(
                                                  'pet',
                                                ) ||
                                                e.title.toLowerCase().contains(
                                                  'walk',
                                                ) ||
                                                e.title.toLowerCase().contains(
                                                  'feed',
                                                ) ||
                                                e.title.toLowerCase().contains(
                                                  'vet',
                                                ) ||
                                                e.title.toLowerCase().contains(
                                                  'groom',
                                                ) ||
                                                e.title.toLowerCase().contains(
                                                  'meds',
                                                ) ||
                                                e.participants.contains(
                                                  profile.userId,
                                                ),
                                          )
                                          .take(5)
                                          .toList();

                                      if (petEvents.isEmpty) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          child: Text(
                                            'No care reminders set. Create events in the Calendar to track walks, feeding, and vet appointments.',
                                            style: TextStyle(
                                              color: Colors.grey.shade500,
                                              fontSize: 13,
                                            ),
                                          ),
                                        );
                                      }

                                      return Column(
                                        children: petEvents.map((evt) {
                                          final title = evt.title;
                                          final dt = evt.eventDatetime;
                                          final isPast = dt.isBefore(
                                            DateTime.now(),
                                          );
                                          String time = '';
                                          if (isPast) {
                                            time = 'Done';
                                          } else {
                                            final diff = dt.difference(
                                              DateTime.now(),
                                            );
                                            if (diff.inHours < 24) {
                                              time = DateFormat.jm().format(dt);
                                            } else {
                                              time = DateFormat.MMMd().format(
                                                dt,
                                              );
                                            }
                                          }
                                          return _buildCareReminder(
                                            context,
                                            title,
                                            time,
                                            isPast,
                                          );
                                        }).toList(),
                                      );
                                    },
                                    loading: () => const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    error: (_, __) => Text(
                                      'Could not load reminders',
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(height: 24),
                              Center(
                                child: StreamBuilder<Map<String, dynamic>?>(
                                  stream: safetyRepo.streamMemberLatestEvent(
                                    profile.userId,
                                  ),
                                  builder: (context, snapshot) {
                                    final createdAt =
                                        snapshot.data?['created_at'] as String?;
                                    String lastUpdated = 'No data yet';
                                    if (createdAt != null) {
                                      try {
                                        final dt = DateTime.parse(
                                          createdAt,
                                        ).toLocal();
                                        lastUpdated = DateFormat.jm().format(
                                          dt,
                                        );
                                      } catch (_) {}
                                    }
                                    return Text(
                                      'Last updated: $lastUpdated',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.grey.shade500,
                                          ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 60),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.large(
            heroTag: 'alert_btn',
            onPressed: () async {
              await ref
                  .read(safetyRepositoryProvider)
                  .triggerSiren(
                    profile.familyId,
                    'Pet tracker initiated an emergency geofence breach alert',
                  );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Pet Tracker triggered Global SOS!'),
                  ),
                );
              }
            },
            backgroundColor: ShieldColors.activeTeal,
            elevation: 8,
            shape: const CircleBorder(),
            child: const Icon(
              Icons.error_outline,
              color: Colors.white,
              size: 40,
            ),
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }

  Widget _buildMapPill(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: ShieldDesign.roundedTwelve,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: Colors.grey.shade700),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? ShieldColors.textBody,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPawsTrailItem(
    BuildContext context,
    String location,
    String time,
    bool isCurrent,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: isCurrent ? ShieldColors.activeTeal : Colors.grey.shade600,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              location,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: isCurrent ? Colors.white : Colors.grey.shade400,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            time,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildCareReminder(
    BuildContext context,
    String title,
    String time,
    bool isComplete,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2438),
        borderRadius: ShieldDesign.roundedTwelve,
      ),
      child: Row(
        children: [
          Icon(
            isComplete ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isComplete
                ? ShieldColors.safeZoneGreen
                : Colors.grey.shade500,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isComplete ? Colors.grey.shade500 : Colors.white,
                    decoration: isComplete ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  time,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out?'),
        content: const Text('You will be signed out of the Shield network.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ShieldColors.urgentRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    //  setState(() => _isLoggingOut = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('priv_biometric', false);
      await Supabase.instance.client.auth.signOut();
      // Router will handle navigation to login via auth state listener
    } catch (e) {
      // if (mounted) {
      // setState(() => _isLoggingOut = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
      // }
    }
  }
}
