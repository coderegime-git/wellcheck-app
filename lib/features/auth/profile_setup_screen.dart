import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/data/health_repository.dart';
import 'package:well_check_v3/core/data/medication_provider.dart';
import 'package:well_check_v3/core/notifications/medication_notification_service.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/data/referral_repository.dart';
import '../../main.dart';
import '../../services/referral_service.dart';

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
  final _formKey = GlobalKey<FormState>();

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
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
    }
    if (phone.isEmpty) {
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
      final existingProfile = await supabase
          .from('profiles')
          .select('id, full_name')
          .eq('id', userId)
          .maybeSingle();

      final fullName = existingProfile?['full_name']?.toString().trim();
      final referralCode = 'WC-${userId.substring(0, 8).toUpperCase()}';

      final isOldUser = fullName != null && fullName.isNotEmpty;
      final isNewUser = !isOldUser;
      await supabase
          .from('profiles')
          .update({'referral_code': referralCode})
          .eq('id', userId);

      // Update the profiles table
      await supabase
          .from('profiles')
          .update({
            'full_name': name,
            "phone": phone,
            // If your database has an age column, write it here:
            'age': int.tryParse(_ageController.text) ?? 0,
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

        final granted = await healthRepo.requestPermissions();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('priv_heartbeat', granted);

        await prefs.setBool('is_new_user', true);

        debugPrint(
          '[ProfileSetup] HealthKit permissions ${granted ? "granted" : "denied"}',
        );
      } catch (e) {
        final prefs = await SharedPreferences.getInstance();

        await prefs.setBool('priv_heartbeat', false);

        debugPrint('[ProfileSetup] HealthKit permission request failed: $e');
      }

      // Schedule medication notifications for any existing medications
      try {
        final profile = await ref.read(currentUserProfileProvider.future);
        if (profile != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('last_user_id', profile.userId);
          await prefs.setString('last_family_id', profile.familyId);
          await prefs.setString('last_user_name', profile.fullName ?? "");
          await prefs.setString('last_user_role', profile.role ?? "");
          if (profile.role != "leader") {
            // await initializeBackgroundService();
            // await startWellCheckService(restart: true);
          }
          // final allMeds = await Supabase.instance.client
          //     .from('medications')
          //     .select()
          //     .eq('family_id', profile.familyId)
          //     .eq('is_active', true);
          // final medList = allMeds.map((e) => Medication.fromJson(e)).toList();
          // if (medList.isNotEmpty) {
          //   await MedicationNotificationService.scheduleForMedications(medList);
          // }
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

  InputDecoration _fieldDecoration(
    String label,
    IconData icon, {
    String? hint,
  }) {
    final scheme = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: ShieldDesign.roundedTwelve,
      borderSide: BorderSide(color: c, width: w),
    );

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: ShieldColors.textLabel),
      filled: true,
      fillColor: ShieldColors.activeTeal.withValues(alpha: 0.04),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: border(scheme.outlineVariant),
      enabledBorder: border(scheme.outlineVariant),
      focusedBorder: border(ShieldColors.activeTeal, 2),
      errorBorder: border(ShieldColors.urgentRed),
      focusedErrorBorder: border(ShieldColors.urgentRed, 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShieldColors.backgroundWhite,
      // appBar: AppBar(
      //   backgroundColor: Colors.transparent,
      //   elevation: 0,
      //   scrolledUnderElevation: 0,
      //   automaticallyImplyLeading:
      //       false, // user arrived via context.go, nothing to go back to
      // ),
      bottomNavigationBar: Padding(
        padding: MediaQuery.viewInsetsOf(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: SafeArea(
            top: false,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _isLoading
                    ? const SizedBox(
                        key: ValueKey('loading'),
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      )
                    : const Text(
                        'Save & Enter Dashboard',
                        key: ValueKey('label'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: AutofillGroup(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: 30),
                        const _ShieldBadge(icon: Icons.person_outline_rounded),
                        const SizedBox(height: 24),
                        Text(
                          'Complete Your Profile',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                                color: ShieldColors.textBody,
                              ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'So your family shield knows exactly who you are.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: ShieldColors.textLabel,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 36),

                        // Full name
                        TextFormField(
                          focusNode: profileNode,
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          onFieldSubmitted: (_) =>
                              phoneNumberNode.requestFocus(),
                          inputFormatters: [
                            // \p{L} allows Tamil, Hindi, accented letters etc.
                            FilteringTextInputFormatter.allow(
                              RegExp(r"[\p{L}\p{M}\s'.\-]", unicode: true),
                            ),
                          ],
                          validator: (value) {
                            final name = value?.trim() ?? '';
                            if (name.isEmpty) return 'Please enter your name';
                            if (name.length < 2) return 'Name is too short';
                            return null;
                          },
                          decoration: _fieldDecoration(
                            'Full Name',
                            Icons.person_outline_rounded,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Phone
                        TextFormField(
                          focusNode: phoneNumberNode,
                          controller: phoneNumber,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [
                            AutofillHints.telephoneNumberNational,
                          ],
                          onFieldSubmitted: (_) => ageNode.requestFocus(),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(15),
                          ],
                          validator: (value) {
                            final phone = value?.trim() ?? '';
                            if (phone.isEmpty)
                              return 'Please enter your phone number';
                            if (phone.length < 7)
                              return 'Enter at least 7 digits';
                            return null;
                          },
                          decoration: _fieldDecoration(
                            'Phone Number',
                            Icons.phone_outlined,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Age
                        TextFormField(
                          focusNode: ageNode,
                          controller: _ageController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!_isLoading) _saveProfile();
                          },
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          validator: (value) {
                            final age = value?.trim() ?? '';
                            if (age.isEmpty) return null;
                            final ageValue = int.tryParse(age);
                            if (ageValue == null ||
                                ageValue < 1 ||
                                ageValue > 120) {
                              return 'Please enter a valid age';
                            }
                            return null;
                          },
                          decoration: _fieldDecoration(
                            'Age',
                            Icons.cake_outlined,
                            hint: 'Optional',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShieldBadge extends StatelessWidget {
  const _ShieldBadge({this.icon = Icons.shield_outlined});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    const teal = ShieldColors.activeTeal;
    return Center(
      child: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              teal.withValues(alpha: 0.28),
              teal.withValues(alpha: 0.04),
            ],
          ),
          border: Border.all(color: teal.withValues(alpha: 0.35), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: teal.withValues(alpha: 0.25),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(icon, size: 52, color: teal),
      ),
    );
  }
}
