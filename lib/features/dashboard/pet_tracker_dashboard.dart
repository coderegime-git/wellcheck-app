import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
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

import '../safety/services/location_service.dart';
import '../safety/services/pulse_service.dart';

class PetDashboard extends ConsumerStatefulWidget {
  const PetDashboard({super.key});

  @override
  ConsumerState<PetDashboard> createState() => _PetDashboardState();
}

class _PetDashboardState extends ConsumerState<PetDashboard> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final granted = await LocationService.checkLocationPermissions(context);
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Location access is required for your safety.',
              ),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Enable',
                onPressed: () async {
                  await LocationService.requestSettingsRedirect(
                    context,
                    title: 'Location Permission Required',
                    steps: [
                      'Tap "Open Settings" below',
                      'Select "Location"',
                      'Choose an option',
                    ],
                  );
                },
              ),
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: safetyRepo.streamMyCheckinSchedules(
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

                        if (nextCheckin == null || selectedSchedule == null) {
                          return const SizedBox.shrink();
                        }

                        final scheduleId = selectedSchedule['id'];

                        return _NextCheckinCard(
                          nextCheckin: nextCheckin,
                          profile: profileAsync.value,
                          scheduleId: scheduleId,
                        );
                      },
                    ),
                    const SizedBox(height: 18),
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
                              // StreamBuilder<Map<String, dynamic>?>(
                              //   stream: safetyRepo.streamMemberLatestEvent(
                              //     profile.userId,
                              //   ),
                              //   builder: (context, snapshot) {
                              //     final event = snapshot.data;
                              //     final inZone =
                              //         event?['event_type'] == 'safe_zone_enter';
                              //     return ShieldMemberCard(
                              //       name: 'Geofence',
                              //       status: inZone ? 'Active' : 'Monitoring',
                              //       metrics: [
                              //         {
                              //           'label': 'STATUS',
                              //           'value': inZone ? 'Secure' : 'Tracking',
                              //           'unit': '',
                              //         },
                              //       ],
                              //       subStatusIcon: Icons.shield_outlined,
                              //       subStatusText: inZone
                              //           ? 'Status: In Safe Zone'
                              //           : 'Status: Monitoring Area',
                              //       isAlert: false,
                              //       isReadOnly: true,
                              //     );
                              //   },
                              // ),
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
      FlutterBackgroundService().invoke('stopService');

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
                '${profile.fullName} initiated an emergency state',
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

        //_checkScheduleTime(widget.nextCheckin);

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
