import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/data/safety_repository.dart';
import 'package:well_check_v3/core/data/safe_zone_provider.dart';

class CampusWatchSheet extends ConsumerStatefulWidget {
  final bool fromLeader;

  const CampusWatchSheet({super.key, this.fromLeader = false});

  @override
  ConsumerState<CampusWatchSheet> createState() => _CampusWatchSheetState();
}

class _CampusWatchSheetState extends ConsumerState<CampusWatchSheet> {
  bool _isLoadingMembers = true;
  List<Map<String, dynamic>> familyMembersAssign = [];
  List<Map<String, dynamic>> _familyMembers = [];

  // Per-user config: userId -> config map
  Map<String, Map<String, dynamic>> _memberConfigs = {};
  String? _expandedUserId;
  String? _selectedUserId;
  String? _selectedUserName;

  @override
  void initState() {
    super.initState();
    _fetchFamilyMembers();
    _fetchMembers();
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
          familyMembersAssign = List<Map<String, dynamic>>.from(res);
          _isLoadingMembers = false;
          if (familyMembersAssign.isNotEmpty) {
            final me = familyMembersAssign
                .where((m) => m['user_id'] == profile.userId)
                .toList();
            _selectedUserId = me.isNotEmpty
                ? me.first['user_id']
                : familyMembersAssign.first['user_id'];
            _selectedUserName = me.isNotEmpty
                ? me.first['profiles']['full_name']
                : familyMembersAssign.first['profile']['user_id'];
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching members: $e');
      if (mounted) setState(() => _isLoadingMembers = false);
    }
  }

  Future<void> _fetchMembers() async {
    try {
      print("_familyMembers");
      final profile = await ref.read(currentUserProfileProvider.future);
      ref.invalidate(safetyRepositoryProvider);
      if (profile == null) return;

      final res = await Supabase.instance.client
          .from('family_members')
          .select('user_id, role, profiles(full_name)')
          .eq('family_id', profile.familyId);

      // Fetch existing configs
      final configs = await Supabase.instance.client
          .from('campus_watch_config')
          .select()
          .eq('family_id', profile.familyId);

      final configMap = <String, Map<String, dynamic>>{};
      for (final c in configs) {
        configMap[c['user_id'] as String] = c;
      }

      if (mounted) {
        setState(() {
          _familyMembers = List<Map<String, dynamic>>.from(res);
          _memberConfigs = configMap;
          _isLoadingMembers = false;
        });
      }
    } catch (e) {
      print(e.toString());
      print("_familyMembers11");

      if (mounted) setState(() => _isLoadingMembers = false);
    }
  }

  Map<String, dynamic> _getConfig(String userId) {
    return _memberConfigs[userId] ??
        {
          'is_monitored': true,
          'notify_zone_entry': true,
          'notify_zone_exit': true,
          'notify_campus_alert': true,
          'notify_check_in': true,
        };
  }

  Future<void> _updateConfig(String userId, String field, bool value) async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;

      // Update local state immediately for responsiveness
      setState(() {
        _memberConfigs[userId] = {..._getConfig(userId), field: value};
      });

