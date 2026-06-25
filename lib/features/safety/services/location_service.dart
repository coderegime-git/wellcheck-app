import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Call this in initState or on app start.
  /// Returns true if all required permissions are granted.
  static Future<bool> requestLocationPermissions(BuildContext context) async {
    // Step 1: Device GPS off
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return false;
    }

    // Step 2: Check current status
    LocationPermission geoPermission = await Geolocator.checkPermission();
    debugPrint('Initial permission status: $geoPermission');

    // ✅ Already "Always" — nothing to do
    if (geoPermission == LocationPermission.always) {
      debugPrint('Location already Always ✅');
      return true;
    }

    // ✅ First time or soft denied — show system prompt first
    if (geoPermission == LocationPermission.denied) {
      geoPermission = await Geolocator.requestPermission();
      debugPrint('After system prompt: $geoPermission');

      // User granted Always on first ask (rare but possible on Android)
      if (geoPermission == LocationPermission.always) return true;

      // User picked "While Using" — show our dialog to upgrade to Always
      if (geoPermission == LocationPermission.whileInUse) {
        final shouldOpen = await _showSettingsDialog(
          context,
          title: 'Enable "Always" Location',
          steps: [
            'Tap "Open Settings" below',
            'Select "Location"',
            'Choose "Always"',
          ],
        );
        if (shouldOpen) {
          await Geolocator.openAppSettings();
          // After returning from settings, re-check
          geoPermission = await Geolocator.checkPermission();
          return geoPermission == LocationPermission.always;
        }
        return false; // user tapped Not Now
      }

      // User denied entirely from system prompt — don't show dialog yet
      // They'll see it next app open via deniedForever or whileInUse check
      if (geoPermission == LocationPermission.denied) {
        return false;
      }
    }

    // ✅ Already "While Using" (set in a previous session) — ask to upgrade
    if (geoPermission == LocationPermission.whileInUse) {
      final shouldOpen = await _showSettingsDialog(
        context,
        title: 'Enable Location',
        steps: [
          'Tap "Open Settings" below',
          'Select "Location"',
          'Choose option',
        ],
      );
      if (shouldOpen) {
        await Geolocator.openAppSettings();
        geoPermission = await Geolocator.checkPermission();
        return geoPermission == LocationPermission.always;
      }
      return false;
    }

    // ✅ Permanently denied — must go to settings
    if (geoPermission == LocationPermission.deniedForever) {
      final shouldOpen = await _showSettingsDialog(
        context,
        title: 'Location Permission Required',
        steps: [
          'Tap "Open Settings" below',
          'Select "Location"',
          'Choose option',
        ],
      );
      if (shouldOpen) {
        await Geolocator.openAppSettings();
        geoPermission = await Geolocator.checkPermission();
        return geoPermission == LocationPermission.always;
      }
      return false;
    }

    return false;
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
                  // Icon
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

                  // Title
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    'To keep you safe, we need to track your location in the background.',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Steps
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

                  // Buttons
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

  /// Get current position (use after permissions confirmed)
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

  /// Stream position updates (foreground + background)
  static Stream<Position> getPositionStream() {
    if (Platform.isIOS) {
      return Geolocator.getPositionStream(
        locationSettings: AppleSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 10,

          //timeLimit: Duration(seconds: 15),
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
        ),
      );
    }

    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: Duration(seconds: 20),
        //  timeLimit: Duration(seconds: 15),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'Well Check Active',
          notificationText: 'Tracking location in background',
          enableWakeLock: true,
        ),
      ),
    );
  }
}
