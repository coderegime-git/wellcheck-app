import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';
import 'package:image_picker/image_picker.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';

import '../../core/data/health_repository.dart';
import '../../core/data/subscription_provider.dart';
import '../../core/notifications/push_notification_service.dart';
import 'health_kit_screen.dart';

class ProfileSettingsView extends ConsumerStatefulWidget {
  const ProfileSettingsView({super.key});

  @override
  ConsumerState<ProfileSettingsView> createState() =>
      _ProfileSettingsViewState();
}

class _ProfileSettingsViewState extends ConsumerState<ProfileSettingsView> {
  bool _isUploading = false;
  bool isLoad = false;
  bool _isLoggingOut = false;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final result = await Supabase.instance.client
          .from('profiles')
          .select('avatar_url')
          .eq('id', userId)
          .maybeSingle();
      if (result != null && result['avatar_url'] != null && mounted) {
        setState(() => _avatarUrl = result['avatar_url'] as String);
      }
    } catch (_) {}
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (image == null) return;

    setState(() => _isUploading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final bytes = await image.readAsBytes();
      final ext = image.path.split('.').last;
      final filePath = '$userId/avatar.$ext';

      // Upload to Supabase Storage
      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(
            filePath,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      // Get public URL
      final publicUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(filePath);

      // Update profile
      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': publicUrl})
          .eq('id', userId);

      if (mounted) {
        setState(() => _avatarUrl = publicUrl);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated!'),
            backgroundColor: ShieldColors.safeZoneGreen,
          ),
        );
      }
    } catch (e) {
      print(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out?'),
        content: const Text('You will be signed out of the Shield network.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ShieldColors.urgentRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLoggingOut = true);
    try {
      PushNotificationService.saveTokenToProfile(null);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('priv_biometric', false);
      FlutterBackgroundService().invoke('stopService');
      await Supabase.instance.client.auth.signOut();
      // Router will handle navigation to login via auth state listener
    } catch (e) {
      if (mounted) {
        setState(() => _isLoggingOut = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
      }
    }
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
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: SingleChildScrollView(
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
            Text(
              'Profile & Settings',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Avatar
            GestureDetector(
              onTap: _isUploading ? null : _pickAndUploadAvatar,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: ShieldColors.activeTeal.withValues(
                      alpha: 0.1,
                    ),
                    backgroundImage: _avatarUrl != null
                        ? NetworkImage(_avatarUrl!)
                        : null,
                    child: _isUploading
                        ? const CircularProgressIndicator()
                        : _avatarUrl == null
                        ? const Icon(
                            Icons.person,
                            size: 48,
                            color: ShieldColors.activeTeal,
                          )
                        : null,
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: ShieldColors.activeTeal,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Name & Role
            profileAsync.when(
              data: (profile) {
                if (profile == null) return const SizedBox.shrink();
                return Column(
                  children: [
                    Text(
                      profile.fullName ?? 'User',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: ShieldColors.activeTeal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        profile.role.toUpperCase(),
                        style: const TextStyle(
                          color: ShieldColors.activeTeal,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Supabase.instance.client.auth.currentUser?.email ?? '',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (e, st) => Text('Error: $e'),
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Settings items
            _settingsItem(
              icon: Icons.camera_alt,
              label: 'Change Profile Photo',
              onTap: _pickAndUploadAvatar,
            ),
            _settingsItem(
              icon: Icons.notifications_outlined,
              label: 'Notification Preferences',
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const _NotificationPrefsSheet(),
                );
              },
            ),
            _settingsItem(
              icon: Icons.shield_outlined,
              label: 'Privacy & Security',
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const _PrivacySecuritySheet(),
                );
              },
            ),
            // In your settings screen (ProfileSettingsView or wherever settings lives)
            Consumer(
              builder: (context, ref, _) {
                final sub = ref.watch(subscriptionProvider);
                return sub.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (state) {
                    if (!state.isWellCheckPro) return const SizedBox.shrink();
                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE1F5EE),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.workspace_premium,
                          color: Color(0xFF007F80),
                          size: 20,
                        ),
                      ),
                      title: const Text('Manage Subscription'),
                      subtitle: const Text('Cancel, restore or get help'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => RevenueCatUI.presentCustomerCenter(),
                    );
                  },
                );
              },
            ),

            // const Spacer(),
            Text("Version:1.0.0"),
            SizedBox(height: 10),
            GestureDetector(
              child: Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isLoad
                    ? Center(
                        child: SizedBox(
                          height: 25,
                          width: 25,
                          child: CircularProgressIndicator(color: Colors.red),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_forever, color: Colors.red),
                          SizedBox(width: 10),
                          const Text(
                            'Delete Account',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
              ),
              onTap: () async {
                if (isLoad) return;
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Account'),
                    content: const Text(
                      'Are you sure? This action cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await deleteAccount();
                }
              },
            ),
            SizedBox(height: 10),

            // Log Out Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isLoggingOut ? null : _logout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ShieldColors.urgentRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: ShieldDesign.roundedTwelve,
                  ),
                ),
                icon: _isLoggingOut
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.logout),
                label: Text(_isLoggingOut ? 'Logging out...' : 'Log Out'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> deleteAccount() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;

      if (user == null) return;
      setState(() {
        isLoad = true;
      });
      await Future.delayed(Duration(seconds: 2));
      await Supabase.instance.client
          .from('profiles')
          .delete()
          .eq('id', user.id);

      // Delete auth user via Edge Function
      final response = await Supabase.instance.client.functions.invoke(
        'delete-user',
        body: {'user_id': user.id},
      );
      if (response.status == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Account deleted successfully")));

        await Supabase.instance.client.auth.signOut();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to delete account")));
      }
      await Supabase.instance.client.auth.signOut();
      setState(() {
        isLoad = false;
      });
      debugPrint('Account deleted');
    } catch (e) {
      setState(() {
        isLoad = false;
      });
      debugPrint('Delete account error: $e');
    }
  }

  Widget _settingsItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: ShieldColors.activeTeal.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: ShieldColors.activeTeal, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}

class _NotificationPrefsSheet extends StatefulWidget {
  const _NotificationPrefsSheet();

  @override
  State<_NotificationPrefsSheet> createState() =>
      _NotificationPrefsSheetState();
}

class _NotificationPrefsSheetState extends State<_NotificationPrefsSheet> {
  bool _sosAlerts = true;
  bool _checkInAlerts = true;
  bool _medicationReminders = true;
  bool _calendarReminders = true;
  bool _safeZoneAlerts = true;
  bool _drivingAlerts = false;
  bool heartBeat = true;
  final Health _health = Health();
  final List<HealthDataType> _healthTypes = [
    HealthDataType.HEART_RATE,
    HealthDataType.STEPS,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.ELECTRODERMAL_ACTIVITY,
  ];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sosAlerts = prefs.getBool('notif_sos') ?? true;
      _checkInAlerts = prefs.getBool('notif_checkin') ?? true;
      _medicationReminders = prefs.getBool('notif_med') ?? true;
      _calendarReminders = prefs.getBool('notif_cal') ?? true;
      _safeZoneAlerts = prefs.getBool('notif_safezone') ?? true;
      _drivingAlerts = prefs.getBool('notif_driving') ?? false;
      heartBeat = prefs.getBool('priv_heartbeat') ?? true;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_sos', _sosAlerts);
    await prefs.setBool('notif_checkin', _checkInAlerts);
    await prefs.setBool('notif_med', _medicationReminders);
    await prefs.setBool('notif_cal', _calendarReminders);
    await prefs.setBool('notif_safezone', _safeZoneAlerts);
    await prefs.setBool('notif_driving', _drivingAlerts);
    await prefs.setBool('priv_heartbeat', heartBeat);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ShieldColors.backgroundWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
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
          Text(
            'Notification Preferences',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            title: const Text('Emergency SOS Alerts'),
            subtitle: const Text('Always recommended'),
            value: _sosAlerts,
            activeColor: ShieldColors.urgentRed,
            onChanged: (v) => setState(() => _sosAlerts = v),
          ),
          SwitchListTile(
            title: const Text('Sync Heart Rate'),
            //    subtitle: const Text('AES-256 encryption for all vault files'),
            value: heartBeat,
            activeColor: ShieldColors.activeTeal,
            onChanged: (value) async {
              if (value) {
                final healthRepo = HealthRepository(Supabase.instance.client);

                try {
                  final granted = await healthRepo.requestPermissions();

                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('priv_heartbeat', granted);
                  setState(() => heartBeat = granted);
                } catch (e) {
                  final prefs = await SharedPreferences.getInstance();

                  await prefs.setBool('priv_heartbeat', false);

                  debugPrint(
                    '[ProfileSetup] HealthKit permission request failed: $e',
                  );
                  // ScaffoldMessenger.of(context).showSnackBar(
                  //   SnackBar(
                  //     content: Text('HealthKit permission request failed: $e'),
                  //   ),
                  // );
                  setState(() => heartBeat = false);
                }
              } else {
                setState(() => heartBeat = false);
              }
              //final prefs = await SharedPreferences.getInstance();

              // prefs.getBool('priv_heartbeat') ?? true;
            },
          ),
          SwitchListTile(
            title: const Text('Check-In Notifications'),
            value: _checkInAlerts,
            activeColor: ShieldColors.activeTeal,
            onChanged: (v) => setState(() => _checkInAlerts = v),
          ),
          SwitchListTile(
            title: const Text('Medication Reminders'),
            value: _medicationReminders,
            activeColor: ShieldColors.activeTeal,
            onChanged: (v) => setState(() => _medicationReminders = v),
          ),
          SwitchListTile(
            title: const Text('Calendar Reminders'),
            value: _calendarReminders,
            activeColor: ShieldColors.activeTeal,
            onChanged: (v) => setState(() => _calendarReminders = v),
          ),

          SwitchListTile(
            title: const Text('Safe Zone Entry/Exit'),
            value: _safeZoneAlerts,
            activeColor: ShieldColors.activeTeal,
            onChanged: (v) => setState(() => _safeZoneAlerts = v),
          ),
          SwitchListTile(
            title: const Text('Driving Alerts'),
            value: _drivingAlerts,
            activeColor: Colors.orange,
            onChanged: (v) => setState(() => _drivingAlerts = v),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                await _savePrefs();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Preferences saved!'),
                      backgroundColor: ShieldColors.safeZoneGreen,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: ShieldColors.activeTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: ShieldDesign.roundedTwelve,
                ),
              ),
              child: const Text('Save Preferences'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacySecuritySheet extends StatefulWidget {
  const _PrivacySecuritySheet();

  @override
  State<_PrivacySecuritySheet> createState() => _PrivacySecuritySheetState();
}

class _PrivacySecuritySheetState extends State<_PrivacySecuritySheet> {
  bool _locationSharing = true;
  bool _biometricLock = false;
  bool _encryptedVault = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _locationSharing = prefs.getBool('priv_location') ?? true;
      _biometricLock = prefs.getBool('priv_biometric') ?? false;
      _encryptedVault = prefs.getBool('priv_vault') ?? true;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('priv_location', _locationSharing);
    await prefs.setBool('priv_biometric', _biometricLock);
    await prefs.setBool('priv_vault', _encryptedVault);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ShieldColors.backgroundWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
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
          Text(
            'Privacy & Security',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            title: const Text('Share Location with Family'),
            subtitle: const Text('Required for safe zone tracking'),
            value: _locationSharing,
            activeColor: ShieldColors.activeTeal,
            onChanged: (v) => setState(() => _locationSharing = v),
          ),
          SwitchListTile(
            title: const Text('Biometric Lock (Face ID / Touch ID)'),
            subtitle: const Text('Require authentication to open app'),
            value: _biometricLock,
            activeColor: ShieldColors.activeTeal,
            onChanged: (v) => setState(() => _biometricLock = v),
          ),
          SwitchListTile(
            title: const Text('End-to-End Encrypted Vault'),
            subtitle: const Text('AES-256 encryption for all vault files'),
            value: _encryptedVault,
            activeColor: ShieldColors.activeTeal,
            onChanged: (v) => setState(() => _encryptedVault = v),
          ),
          ListTile(
            //    leading: const Icon(Icons.favorite),
            title: const Text('Health Monitoring'),
            subtitle: const Text('Manage Apple Health integration'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HealthKitInfoScreen()),
              );
            },
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ShieldColors.activeTeal.withValues(alpha: 0.05),
              borderRadius: ShieldDesign.roundedTwelve,
              border: Border.all(
                color: ShieldColors.activeTeal.withValues(alpha: 0.2),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock, color: ShieldColors.activeTeal, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your data is encrypted in transit and at rest. Only your family members can see your location.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                await _savePrefs();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Security settings saved!'),
                      backgroundColor: ShieldColors.safeZoneGreen,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: ShieldColors.activeTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: ShieldDesign.roundedTwelve,
                ),
              ),
              child: const Text('Save Settings'),
            ),
          ),
        ],
      ),
    );
  }
}
