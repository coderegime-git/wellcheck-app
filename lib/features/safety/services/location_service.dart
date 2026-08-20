import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Call this on app start / initState.
  /// Does NOT open Settings or show any "go enable it" dialog.
  /// Just checks status and asks the system prompt if it hasn't been shown yet.
  /// Returns true only if permission is already usable.
  static Future<bool> checkLocationPermissions(BuildContext context) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Don't auto-open Settings. Let the caller decide whether to prompt
      // the user (e.g. via a snackbar) and call requestSettingsRedirect() later.
      return false;
    }

    LocationPermission geoPermission = await Geolocator.checkPermission();
    debugPrint('Initial permission status: $geoPermission');

    if (geoPermission == LocationPermission.whileInUse ||
        geoPermission == LocationPermission.always) {
      return true;
    }

    if (geoPermission == LocationPermission.denied) {
      // First-time system prompt — this is allowed, it's Apple's own dialog.
      geoPermission = await Geolocator.requestPermission();
      debugPrint('After system prompt: $geoPermission');

      // Whatever the result, do NOT show our own dialog here.
      // If denied or deniedForever, just return false quietly.
      return geoPermission == LocationPermission.whileInUse ||
          geoPermission == LocationPermission.always;
    }

    // deniedForever or restricted — return false, no auto dialog.
    return false;
  }

  /// Call this ONLY when the user actively tries to use a feature that
  /// requires location and it's currently unavailable (deniedForever or
  /// service disabled). This is the one place it's okay to offer Settings,
  /// per Apple's guidance: "if a feature won't function without access,
  /// you may include a notification and a link to Settings."
  static Future<bool> requestSettingsRedirect(
    BuildContext context, {
    required String title,
    required List<String> steps,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    final geoPermission = await Geolocator.checkPermission();

    final needsSettings =
        !serviceEnabled || geoPermission == LocationPermission.deniedForever;

    if (!needsSettings) {
      // Nothing to redirect for — don't show the dialog needlessly.
      return geoPermission == LocationPermission.whileInUse ||
          geoPermission == LocationPermission.always;
    }

    final shouldOpen = await _showSettingsDialog(
      context,
      title: title,
      steps: steps,
    );

    if (!shouldOpen) return false;

    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }

    final updatedPermission = await Geolocator.checkPermission();
    return updatedPermission == LocationPermission.whileInUse ||
        updatedPermission == LocationPermission.always;
  }

  static Future<bool> _showSettingsDialog(
    BuildContext context, {
    required String title,
    required List<String> steps,
  }) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.blue,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'To keep you safe, we need location access.',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: steps.asMap().entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: const BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${entry.key + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  entry.value,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Not Now'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Open Settings',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
  }

  static Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (e) {
      return null;
    }
  }

  static Stream<Position> getPositionStream() {
    if (Platform.isIOS) {
      return Geolocator.getPositionStream(
        locationSettings: AppleSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 10,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
        ),
      );
    }

    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 20),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Well Check Active',
          notificationText: 'Tracking location in background',
          notificationIcon: const AndroidResource(
            name: 'ic_stat_notify',
            defType: 'drawable',
          ),
          enableWakeLock: true,
        ),
      ),
    );
  }
}
