import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/data/health_repository.dart';
import 'package:well_check_v3/core/data/medication_provider.dart';
import 'package:well_check_v3/core/notifications/medication_notification_service.dart';
import 'package:geolocator/geolocator.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final phoneNumber = TextEditingController();
  bool _isLoading = false;
  final profileNode = FocusNode();
  final ageNode = FocusNode();
  final phoneNumberNode = FocusNode();

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final phone = phoneNumber.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your name'),
          backgroundColor: ShieldColors.urgentRed,
        ),
      );
      return;
    } if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your phone number'),
          backgroundColor: ShieldColors.urgentRed,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      profileNode.unfocus();
      ageNode.unfocus();
      phoneNumberNode.unfocus();
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;

      if (userId == null) throw Exception('No user logged in');

      // Update the profiles table
      await supabase
          .from('profiles')
          .update({
            'full_name': name,
        "phone":phone
            // If your database has an age column, write it here:
            // 'age': int.tryParse(_ageController.text) ?? 0,
          })
          .eq('id', userId);

      // Invalidate to fetch fresh names
      ref.invalidate(currentUserProfileProvider);

      // Request Location Permissions (Issue #5: GPS pulse not sending)
      try {
        LocationPermission perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.whileInUse) {
          await Geolocator.requestPermission();
        }
        debugPrint('[ProfileSetup] Location permissions requested');
      } catch (e) {
        debugPrint('[ProfileSetup] Location permission request failed: $e');
      }

      // Request HealthKit permissions (Issue #8: Apple Watch pulse)
      try {
        final healthRepo = ref.read(healthRepositoryProvider);
        await healthRepo.requestPermissions();
        debugPrint('[ProfileSetup] HealthKit permissions requested');
      } catch (e) {
        debugPrint('[ProfileSetup] HealthKit permission request failed: $e');
      }

      // Schedule medication notifications for any existing medications
      try {
        final profile = await ref.read(currentUserProfileProvider.future);
        if (profile != null) {
          final allMeds = await Supabase.instance.client
              .from('medications')
              .select()
              .eq('family_id', profile.familyId)
              .eq('is_active', true);
          final medList = allMeds.map((e) => Medication.fromJson(e)).toList();
          if (medList.isNotEmpty) {
            await MedicationNotificationService.scheduleForMedications(medList);
          }
        }
      } catch (e) {
        debugPrint('[ProfileSetup] Medication scheduling failed: $e');
      }
      profileNode.unfocus();
      ageNode.unfocus();
      phoneNumberNode.unfocus();

      if (mounted) {
        context.go('/dashboard');
      }
    } catch (e) {
      debugPrint('Profile Update Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile.'),
            backgroundColor: ShieldColors.urgentRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: Padding(
        padding: MediaQuery.viewInsetsOf(context),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: SafeArea(child:                 ElevatedButton(
            onPressed: _isLoading ? null : _saveProfile,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
            child: _isLoading
                ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            )
                : const Text(
              'SAVE & ENTER DASHBOARD',
              style: TextStyle(fontSize: 16),
            ),
          ),
          ),
        ),
      ),
      backgroundColor: ShieldColors.backgroundWhite,
      body: SingleChildScrollView(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.person_pin,
                  size: 80,
                  color: ShieldColors.activeTeal,
                ),
                const SizedBox(height: 24),
                Text(
                  'Complete Your Profile',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: ShieldColors.textBody,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'So your family shield knows exactly who you are.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ShieldColors.textLabel),
                ),
                const SizedBox(height: 48),
                TextField(
                  focusNode: profileNode,
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(
                      borderRadius: ShieldDesign.roundedTwelve,
                    ),
                  ),
                ),
                const SizedBox(height: 24), TextField(
                  focusNode: phoneNumberNode,
                  controller: phoneNumber,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(
                      borderRadius: ShieldDesign.roundedTwelve,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  focusNode: ageNode,
                  controller: _ageController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Age (Optional)',
                    border: OutlineInputBorder(
                      borderRadius: ShieldDesign.roundedTwelve,
                    ),
                  ),
                ),
               // const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
