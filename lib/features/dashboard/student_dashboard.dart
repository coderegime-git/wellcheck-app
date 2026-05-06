import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/safety_repository.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/data/tools_repository.dart';
import 'package:well_check_v3/features/profile/profile_settings_view.dart';
import 'package:well_check_v3/features/messaging/family_chat_screen.dart';
import 'package:well_check_v3/features/dashboard/widgets/command_center_sheet.dart';
import 'package:well_check_v3/features/dashboard/widgets/pending_actions_card.dart';
import 'package:geolocator/geolocator.dart';

class StudentDashboard extends ConsumerStatefulWidget {
  const StudentDashboard({super.key});

  @override
  ConsumerState<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends ConsumerState<StudentDashboard> {
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
                'Minor pressed Emergency SOS (5s countdown completed)',
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
      backgroundColor: ShieldColors.softMint,
      body: SafeArea(
        child: profileAsync.when(
          data: (profile) {
            if (profile == null) {
              return const Center(child: Text('No profile found.'));
            }

            final toolsRepo = ref.watch(toolsRepositoryProvider);
            final safetyRepo = ref.watch(safetyRepositoryProvider);

            return ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hi, ${profile.fullName?.split(' ').first ?? 'there'}!',
                            style: Theme.of(context).textTheme.headlineMedium
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
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: ShieldColors.textLabel),
                          ),
                        ],
                      ),
                    ),
                    // Profile avatar — taps to open ProfileSettingsView
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
                        child: profile.avatarUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(26),
                                child: Image.network(
                                  profile.avatarUrl!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : const Icon(Icons.person, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                const PendingActionsCard(),

                // Safe Zones Status
                Text(
                  'YOUR SAFE ZONES',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: toolsRepo.streamSafeZones(profile.familyId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final zones = snapshot.data ?? [];

                    if (zones.isEmpty) {
                      return Container(
                        height: 120,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: ShieldDesign.roundedTwelve,
                        ),
                        child: const Text('No Safe Zones Configured'),
                      );
                    }

                    return Column(
                      children: zones.map((zone) {
                        bool isInside =
                            zone['name'].toString().toLowerCase().contains(
                              'school',
                            ) ||
                            zone['name'].toString().toLowerCase().contains(
                              'home',
                            );

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isInside
                                ? ShieldColors.safeZoneGreen.withValues(
                                    alpha: 0.1,
                                  )
                                : Colors.white,
                            borderRadius: ShieldDesign.roundedTwelve,
                            border: Border.all(
                              color: isInside
                                  ? ShieldColors.safeZoneGreen
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: ListTile(
                            leading: Icon(
                              Icons.location_on,
                              color: isInside
                                  ? ShieldColors.safeZoneGreen
                                  : Colors.grey,
                            ),
                            title: Text(
                              zone['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: ShieldColors.textBody,
                              ),
                            ),
                            subtitle: Text('Radius: ${zone['radius_meters']}m'),
                            trailing: isInside
                                ? const Chip(
                                    label: Text('ACTIVE'),
                                    backgroundColor: ShieldColors.safeZoneGreen,
                                    labelStyle: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  )
                                : const Text(
                                    'Away',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      // Fetch real GPS
                      double lat = 0.0;
                      double lng = 0.0;
                      bool gpsSuccess = false;
                      try {
                        LocationPermission perm =
                            await Geolocator.checkPermission();
                        print(perm);
                        if (perm == LocationPermission.denied) {
                          perm = await Geolocator.requestPermission();
                          print(perm);
                          print("adds");
                        } else if (perm == LocationPermission.deniedForever) {
                          print("openLocationSettings");

                          await Geolocator.openLocationSettings();
                        }
                        if (perm != LocationPermission.denied &&
                            perm != LocationPermission.deniedForever) {
                          final pos = await Geolocator.getCurrentPosition(
                            desiredAccuracy: LocationAccuracy.medium,
                            timeLimit: const Duration(seconds: 8),
                          );
                          lat = pos.latitude;
                          lng = pos.longitude;
                          gpsSuccess = true;
                        }
                      } catch (e) {
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
                        } catch (_) {}
                      }
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

                      await safetyRepo.submitPulse(
                        familyId: profile.familyId,
                        latitude: lat,
                        longitude: lng,
                        batteryLevel: level,
                        type: 'check_in',
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              gpsSuccess
                                  ? 'Checked in successfully!'
                                  : 'Checked in (GPS unavailable)',
                            ),
                            backgroundColor: gpsSuccess
                                ? ShieldColors.safeZoneGreen
                                : Colors.orange,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.check_circle_outline, size: 24),
                    label: const Text(
                      'Check In',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ShieldColors.activeTeal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: ShieldDesign.roundedTwelve,
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
                        backgroundColor: Colors.transparent,
                        builder: (_) => const FamilyChatScreen(),
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_outline, size: 24),
                    label: const Text(
                      'Message Family',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: ShieldColors.textBody,
                      shape: RoundedRectangleBorder(
                        borderRadius: ShieldDesign.roundedTwelve,
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Family Status — BUG FIX: show name instead of role
                Text(
                  'FAMILY STATUS',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: safetyRepo.streamActiveMembers(profile.familyId),
                  builder: (context, memberSnapshot) {
                    if (memberSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final members = memberSnapshot.data ?? [];
                    final parents = members
                        .where(
                          (m) =>
                              m['role'] == 'leader' || m['role'] == 'monitor',
                        )
                        .toList();

                    if (parents.isEmpty) {
                      return const Text('No parents online.');
                    }

                    return Column(
                      children: parents
                          .map(
                            (member) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: ParentLocationRow(
                                // FIX: Display name, not role
                                name: member['full_name'] ?? 'Family Member',
                                location: 'Active on Shield',
                                // Assuming 'memberLoc' was intended to be this static string or derived elsewhere
                                isOnline: true,
                                // Assuming 'isOnline' was intended to be this static boolean or derived elsewhere
                                avatarUrl: member['avatar_url'] as String?,
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 100),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error: $e')),
        ),
      ),
      // Elder-portal style anchored bottom bar
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
              const SizedBox(width: 8),
              // MENU button (command center)
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 60,
                  child: ElevatedButton(
                    onPressed: () {
                      print("dss");
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
              const SizedBox(width: 8),
              // Profile
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
    );
  }
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
