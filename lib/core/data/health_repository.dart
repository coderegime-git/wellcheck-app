import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'health_repository.g.dart';

class HealthRepository {
  final SupabaseClient _client;
  final Health _health = Health();

  HealthRepository(this._client);

  // ─────────────────────────────────────────────
  // 1. Request Permissions
  // ─────────────────────────────────────────────
  Future<bool> requestPermissions() async {
    try {
      final types = _healthTypes;

      final permissions = types
          .map((e) => HealthDataAccess.READ_WRITE)
          .toList();
      bool heartRateEnabled = false;
      // Request Health Connect / HealthKit permissions
      final granted = await _health.requestAuthorization(
        types,
        permissions: permissions,
      );

      // Persist preference

      // Optional: verify we can actually access heart rate data
      if (granted) {
        try {
          final now = DateTime.now();
          final yesterday = now.subtract(const Duration(days: 1));

          final data = await _health.getHealthDataFromTypes(
            startTime: yesterday,
            endTime: now,
            types: [HealthDataType.HEART_RATE],
          );
          heartRateEnabled = data.isNotEmpty;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('priv_heartbeat', heartRateEnabled);
        } catch (e) {
          debugPrint('Heart rate read test failed: $e');
        }
      } else {
        heartRateEnabled = false;
      }

      return heartRateEnabled;
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('priv_heartbeat', false);

      debugPrint('Health permission request failed: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // Health types used across the repo
  // ─────────────────────────────────────────────
  static const List<HealthDataType> _healthTypes = [
    HealthDataType.HEART_RATE,
    HealthDataType.STEPS,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.ELECTRODERMAL_ACTIVITY,
  ];

  // ─────────────────────────────────────────────
  // 2. Fetch and Sync Vitals — returns SyncResult
  // ─────────────────────────────────────────────

  Future<SyncResult> syncVitals({
    required String userId,
    required String familyId,
    required String userName,
  }) async {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(hours: 24));
    final types = _healthTypes;

    // ── STAGE 1: Permission ──────────────────────
    bool granted = false;
    try {
      final permissions = types.map((e) => HealthDataAccess.READ).toList();
      granted = await _health.requestAuthorization(
        types,
        permissions: permissions,
      );
      bool heartRateEnabled = false;

      if (granted) {
        try {
          final now = DateTime.now();
          final yesterday = now.subtract(const Duration(days: 1));

          final data = await _health.getHealthDataFromTypes(
            startTime: yesterday,
            endTime: now,
            types: [HealthDataType.HEART_RATE],
          );
          print("heartRateEnabledheartRateEnabled");
          print(heartRateEnabled);
          heartRateEnabled = data.isNotEmpty;
        } catch (e) {
          final prefs = await SharedPreferences.getInstance();
          heartRateEnabled = false;
          await prefs.setBool('priv_heartbeat', false);
          debugPrint('Heart rate read failed: $e');
        }
      }
      final prefs = await SharedPreferences.getInstance();
      print("heartRateEnabledheartRateEnabled1");
      print(heartRateEnabled);
      await prefs.setBool('priv_heartbeat', heartRateEnabled);
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('priv_heartbeat', false);
      debugPrint('Permission request error: $e');
      return SyncResult(
        success: false,
        status: SyncStatus.permissionDenied,
        message:
        'Could not request Health permissions.\n\n'
            'Please go to:\nSettings → Privacy & Security → Health → [App Name]\n'
            'and enable all permissions manually.',
        debugInfo: {'stage': 'permission_request', 'error': e.toString()},
      );
    }

    if (!granted) {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('priv_heartbeat', false);
      return SyncResult(
        success: false,
        status: SyncStatus.permissionDenied,
        message:
        'Health access not granted.\n\n'
            'Please go to:\nSettings → Privacy & Security → Health → [App Name]\n'
            'and turn ON all health permissions, then try again.',
        debugInfo: {'stage': 'permission', 'granted': false},
      );
    }

    // ── STAGE 2: Fetch Health Data ───────────────
    List<HealthDataPoint> healthData = [];
    try {
      healthData = await _health.getHealthDataFromTypes(
        startTime: yesterday,
        endTime: now,
        types: types,
      );
    } catch (e) {
      debugPrint('Health fetch error: $e');
      return SyncResult(
        success: false,
        status: SyncStatus.unknownError,
        message:
        'Failed to read health data from your device.\n\n'
            'Please make sure:\n'
            '• Your watch is worn and connected to iPhone\n'
            '• Apple Health app is open and syncing\n'
            '• Try opening the Health app once, then retry',
        debugInfo: {'stage': 'fetch', 'error': e.toString()},
      );
    }

    // ── STAGE 3: Empty Data Check ────────────────
    if (healthData.isEmpty) {
      return SyncResult(
        success: false,
        status: SyncStatus.noData,
        message:
        'No health data found in the last 24 hours.\n\n'
            'Please make sure:\n'
            '• Your watch is worn and connected\n'
            '• Apple Health is syncing with your watch\n'
            '• Try opening the Health app once, then retry\n'
            '• Wear your watch for a few minutes to generate data',
        debugInfo: {
          'stage': 'data_check',
          'dataPoints': 0,
          'from': yesterday.toIso8601String(),
          'to': now.toIso8601String(),
        },
      );
    }

    // ── STAGE 4: Heart Rate Specific Check ───────
    final hasHeartRate = healthData.any(
          (p) => p.type == HealthDataType.HEART_RATE,
    );
    if (!hasHeartRate) {
      return SyncResult(
        success: false,
        status: SyncStatus.noHeartRate,
        message:
        'Watch is connected but no Heart Rate data was found.\n\n'
            'Please make sure:\n'
            '• Heart Rate monitoring is enabled on your watch\n'
            '• Wear your watch snugly on your wrist\n'
            '• Wait a few minutes for a reading, then retry',
        debugInfo: {
          'stage': 'heart_rate_check',
          'typesFound': healthData.map((e) => e.type.name).toSet().toList(),
        },
      );
    }

    // ── STAGE 5: De-duplicate ────────────────────
    final uniqueData = <String, HealthDataPoint>{};
    for (final p in healthData) {
      final key = '${p.type.name}_${p.dateFrom.toIso8601String()}';
      uniqueData[key] = p;
    }
    final filteredHealthData = uniqueData.values.toList();

    // ── STAGE 6: Upload to Supabase ──────────────
    final vitalsToUpload = filteredHealthData.map((p) {
      double value = 0;

      if (p.value is NumericHealthValue) {
        value = (p.value as NumericHealthValue).numericValue.toDouble();
      } else {
        value = double.tryParse(p.value.toString()) ?? 0;
      }

      return {
        'user_id': userId,
        'family_id': familyId,
        'vital_type': p.type.name,
        'value': value,
        'unit': p.unit.name,
        'timestamp': p.dateFrom.toIso8601String(),
      };
    }).toList();

    try {
      await _client
          .from('health_vitals')
          .upsert(vitalsToUpload, onConflict: 'user_id,vital_type,timestamp');
    } catch (e) {
      debugPrint('Supabase upload error: $e');

      // Check if it's a network issue
      final isNetwork =
          e.toString().toLowerCase().contains('socket') ||
              e.toString().toLowerCase().contains('network') ||
              e.toString().toLowerCase().contains('connection') ||
              e.toString().toLowerCase().contains('timeout');

      return SyncResult(
        success: false,
        status: isNetwork ? SyncStatus.networkError : SyncStatus.uploadFailed,
        message: isNetwork
            ? 'No internet connection.\n\n'
            'Health data was read from your watch but could not be uploaded.\n'
            'Please check your internet and try again.'
            : 'Data upload failed.\n\n'
            'Health data was read from your watch but could not be saved.\n'
            'Please try again. If the issue persists, contact support.',
        debugInfo: {
          'stage': 'upload',
          'error': e.toString(),
          'recordCount': vitalsToUpload.length,
        },
      );
    }

    // ── STAGE 7: Battery ─────────────────────────
    int batteryLevel = 100;
    try {
      batteryLevel = await Battery().batteryLevel;
    } catch (e) {
      debugPrint('Battery info not available: $e');
    }

    // ── STAGE 8: Well Event Insert ───────────────
    try {
      await _client.from('well_events').insert({
        'user_id': userId,
        'family_id': familyId,
        'event_type': 'heartbeat',
        'user_name': userName,
        'title': 'Health Sync Active',
        'description': 'Health data synced from device.',
        'battery_level': batteryLevel,
        'metadata': {
          'types_synced': filteredHealthData.map((e) => e.type.name).toList(),
        },
      });
    } catch (e) {
      // Non-critical — don't fail the whole sync for this
      debugPrint('Well event insert error (non-critical): $e');
    }

    // ── STAGE 9: Distress Analysis ───────────────
    try {
      await _calculateDistressAndEscalate(
        userId,
        familyId,
        userName,
        healthData,
      );
    } catch (e) {
      // Non-critical — don't fail the whole sync for this
      debugPrint('Distress analysis error (non-critical): $e');
    }

    // ── STAGE 10: Build Success Summary ──────────
    final Map<String, int> typeCounts = {};
    for (final p in filteredHealthData) {
      typeCounts[p.type.name] = (typeCounts[p.type.name] ?? 0) + 1;
    }

    final heartRateCount = typeCounts['HEART_RATE'] ?? 0;
    final stepsCount = typeCounts['STEPS'] ?? 0;
    final spo2Count = typeCounts['BLOOD_OXYGEN'] ?? 0;
    final hrvCount = typeCounts['HEART_RATE_VARIABILITY_SDNN'] ?? 0;
    final sleepCount = typeCounts['SLEEP_ASLEEP'] ?? 0;

    final summaryLines = <String>[
      if (heartRateCount > 0) '❤️  Heart Rate: $heartRateCount readings',
      if (stepsCount > 0) '🚶 Steps: $stepsCount entries',
      if (spo2Count > 0) '🩸 Blood Oxygen: $spo2Count readings',
      if (hrvCount > 0) '📊 HRV: $hrvCount readings',
      if (sleepCount > 0) '😴 Sleep: $sleepCount entries',
    ];

    return SyncResult(
      success: true,
      status: SyncStatus.success,
      message:
      'Health data synced successfully!\n\n'
          '${summaryLines.join('\n')}\n\n'
          'Total: ${filteredHealthData.length} data points uploaded.',
      debugInfo: typeCounts,
    );
  }

  // ─────────────────────────────────────────────
  // 3. Predictive Deviation & Escalation
  // ─────────────────────────────────────────────
  Future<void> _calculateDistressAndEscalate(
      String userId,
      String familyId,
      String userName,
      List<HealthDataPoint> recentData,
      ) async {
    debugPrint('Running distress analysis...');

    final heartRates = recentData
        .where((p) => p.type == HealthDataType.HEART_RATE)
        .toList();

    if (heartRates.isEmpty) return;

    final latestHr = double.tryParse(heartRates.last.value.toString()) ?? 0.0;

    final hrvData = recentData
        .where((p) => p.type == HealthDataType.HEART_RATE_VARIABILITY_SDNN)
        .toList();
    double? latestHrv;
    if (hrvData.isNotEmpty) {
      latestHrv = double.tryParse(hrvData.last.value.toString());
    }

    int batteryLevel = 100;
    try {
      batteryLevel = await Battery().batteryLevel;
    } catch (e) {
      debugPrint('Battery info not available: $e');
    }

    final steps = recentData
        .where((p) => p.type == HealthDataType.STEPS)
        .toList();
    final double recentSteps = steps.fold(
      0.0,
          (sum, p) => sum + (double.tryParse(p.value.toString()) ?? 0.0),
    );

    final baseline = await _client
        .from('health_baselines')
        .select()
        .eq('user_id', userId)
        .eq('vital_type', 'HEART_RATE')
        .maybeSingle();

    if (baseline != null) {
      final double maxNormal =
          (baseline['max_value'] as num?)?.toDouble() ?? 100.0;
      final double hrvBaseline =
          (baseline['hrv_avg'] as num?)?.toDouble() ?? 50.0;

      bool isDistressed = false;
      String distressReason = '';

      if (latestHr > maxNormal * 1.3 && recentSteps < 5) {
        isDistressed = true;
        distressReason = 'Tachycardia while stationary';
      }

      if (latestHrv != null && latestHrv < hrvBaseline * 0.6) {
        isDistressed = true;
        distressReason +=
        '${distressReason.isEmpty ? '' : ' & '}Low HRV (Psychological Stress)';
      }

      debugPrint('isDistressed: $isDistressed — $distressReason');

      if (isDistressed) {
        String title = 'Health Alert Detected';
        String description =
            'Elevated stress indicators detected from wearable vitals.';

        if (distressReason.toLowerCase().contains('heart')) {
          title = 'Abnormal Heart Rate';
          description =
          'Heart rate is significantly above the normal baseline.';
        } else if (distressReason.toLowerCase().contains('hrv')) {
          title = 'High Stress Detected';
          description = 'Low HRV and elevated stress levels were detected.';
        }

        await _client.from('well_events').insert({
          'user_id': userId,
          'family_id': familyId,
          'event_type': 'vital_anomaly',
          'title': '$title - $userName',
          'description': description,
          'metadata': {
            'vital_type': 'STRESS_STATE',
            'hr_value': latestHr,
            'hrv_value': latestHrv,
            'reason': distressReason,
            'severity': 'high',
            'status': 'pending_confirmation',
          },
          'battery_level': batteryLevel,
        });
      }
    } else {
      // First time — seed the baseline
      await _client.from('well_events').insert({
        'user_id': userId,
        'family_id': familyId,
        'event_type': 'heartbeat',
        'title': 'Pulse Active - $userName',
        'description': 'Wearable vitals synced successfully.',
        'battery_level': batteryLevel,
        'metadata': {'heart_rate': latestHr, 'hrv': latestHrv},
      });

      await _client.from('health_baselines').upsert({
        'user_id': userId,
        'vital_type': 'HEART_RATE',
        'avg_value': latestHr,
        'max_value': latestHr + 20,
        'hrv_avg': latestHrv ?? 50.0,
        'sample_count': 1,
      });
    }
  }

  // ─────────────────────────────────────────────
  // 4. Consent Management
  // ─────────────────────────────────────────────
  Future<void> updateConsent(
      String userId,
      String dataType,
      bool granted,
      ) async {
    await _client.from('consent_ledger').upsert({
      'user_id': userId,
      'data_type': dataType,
      'granted': granted,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}

@riverpod
HealthRepository healthRepository(Ref ref) {
  return HealthRepository(Supabase.instance.client);
}

Future<void> runHealthSync(
    BuildContext context,
    WidgetRef ref, {
      required String userId,
      required String familyId,
      required String userName,
    }) async {
  // Show loading indicator
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Syncing health data...')),
          ],
        ),
      ),
    ),
  );

