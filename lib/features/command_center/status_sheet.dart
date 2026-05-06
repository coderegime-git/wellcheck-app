import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';

class StatusSheet extends ConsumerStatefulWidget {
  const StatusSheet({super.key});

  @override
  ConsumerState<StatusSheet> createState() => _StatusSheetState();
}

class _StatusSheetState extends ConsumerState<StatusSheet> {
  List<Map<String, dynamic>> _members = [];
  Map<String, Map<String, dynamic>?> _latestEvents = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchStatuses();
  }

  Future<void> _fetchStatuses() async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;

      final res = await Supabase.instance.client
          .from('family_members')
          .select('user_id, role, profiles(full_name)')
          .eq('family_id', profile.familyId);

      final memberList = List<Map<String, dynamic>>.from(res);

      // Fetch latest event per member for battery + last seen
      final eventMap = <String, Map<String, dynamic>?>{};
      for (final member in memberList) {
        final userId = member['user_id'] as String;
        try {
          final eventRes = await Supabase.instance.client
              .from('well_events')
              .select()
              .eq('user_id', userId)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          eventMap[userId] = eventRes;
        } catch (_) {
          eventMap[userId] = null;
        }
      }

      if (mounted) {
        setState(() {
          _members = memberList;
          _members.sort((a, b) {
            final valA = a['profiles']?['full_name'] ?? 'Unknown';
            final valB = b['profiles']?['full_name'] ?? 'Unknown';
            return valA.compareTo(valB);
          });
          _latestEvents = eventMap;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildStatusRow(
    String name,
    String role,
    String statusLine,
    IconData icon,
    Color dotColor,
    String? battery,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.all(0),
      leading: CircleAvatar(
        backgroundColor: ShieldColors.activeTeal.withValues(alpha: 0.1),
        child: Icon(icon, color: ShieldColors.activeTeal),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(statusLine, style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (battery != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.battery_std,
                    size: 14,
                    color:
                        int.tryParse(battery) != null && int.parse(battery) < 25
                        ? Colors.red
                        : Colors.green,
                  ),
                  const SizedBox(width: 2),
                  Text('$battery%', style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          const SizedBox(width: 8),
          Icon(Icons.circle, size: 10, color: dotColor),
        ],
      ),
    );
  }

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
          Row(
            children: [
              Text(
                'Family Status Matrix',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
                  child: const Icon(Icons.close, color: Colors.black, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _members.length,
                    itemBuilder: (context, index) {
                      final contact = _members[index];
                      final profileData =
                          contact['profiles'] as Map<String, dynamic>?;
                      final name =
                          profileData?['full_name'] ??
                          profileData?['email'] ??
                          'Member';
                      final role = contact['role'] as String;
                      final userId = contact['user_id'] as String;
                      final latestEvent = _latestEvents[userId];

                      IconData icon = Icons.person;
                      if (role == 'leader') icon = Icons.admin_panel_settings;
                      if (role == 'elder' || role == 'senior')
                        icon = Icons.elderly;
                      if (role == 'student') icon = Icons.school;
                      if (role == 'pet') icon = Icons.pets;

                      // Derive status line from latest event
                      String statusLine;
                      Color dotColor;
                      String? battery;

                      if (latestEvent != null) {
                        final createdAt = latestEvent['created_at'] as String?;
                        final bat = latestEvent['battery_level'];
                        battery = bat?.toString();

                        if (createdAt != null) {
                          try {
                            final dt = DateTime.parse(createdAt);
                            final diff = DateTime.now().difference(dt);
                            if (diff.inMinutes < 10) {
                              statusLine = 'Online — Last sync just now';
                              dotColor = ShieldColors.safeZoneGreen;
                            } else if (diff.inHours < 1) {
                              statusLine = 'Online — ${diff.inMinutes}m ago';
                              dotColor = ShieldColors.safeZoneGreen;
                            } else if (diff.inHours < 24) {
                              statusLine =
                                  'Idle — Last seen ${diff.inHours}h ago';
                              dotColor = Colors.orange;
                            } else {
                              statusLine = 'Offline — ${diff.inDays}d ago';
                              dotColor = Colors.red;
                            }
                          } catch (_) {
                            statusLine = 'Unknown';
                            dotColor = Colors.grey;
                          }
                        } else {
                          statusLine = 'No timestamp data';
                          dotColor = Colors.grey;
                        }
                      } else {
                        statusLine = 'Waiting for first check-in…';
                        dotColor = Colors.grey;
                      }

                      return _buildStatusRow(
                        name,
                        role,
                        statusLine,
                        icon,
                        dotColor,
                        battery,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
