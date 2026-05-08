import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:geolocator/geolocator.dart';

class CheckInSheet extends ConsumerStatefulWidget {
  const CheckInSheet({super.key});

  @override
  ConsumerState<CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends ConsumerState<CheckInSheet> {
  bool _isLoading = false;
  final TextEditingController _statusController = TextEditingController();

  @override
  void dispose() {
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _performCheckIn() async {
    setState(() => _isLoading = true);

    try {
      int level =
          100; // Safe default for simulators and aggressive background iOS policies
      try {
        final battery = Battery();
        level = await battery.batteryLevel;
      } catch (e) {
        debugPrint(
          'Battery info not available over isolate, using default: $e',
        );
      }
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile found');

      final msg = _statusController.text.trim();
      final defaultMsg = "Checked in from Current Location.";

      bool gpsSuccess = false;
      double lat = 0.0;
      double lng = 0.0;

      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission == LocationPermission.deniedForever) {
            throw Exception(
              'Location permissions are permanently denied, we cannot request permissions. Please enable in Settings.',
            );
          }

          if (permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always) {
            // First attempt: High accuracy, short timeout
            try {
              final position = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high,
                ),
                timeLimit: const Duration(seconds: 5),
              );
              lat = position.latitude;
              lng = position.longitude;
              gpsSuccess = true;
            } catch (_) {
              // Fallback 1: Low accuracy (Cell tower/Wi-Fi), very fast
              try {
                final position = await Geolocator.getCurrentPosition(
                  locationSettings: const LocationSettings(
                    accuracy: LocationAccuracy.low,
                  ),
                  timeLimit: const Duration(seconds: 4),
                );
                lat = position.latitude;
                lng = position.longitude;
                gpsSuccess = true;
              } catch (_) {
                // Fallback 2: Last known position
                final lastPos = await Geolocator.getLastKnownPosition();
                if (lastPos != null) {
                  lat = lastPos.latitude;
                  lng = lastPos.longitude;
                  gpsSuccess = true;
                }
              }
            }
          }
        } else {
          throw Exception('GPS Location Services are disabled on this device.');
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('permanently denied') ||
            e.toString().contains('disabled')) {
          rethrow;
        }
      }
      await Supabase.instance.client.from('check_ins').insert({
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'latitude': lat,
        'longitude': lng,
        'status_message': msg.isNotEmpty ? msg : defaultMsg,
      });

      // Also register this as a well_event to ensure it shows up securely on the stream!
      await Supabase.instance.client.from('well_events').insert({
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'user_name': profile.fullName,
        'event_type': 'check_in',
        'title': 'Manual Check-in',
        'description': msg.isNotEmpty ? msg : defaultMsg,
        'latitude': lat,
        'longitude': lng,
        'battery_level': level,
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              gpsSuccess
                  ? 'Check-in successful!'
                  : 'Check-in successful! (GPS unavailable)',
            ),
            backgroundColor: gpsSuccess
                ? ShieldColors.safeZoneGreen
                : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile');

      final members = await Supabase.instance.client
          .from('family_members')
          .select('user_id')
          .eq('family_id', profile.familyId);

      // 3. Send push
      for (final m in members) {
        final targetUserId = m['user_id'];

        if (targetUserId == profile.userId) continue;

        try {
          await Supabase.instance.client.functions.invoke(
            'push-router',
            body: {
              "target_user_id": targetUserId,
              "title": "Check-In",
              "body": "${profile.fullName ?? 'Someone'}: Checked in just now",
              "action": "check_in",
            },
          );
        } catch (e) {
          print("Push failed: $e");
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: MediaQuery.viewInsetsOf(context),
          child: Container(
            decoration: const BoxDecoration(
              color: ShieldColors.backgroundWhite,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              12,
              // MediaQuery.of(context).viewInsets.bottom + 32,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Manual Check-in',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: ShieldColors.textBody,
                        ),
                      ),  GestureDetector(
                        onTap: () async {
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          padding: EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.shade400,
                                offset: Offset(0, 0),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.close, color: Colors.black, size: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Instantly broadcast your safe location to the family network. Your current GPS coordinates will be captured.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _statusController,
                    decoration: InputDecoration(
                      labelText: 'Optional Status Message',
                      hintText: 'e.g. "Arrived at school safely!"',
                      border: OutlineInputBorder(
                        borderRadius: ShieldDesign.roundedTwelve,
                      ),
                      prefixIcon: const Icon(Icons.chat_bubble_outline),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _performCheckIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ShieldColors.activeTeal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: ShieldDesign.roundedTwelve,
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.how_to_reg),
                                SizedBox(width: 8),
                                Text(
                                  'Broadcast Check-In',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
