import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/tools_repository.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/data/safety_repository.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/navigation/shield_router.dart';
import 'package:well_check_v3/features/safety/widgets/breathing_shield.dart';
class MedicationWizardScreen extends ConsumerStatefulWidget {
  const MedicationWizardScreen({super.key});

  @override
  ConsumerState<MedicationWizardScreen> createState() =>
      _MedicationWizardScreenState();
}

class _MedicationWizardScreenState
    extends ConsumerState<MedicationWizardScreen> {
  final _medNameController = TextEditingController();
  final _dosageController = TextEditingController();

  TimeOfDay _selectedTime = const TimeOfDay(hour: 8, minute: 0);
  int _inventoryCount = 30;
  int _refillAlertThreshold = 5;
  bool _isSaving = false;

  // IDs fetched dynamically from profile on save

  Future<void> _handleSave() async {
    if (_medNameController.text.isEmpty || _dosageController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill out all fields.'),
          backgroundColor: ShieldColors.urgentRed,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('Profile not found. Please log in.');

      final formattedTime =
          '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}:00';

      await ref
          .read(toolsRepositoryProvider)
          .addMedication(
            familyId: profile.familyId,
            assignedUserId: profile.userId,
            name: _medNameController.text.trim(),
            dosage: _dosageController.text.trim(),
            scheduleTime: formattedTime,
            inventoryCount: _inventoryCount,
          );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save medication: $e'),
            backgroundColor: ShieldColors.urgentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Medication'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _handleSave,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(),
                  )
                : const Text(
                    'SAVE',
                    style: TextStyle(
                      color: ShieldColors.activeTeal,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Medication Details',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: ShieldColors.activeTeal,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _medNameController,
              decoration: const InputDecoration(
                labelText: 'Medication Name (e.g. Lisinopril)',
                prefixIcon: Icon(Icons.medical_services_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _dosageController,
              decoration: const InputDecoration(
                labelText: 'Dosage (e.g. 10mg)',
                prefixIcon: Icon(Icons.vaccines_outlined),
              ),
            ),
            const SizedBox(height: 32),

            const Text(
              'Schedule',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: ShieldColors.activeTeal,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time),
              title: const Text('Time of Day'),
              trailing: Text(
                _selectedTime.format(context),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: _selectedTime,
                );
                if (time != null) {
                  setState(() => _selectedTime = time);
                }
              },
            ),
            const Divider(),

            const SizedBox(height: 32),
            const Text(
              'Inventory Tracking',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: ShieldColors.activeTeal,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Current Pill Count'),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => setState(
                        () => _inventoryCount = (_inventoryCount > 0)
                            ? _inventoryCount - 1
                            : 0,
                      ),
                    ),
                    Text(
                      '$_inventoryCount',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setState(() => _inventoryCount++),
                    ),
                  ],
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Refill Alert Threshold'),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => setState(
                        () =>
                            _refillAlertThreshold = (_refillAlertThreshold > 0)
                            ? _refillAlertThreshold - 1
                            : 0,
                      ),
                    ),
                    Text(
                      '$_refillAlertThreshold',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setState(() => _refillAlertThreshold++),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
