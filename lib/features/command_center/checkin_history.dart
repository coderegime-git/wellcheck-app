import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/user_profile_provider.dart';

final checkInHistoryProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      familyId,
    ) async {
      final supabase = Supabase.instance.client;
      // await generateMissedCheckIns(familyId);
      // Check-ins
      final checkIns = await supabase
          .from('check_ins')
          .select()
          .eq('family_id', familyId)
          .order('created_at', ascending: false);

      // Profiles
      final profiles = await supabase.from('profiles').select('id, full_name');

      final profileMap = {
        for (final p in profiles)
          p['id'].toString(): p['full_name'] ?? 'Unknown',
      };

      return List<Map<String, dynamic>>.from(checkIns).map((item) {
        return {
          ...item,
          'profiles': {
            'id': item['user_id'],
            'full_name': profileMap[item['user_id'].toString()] ?? 'Unknown',
          },
        };
      }).toList();
    });

Future<void> generateMissedCheckIns(String familyId) async {
  final now = DateTime.now().toUtc();

  final schedules = await Supabase.instance.client
      .from('checkin_schedules')
      .select()
      .eq('family_id', familyId)
      .eq('status', 'pending');

  for (final schedule in schedules) {
    final scheduledAt = DateTime.parse(schedule['scheduled_at']);

    if (scheduledAt.isAfter(now)) continue;
    print("Schedule: ${schedule['id']}");
    print("Status: ${schedule['status']}");
    print("ScheduledAt: ${schedule['scheduled_at']}");
    // Insert missed history
    await Supabase.instance.client.from('check_ins').insert({
      'family_id': familyId,
      'user_id': schedule['assigned_user_id'],
      'status_message': 'Missed check-in',
      'created_at': scheduledAt.toIso8601String(),
    });

    // Mark schedule as missed
    await Supabase.instance.client
        .from('checkin_schedules')
        .update({'status': 'missed'})
        .eq('id', schedule['id']);
  }
}

class CheckInHistoryScreen extends ConsumerWidget {
  const CheckInHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider);

    if (!profile.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    ref.invalidate(checkInHistoryProvider(profile.value!.familyId));
    final history = ref.watch(checkInHistoryProvider(profile.value!.familyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Check-In History')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),

        error: (e, _) {
          print(e.toString());
          return Center(child: Text(e.toString()));
        },

        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('No check-in history'));
          }

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, index) {
              final item = items[index];
              print("item111");
              print(item);
              final userName = item['profiles']['full_name'] ?? 'Unknown User';

              final createdAt = DateTime.parse(item['created_at']).toLocal();

              final status = item['status_message'] ?? 'Unknown';

              Color statusColor;

              if (status.toLowerCase().contains('missed')) {
                statusColor = Colors.red;
              } else if (status.toLowerCase().contains('manual')) {
                statusColor = Colors.orange;
              } else {
                statusColor = Colors.green;
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: statusColor,
                    child: const Icon(Icons.check_circle, color: Colors.white),
                  ),

                  title: Text(
                    userName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),

                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(status),
                      Text(
                        DateFormat('dd MMM yyyy • hh:mm a').format(createdAt),
                      ),
                    ],
                  ),

                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.toLowerCase().contains('missed')
                          ? 'Missed'
                          : 'Completed',
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
