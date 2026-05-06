import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/data/safety_repository.dart';

class DrivingSheet extends ConsumerStatefulWidget {
  const DrivingSheet({super.key});

  @override
  ConsumerState<DrivingSheet> createState() => _DrivingSheetState();
}

class _DrivingSheetState extends ConsumerState<DrivingSheet> {
  bool _isLoadingMembers = true;
  List<Map<String, dynamic>> _familyMembers = [];
  String? _selectedUserId;

  @override
  void initState() {
    super.initState();
    _fetchMembers();
  }

  Future<void> _fetchMembers() async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;
      print("aaaaaa");

      final res = await Supabase.instance.client
          .from('family_members')
          .select('user_id, role, profiles(full_name)')
          .eq('family_id', profile.familyId);

      if (mounted) {
        setState(() {
          _familyMembers = List<Map<String, dynamic>>.from(res);
          _isLoadingMembers = false;
          if (_familyMembers.isNotEmpty) {
            _selectedUserId = _familyMembers.first['user_id'] as String;
          }
        });
      }
    } catch (e) {
      print(e.toString());
      print("drivvv");
      if (mounted) setState(() => _isLoadingMembers = false);
    }
  }

  String _getMemberName(String? userId) {
    if (userId == null) return 'Unknown';
    final m = _familyMembers.firstWhere(
      (m) => m['user_id'] == userId,
      orElse: () => {},
    );
    return m['profiles']?['full_name'] ?? 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);

    return Container(
      decoration: const BoxDecoration(
        color: ShieldColors.backgroundWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Driving Monitor',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Family driving activity feed',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              const Icon(Icons.speed, color: Colors.orange, size: 28),
            ],
          ),
          const SizedBox(height: 16),

          // Member filter
          if (_isLoadingMembers)
            const Center(child: CircularProgressIndicator())
          else if (_familyMembers.isNotEmpty)
            DropdownButtonFormField<String>(
              value: _selectedUserId,
              decoration: InputDecoration(
                labelText: 'Filter by Member',
                border: OutlineInputBorder(
                  borderRadius: ShieldDesign.roundedTwelve,
                ),
                prefixIcon: const Icon(Icons.person),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('All Members'),
                ),
                ..._familyMembers.map((m) {
                  final name = m['profiles']?['full_name'] ?? 'Unknown';
                  return DropdownMenuItem<String>(
                    value: m['user_id'] as String,
                    child: Text(name),
                  );
                }),
              ],
              onChanged: (val) => setState(() => _selectedUserId = val),
            ),

          const SizedBox(height: 16),
          const Text(
            'Recent Driving Events',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),

          // Real driving events from well_events
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
                    var events = (snapshot.data ?? [])
                        .where(
                          (e) =>
                              e['event_type'] == 'driving_alert' ||
                              e['event_type'] == 'driving' ||
                              e['event_type'] == 'speed_alert',
                        )
                        .toList();

                    // Filter by selected member
                    if (_selectedUserId != null) {
                      events = events
                          .where((e) => e['user_id'] == _selectedUserId)
                          .toList();
                    }

                    events = events.take(20).toList();

                    if (events.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.drive_eta,
                              size: 64,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No driving events recorded yet.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Speed alerts and driving activity\nwill appear here in real time.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: events.length,
                      itemBuilder: (context, index) {
                        final evt = events[index];
                        final desc =
                            evt['description'] as String? ??
                            evt['title'] as String? ??
                            'Driving event';
                        final userId = evt['user_id'] as String?;
                        final memberName = _getMemberName(userId);
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

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: ShieldDesign.roundedTwelve,
                          ),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.orange,
                              child: Icon(
                                Icons.directions_car,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              memberName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              desc,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              timeStr,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
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
