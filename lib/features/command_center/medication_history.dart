import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';

import '../../core/data/medication_provider.dart';
import '../../core/data/user_profile_provider.dart';

class MedicationHistoryScreen extends ConsumerStatefulWidget {
  bool? fromLeader = false;

  MedicationHistoryScreen({super.key, this.fromLeader});

  @override
  ConsumerState<MedicationHistoryScreen> createState() =>
      _MedicationHistoryScreenState();
}

class _MedicationHistoryScreenState
    extends ConsumerState<MedicationHistoryScreen> {
  @override
  initState() {
    super.initState();
    generateMissedLogs();
    // loadData();
  }

  Future<void> generateMissedLogs() async {
    final profile = await ref.read(currentUserProfileProvider.future);

    final meds = await Supabase.instance.client
        .from('medications')
        .select()
        .eq('family_id', profile!.familyId)
        .eq('is_active', true);

    final now = DateTime.now();

    for (final med in meds) {
      final assignedTo = med['assigned_to'];

      // Example: ["08:00","21:00"]
      final times = List<String>.from(med['schedule_times'] ?? []);

      for (final time in times) {
        final split = time.split(':');

        final scheduledTime = DateTime(
          now.year,
          now.month,
          now.day,
          int.parse(split[0]),
          int.parse(split[1]),
        );

        // only if time already passed
        if (scheduledTime.isBefore(now)) {
          // check whether user already took it
          final existing = await Supabase.instance.client
              .from('dose_logs')
              .select()
              .eq('medication_id', med['id'])
              .eq('user_id', assignedTo)
              .gte(
                'scheduled_at',
                DateTime(now.year, now.month, now.day).toIso8601String(),
              )
              .limit(1);

          if (existing.isEmpty) {
            await Supabase.instance.client.from('dose_logs').insert({
              'medication_id': med['id'],
              'user_id': assignedTo,
              'family_id': profile.familyId,
              'scheduled_at': scheduledTime.toIso8601String(),
              'status': 'missed',
            });
          }
        }
      }
    }
  }

  DateTime parseAsUtc(String raw) {
    // if there's no Z or offset already, treat it as UTC explicitly
    final hasOffset =
        raw.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(raw);
    final iso = hasOffset ? raw : '${raw}Z';
    return DateTime.parse(iso).toLocal();
  }

  @override
  Widget build(BuildContext context) {
    final historyData = ref.invalidate(allMedicationHistoryProvider);
    final profile = ref.watch(currentUserProfileProvider);

    if (!profile.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final history = ref.watch(
      allMedicationHistoryProvider(profile.value!.familyId),
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: ShieldColors.backgroundWhite,
        titleSpacing: 6,
        surfaceTintColor: Colors.grey.shade200,
        shadowColor: Colors.grey.shade200,
        title: const Text('Medication Log History'),
      ),

      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),

        error: (e, _) {
          return Center(child: Text(e.toString()));
        },

        data: (items) {
          print(items);
          if (items.isEmpty) {
            return const Center(child: Text('No medication logs'));
          }
          final currentUserId = profile.value!.userId;

          final filteredItems = widget.fromLeader == true
              ? items
              : items.where((item) {
                  final profileData = item['profiles'];
                  return profileData != null &&
                      profileData['id'] == currentUserId;
                }).toList();

          if (filteredItems.isEmpty) {
            return const Center(child: Text('No medication logs'));
          }

          return ListView.builder(
            itemCount: filteredItems.length,
            itemBuilder: (_, index) {
              final item = filteredItems[index];

              final medication = item['medications'];
              final profileData = item['profiles'];
              final status = item['status'] ?? '';
              print(item['scheduled_at']);
              print('RAW scheduled_at: ${item['scheduled_at']}');
              print(
                'RAW scheduled_at TYPE: ${item['scheduled_at'].runtimeType}',
              );
              final date = DateTime.parse(item['scheduled_at']).toLocal();
              print('PARSED: $date');
              //final date = DateTime.parse(item['scheduled_at']).toLocal();
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),

                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.purple,

                    child: Icon(Icons.medication, color: Colors.white),
                  ),

                  title: Text(medication['medication_name'] ?? ''),

                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Name: ${profileData['full_name']}"),

                      Text("Dose: ${medication['dosage'] ?? ''}"),

                      Text(
                        status == 'missed'
                            ? 'Missed at: ${DateFormat('dd MMM yyyy • hh:mm a').format(date)}'
                            : 'Taken at: ${DateFormat('dd MMM yyyy • hh:mm a').format(date)}',
                      ),
                    ],
                  ),

                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: status == 'missed'
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: status == 'missed' ? Colors.red : Colors.green,
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
