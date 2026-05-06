import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/notifications/global_notification_service.dart';

class GlobalNotificationWrapper extends ConsumerStatefulWidget {
  final Widget child;
  const GlobalNotificationWrapper({super.key, required this.child});

  @override
  ConsumerState<GlobalNotificationWrapper> createState() =>
      _GlobalNotificationWrapperState();
}

class _GlobalNotificationWrapperState
    extends ConsumerState<GlobalNotificationWrapper> {
  bool _hasInitialized = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserProfileProvider, (prev, next) async {
      final profile = next.value;
      if (profile != null && !_hasInitialized) {
        _hasInitialized = true;

        // 1. Start listening to family events across the whole app
        GlobalNotificationService.startListeningForFamilyEvents(
            profile.familyId, profile.userId);

        // 2. Show the 'first time' test notification if they haven't seen it yet
        final prefs = await SharedPreferences.getInstance();
        final hasSeenFirst =
            prefs.getBool('has_seen_first_notification') ?? false;

        if (!hasSeenFirst) {
          await prefs.setBool('has_seen_first_notification', true);

          // Delay slightly so the UI has time to fully paint the dashboard
          Future.delayed(const Duration(seconds: 3), () {
            GlobalNotificationService.showNotification(
              id: 9999,
              title: "Shield Active 🛡️",
              body: "Welcome to your Dashboard! You will now receive family alerts.",
            );
          });
        }
      } else if (profile == null && _hasInitialized) {
        // User logged out
        _hasInitialized = false;
        GlobalNotificationService.dispose();
      }
    });

    return widget.child;
  }
}
