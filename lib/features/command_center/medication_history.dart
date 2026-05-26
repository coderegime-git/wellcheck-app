import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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

    // loadData();
  }

  loadData() {
    final history = ref.invalidate(allMedicationHistoryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final historyd = ref.invalidate(allMedicationHistoryProvider);
    final history = ref.watch(allMedicationHistoryProvider);
    final profile = ref.watch(currentUserProfileProvider);
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
          print(e.toString());
          return Center(child: Text(e.toString()));
        },

        data: (items) {
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

              final date = DateTime.parse(item['taken_at']).toLocal();

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

                      Text(DateFormat('dd MMM yyyy • hh:mm a').format(date)),
                    ],
                  ),

                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(item['status']),
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