  final repo = ref.read(healthRepositoryProvider);
  final result = await repo.syncVitals(
    userId: userId,
    familyId: familyId,
    userName: userName,
  );

  // Close loading dialog
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

  if (!context.mounted) return;

  if (result.success) {
    _showSuccessSnackbar(context, result.message);
  } else {
    _showErrorDialog(context, result);
  }
}

// ─────────────────────────────────────────────────────────────
// Success — subtle snackbar (non-blocking)
// ─────────────────────────────────────────────────────────────
void _showSuccessSnackbar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: Colors.green.shade700,
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// Error — blocking dialog with icon + action per scenario
// ─────────────────────────────────────────────────────────────
void _showErrorDialog(BuildContext context, SyncResult result) {
  final config = _dialogConfig(result.status);

  showDialog(
    context: context,
    barrierDismissible: false, // client must read and dismiss
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(config.icon, color: config.color, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              config.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Text(
        result.message,
        style: const TextStyle(fontSize: 14, height: 1.5),
      ),
      actions: [
        // Optional: retry button for network/upload errors
        if (result.status == SyncStatus.networkError ||
            result.status == SyncStatus.uploadFailed)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Retry'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// Icon + title per SyncStatus
// ─────────────────────────────────────────────────────────────
_DialogConfig _dialogConfig(SyncStatus status) {
  switch (status) {
    case SyncStatus.permissionDenied:
      return _DialogConfig(
        icon: Icons.lock_outline,
        color: Colors.orange,
        title: 'Permission Required',
      );
    case SyncStatus.noData:
      return _DialogConfig(
        icon: Icons.watch_off_outlined,
        color: Colors.blue,
        title: 'No Health Data Found',
      );
    case SyncStatus.noHeartRate:
      return _DialogConfig(
        icon: Icons.favorite_border,
        color: Colors.red,
        title: 'No Heart Rate Data',
      );
    case SyncStatus.networkError:
      return _DialogConfig(
        icon: Icons.wifi_off_outlined,
        color: Colors.grey,
        title: 'No Internet Connection',
      );
    case SyncStatus.uploadFailed:
      return _DialogConfig(
        icon: Icons.cloud_off_outlined,
        color: Colors.deepOrange,
        title: 'Upload Failed',
      );
    case SyncStatus.unknownError:
    default:
      return _DialogConfig(
        icon: Icons.error_outline,
        color: Colors.red,
        title: 'Sync Failed',
      );
  }
}

class _DialogConfig {
  final IconData icon;
  final Color color;
  final String title;

  _DialogConfig({required this.icon, required this.color, required this.title});
} // sync_result.dart

enum SyncStatus {
  success,
  permissionDenied,
  noData,
  noHeartRate,
  uploadFailed,
  networkError,
  unknownError,
}

class SyncResult {
  final bool success;
  final String message;
  final SyncStatus status;
  final Map<String, dynamic> debugInfo;

  SyncResult({
    required this.success,
    required this.message,
    required this.status,
    this.debugInfo = const {},
  });
}