      // Upsert to Supabase
      await Supabase.instance.client.from('campus_watch_config').upsert({
        'family_id': profile.familyId,
        'user_id': userId,
        ..._getConfig(userId),
        field: value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'family_id,user_id');
    } catch (e) {
      debugPrint('[CampusWatch] Config update error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  final TextEditingController _campusNameController = TextEditingController();
  final TextEditingController _campusAddressController =
      TextEditingController();

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

  Future<void> _showAddCampusDialog() async {
    _campusNameController.clear();
    _campusAddressController.clear();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: ShieldDesign.roundedTwelve,
            ),
            title: const Row(
              children: [
                Icon(Icons.school, color: ShieldColors.activeTeal),
                SizedBox(width: 8),
                Text('Add Campus'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sectionLabel('Assign To'),
                if (_isLoadingMembers)
                  const Center(child: CircularProgressIndicator()),
                if (familyMembersAssign.isEmpty)
                  Text("No Family member")
                else if (familyMembersAssign.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: _selectedUserId,

                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: ShieldDesign.roundedTwelve,
                      ),
                      prefixIcon: const Icon(Icons.person),
                    ),
                    items: familyMembersAssign.map((m) {
                      final name = m['profiles']?['full_name'] ?? 'Unknown';

                      final role = m['role'];

                      return DropdownMenuItem<String>(
                        value: m['user_id'] as String,
                        child: Text(
                          '$name ($role)',
                          style: TextStyle(fontSize: 15),
                        ),
                      );
                    }).toList(),

                    onChanged: (val) {
                      final selectedMember = familyMembersAssign.firstWhere(
                        (m) => m['user_id'] == val,
                      );

                      setDialogState(() {
                        _selectedUserId = val;

                        _selectedUserName =
                            selectedMember['profiles']?['full_name'] ??
                            'Unknown';
                      });
                    },

                    validator: (val) => val == null ? 'Required' : null,
                  ),
                SizedBox(height: 20),
                TextField(
                  controller: _campusNameController,
                  decoration: InputDecoration(
                    labelText: 'Campus Name',
                    hintText: 'e.g. Lincoln High School',
                    prefixIcon: const Icon(Icons.school_outlined),
                    border: OutlineInputBorder(
                      borderRadius: ShieldDesign.roundedTwelve,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _campusAddressController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Campus Address',
                    hintText: 'e.g. 123 Main St, City, State',
                    prefixIcon: const Icon(Icons.place),
                    border: OutlineInputBorder(
                      borderRadius: ShieldDesign.roundedTwelve,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This will create a geo-fence zone around the campus to track student proximity.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ShieldColors.activeTeal,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Add Campus'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true && _campusNameController.text.trim().isNotEmpty) {
      await _saveCampusZone();
    }
  }

  Future<void> _saveCampusZone() async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;

      final name = _campusNameController.text.trim();
      final address = _campusAddressController.text.trim();

      await Supabase.instance.client.from('locations_safe_zones').insert({
        'family_id': profile.familyId,
        'name': name,
        'assigned_user_id': _selectedUserId,

        'assigned_user_name': _selectedUserName,
        'latitude': 0.0,
        'longitude': 0.0,
        'radius_meters': 300,
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
      await Supabase.instance.client.from('well_events').insert({
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'event_type': 'campus_added',
        'title': 'Campus Zone Added',
        'battery_level': level,

        'description':
            '${profile.fullName}- Created campus zone: $name${address.isNotEmpty ? ' at $address' : ''}',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Campus "$name" added! Configure location in Safe Zones.',
            ),
            backgroundColor: ShieldColors.safeZoneGreen,
          ),
        );
      }
    } catch (e) {
      debugPrint('[CampusWatch] Error saving campus: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding campus: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _campusNameController.dispose();
    _campusAddressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final zonesAsync = ref.watch(familySafeZonesProvider);

    return Container(
      decoration: const BoxDecoration(
        color: ShieldColors.backgroundWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Campus Watch',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Geo-fence activity tracker',
                    style: TextStyle(
                      color: ShieldColors.activeTeal,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              Spacer(),
              if (widget.fromLeader == true)
                IconButton(
                  onPressed: _showAddCampusDialog,
                  icon: const Icon(
                    Icons.add_location_alt,
                    color: ShieldColors.activeTeal,
                    size: 28,
                  ),
                  tooltip: 'Add Campus',
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
                  child: const Icon(Icons.close, color: Colors.black, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Safe Zones summary
          zonesAsync.when(
            data: (zones) {
              if (zones.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: ShieldDesign.roundedTwelve,
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber),
                      SizedBox(width: 12),

                      Expanded(
                        child: Text(
                          widget.fromLeader == true
                              ? 'No safe zones configured yet. Create zones like "School" or "Home" from the Safe Zones menu to enable campus tracking.'
                              : 'No safe zones configured yet.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF007F80), Color(0xFF059669)],
                  ),
                  borderRadius: ShieldDesign.roundedTwelve,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${zones.length} Zone${zones.length > 1 ? "s" : ""} Active',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            zones.map((z) => z.zoneName).join(', '),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // Family members with toggles
          if (_isLoadingMembers)
            const Center(child: CircularProgressIndicator())
          else if (_familyMembers.isNotEmpty) ...[
            const Text(
              'Member Monitoring',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap a member to configure what you want to track',
              style: TextStyle(fontSize: 12, color: ShieldColors.textLabel),
            ),
            const SizedBox(height: 8),
            ..._familyMembers.map((member) {
              final userId = member['user_id'] as String;
              final name =
                  member['profiles']?['full_name'] ??
                  member['profiles']?['email'] ??
                  'Member';
              final role = member['role'] as String;
              final config = _getConfig(userId);
              final isMonitored = config['is_monitored'] as bool? ?? true;
              final isExpanded = _expandedUserId == userId;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: ShieldDesign.roundedTwelve,
                  side: isExpanded
                      ? const BorderSide(
                          color: ShieldColors.activeTeal,
                          width: 1.5,
                        )
                      : BorderSide.none,
                ),
                child: Column(
                  children: [
                    ListTile(
                      onTap: () {
                        setState(() {
                          _expandedUserId = isExpanded ? null : userId;
                        });
                      },
                      leading: CircleAvatar(
                        backgroundColor: isMonitored
                            ? ShieldColors.activeTeal.withValues(alpha: 0.15)
                            : Colors.grey.shade200,
                        child: Icon(
                          Icons.person,
                          color: isMonitored
                              ? ShieldColors.activeTeal
                              : Colors.grey,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        role.toUpperCase(),
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isMonitored
                                  ? ShieldColors.safeZoneGreen.withValues(
                                      alpha: 0.12,
                                    )
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isMonitored ? 'Active' : 'Off',
                              style: TextStyle(
                                color: isMonitored
                                    ? ShieldColors.safeZoneGreen
                                    : Colors.grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            isExpanded ? Icons.expand_less : Icons.expand_more,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                    ),
                    if (isExpanded)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                        ),
                        child: Column(
                          children: [
                            const Divider(height: 1),
                            _ToggleRow(
                              icon: Icons.shield,
                              title: 'Monitor',
                              subtitle: 'Enable/disable all tracking',
                              value: isMonitored,
                              onChanged: (val) =>
                                  _updateConfig(userId, 'is_monitored', val),
                            ),
                            _ToggleRow(
                              icon: Icons.login,
                              title: 'Zone Entry',
                              subtitle: 'Alert when entering a safe zone',
                              value:
                                  config['notify_zone_entry'] as bool? ?? true,
                              enabled: isMonitored,
                              onChanged: (val) => _updateConfig(
                                userId,
                                'notify_zone_entry',
                                val,
                              ),
                            ),
                            _ToggleRow(
                              icon: Icons.logout,
                              title: 'Zone Exit',
                              subtitle: 'Alert when leaving a safe zone',
                              value:
                                  config['notify_zone_exit'] as bool? ?? true,
                              enabled: isMonitored,
                              onChanged: (val) => _updateConfig(
                                userId,
                                'notify_zone_exit',
                                val,
                              ),
                            ),
                            _ToggleRow(
                              icon: Icons.campaign,
                              title: 'Campus Alerts',
                              subtitle: 'Receive campus-wide alerts',
                              value:
                                  config['notify_campus_alert'] as bool? ??
                                  true,
                              enabled: isMonitored,
                              onChanged: (val) => _updateConfig(
                                userId,
                                'notify_campus_alert',
                                val,
                              ),
                            ),
                            _ToggleRow(
                              icon: Icons.how_to_reg,
                              title: 'Check-ins',
                              subtitle: 'Track manual check-in events',
                              value: config['notify_check_in'] as bool? ?? true,
                              enabled: isMonitored,
                              onChanged: (val) =>
                                  _updateConfig(userId, 'notify_check_in', val),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],

          const SizedBox(height: 16),
          const Text(
            'Recent Zone Activity',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),

          // Campus/zone events from well_events — filtered by config
          Expanded(
            child: profileAsync.when(
              data: (profile) {
                if (profile == null) {
                  return const Center(child: Text('No profile.'));
                }
                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: ref
                      .read(safetyRepositoryProvider)
                      .streamFamilyEvents(profile.familyId),
                  builder: (context, snapshot) {
                    print(snapshot.data);
                    final allEvents = (snapshot.data ?? [])
                        .where(
                          (e) =>
                              e['event_type'] == 'campus_alert' ||
                              e['event_type'] == 'safe_zone_enter' ||
                              e['event_type'] == 'safe_zone_exit' ||
                              e['event_type'] == 'safe_zone_created' ||
                              e['event_type'] == 'check_in',
                        )
                        .toList();
                    print("allEvents");
                    print(allEvents);
                    // Filter based on per-user config
                    final events = allEvents
                        .where((e) {
                          final eventUserId = e['user_id'] as String?;
                          if (eventUserId == null) return true;
                          final config = _getConfig(eventUserId);
                          if (config['is_monitored'] == false) return false;

                          final type = e['event_type'] as String;
                          if (type == 'safe_zone_enter' &&
                              config['notify_zone_entry'] == false)
                            return false;
                          if (type == 'safe_zone_exit' &&
                              config['notify_zone_exit'] == false)
                            return false;
                          if (type == 'campus_alert' &&
                              config['notify_campus_alert'] == false)
                            return false;
                          if (type == 'check_in' &&
                              config['notify_check_in'] == false)
                            return false;

                          return true;
                        })
                        .take(15)
                        .toList();

                    if (events.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_off,
                              size: 48,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No zone activity yet.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                            const Text(
                              'Check-ins and zone entries/exits\nwill appear here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: events.length,
                      itemBuilder: (context, index) {
                        final evt = events[index];
                        final type = evt['event_type'] as String;
                        final userName = evt['user_name'] as String?;
                        final desc =
                            evt['description'] as String? ??
                            evt['title'] as String? ??
                            type;
                        final createdAt = evt['created_at'] as String?;
                        String timeStr = '';
                        if (createdAt != null) {
                          try {
                            final dt = DateTime.parse(createdAt);
                            final diff = DateTime.now().difference(dt);
                            if (diff.inMinutes < 60) {
                              timeStr = '${diff.inMinutes}m ago';
                            } else if (diff.inHours < 24) {
                              timeStr = '${diff.inHours}h ago';
                            } else {
                              timeStr = DateFormat.MMMd().format(dt);
                            }
                          } catch (_) {}
                        }

                        IconData icon = Icons.location_on;
                        Color color = ShieldColors.activeTeal;
                        if (type == 'safe_zone_enter') {
                          icon = Icons.verified_user;
                          color = ShieldColors.safeZoneGreen;
                        } else if (type == 'safe_zone_exit') {
                          icon = Icons.warning_amber;
                          color = Colors.orange;
                        } else if (type == 'campus_alert') {
                          icon = Icons.campaign;
                          color = ShieldColors.alertRed;
                        } else if (type == 'check_in') {
                          icon = Icons.how_to_reg;
                          color = ShieldColors.safeZoneGreen;
                        }

                        return ListTile(
                          leading: Icon(icon, color: color),
                          // title: Row(
                          //   children: [
                          //     if(userName!=null&&userName!='')
                          //       Expanded(
                          //         child: Text('$userName-'??"", style: TextStyle(
                          //           fontWeight: FontWeight.bold,
                          //           color: Colors.black,
                          //           fontSize: 12,
                          //         ),),
                          //       ),
                          //     Expanded(
                          //       child: Text(
                          //         desc,
                          //         style: const TextStyle(
                          //           fontWeight: FontWeight.w500,
                          //           fontSize: 13,
                          //         ),
                          //         maxLines: 2,
                          //         overflow: TextOverflow.ellipsis,
                          //       ),
                          //     ),
                          //   ],
                          // ),
                          title: RichText(
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              children: [
                                if (userName != null && userName != '')
                                  TextSpan(
                                    text: '$userName - ',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 12,
                                    ),
                                  ),

                                TextSpan(
                                  text: desc,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: ShieldColors.activeTeal,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: Text(
                            timeStr,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SwitchListTile(
        secondary: Icon(
          icon,
          color: enabled ? ShieldColors.activeTeal : Colors.grey.shade400,
          size: 20,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: enabled ? ShieldColors.textBody : Colors.grey,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 11,
            color: enabled ? ShieldColors.textLabel : Colors.grey.shade400,
          ),
        ),
        value: value && enabled,
        activeThumbColor: ShieldColors.activeTeal,
        onChanged: enabled ? onChanged : null,
        dense: true,
      ),
    );
  }
}
