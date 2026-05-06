import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'health_repository.g.dart';

class HealthRepository {
  final SupabaseClient _client;
  final Health _health = Health();

  HealthRepository(this._client);

  // 1. Request Permissions
  Future<bool> requestPermissions() async {
    final types = [
      HealthDataType.HEART_RATE,
      HealthDataType.STEPS,
      HealthDataType.SLEEP_ASLEEP,
      HealthDataType.BLOOD_OXYGEN,
      HealthDataType.HEART_RATE_VARIABILITY_SDNN,
      HealthDataType.ELECTRODERMAL_ACTIVITY,
    ];

    // On Android, we need to specify access types
    final permissions = types.map((e) => HealthDataAccess.READ_WRITE).toList();

    return await _health.requestAuthorization(types, permissions: permissions);
  }

  // 2. Fetch and Sync Vitals
  Future<void> syncVitals({
    required String userId,
    required String familyId,
  }) async {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(hours: 24));

    final types = [
      HealthDataType.HEART_RATE,
      HealthDataType.BLOOD_OXYGEN,
    ];

    try {
      List<HealthDataPoint> healthData = await _health.getHealthDataFromTypes(
        startTime: yesterday,
        endTime: now,
        types: types,
      );

      if (healthData.isEmpty) return;

      // Filter and upload
      final vitalsToUpload = healthData.map((p) {
        return {
          'user_id': userId,
          'family_id': familyId,
          'vital_type': p.type.name,
          'value': double.tryParse(p.value.toString()) ?? 0.0,
          'unit': p.unit.name,
          'timestamp': p.dateFrom.toIso8601String(),
        };
      }).toList();

      await _client.from('health_vitals').upsert(vitalsToUpload);
      
      // Update baseline logic could go here or as an Edge Function
      await _calculateDistressAndEscalate(userId, familyId, healthData);
    } catch (e) {
      debugPrint('Error syncing health data: $e');
    }
  }

  // 3. Predictive Deviation & Escalation
  Future<void> _calculateDistressAndEscalate(
    String userId,
    String familyId,
    List<HealthDataPoint> recentData,
  ) async {
    // 1. Heart Rate Analysis
    final heartRates = recentData.where((p) => p.type == HealthDataType.HEART_RATE).toList();
    if (heartRates.isEmpty) return;
    final latestHr = double.tryParse(heartRates.last.value.toString()) ?? 0.0;

    // 2. HRV Analysis (Stress State)
    final hrvData = recentData.where((p) => p.type == HealthDataType.HEART_RATE_VARIABILITY_SDNN).toList();
    double? latestHrv;
    if (hrvData.isNotEmpty) {
      latestHrv = double.tryParse(hrvData.last.value.toString());
    }

    // 3. Movement Context (Zero-Assumption check)
    final steps = recentData.where((p) => p.type == HealthDataType.STEPS).toList();
    final double recentSteps = steps.fold(0.0, (sum, p) => sum + (double.tryParse(p.value.toString()) ?? 0.0));

    // Fetch baseline
    final baseline = await _client
        .from('health_baselines')
        .select()
        .eq('user_id', userId)
        .eq('vital_type', 'HEART_RATE')
        .maybeSingle();

    if (baseline != null) {
      final double maxNormal = baseline['max_value'] ?? 100.0;
      final double hrvBaseline = baseline['hrv_avg'] ?? 50.0;

      bool isDistressed = false;
      String distressReason = '';

      // Rule A: High HR + Low Steps (Stationary Distress)
      if (latestHr > maxNormal * 1.3 && recentSteps < 5) {
        isDistressed = true;
        distressReason = 'Tachycardia while stationary';
      }

      // Rule B: HRV Desynchronization (Stress State)
      if (latestHrv != null && latestHrv < hrvBaseline * 0.6) {
        isDistressed = true;
        distressReason += '${distressReason.isEmpty ? '' : ' & '}Low HRV (Psychological Stress)';
      }

      if (isDistressed) {
        await _client.from('well_events').insert({
          'user_id': userId,
          'family_id': familyId,
          'event_type': 'vital_anomaly',
          'metadata': {
            'vital_type': 'STRESS_STATE',
            'hr_value': latestHr,
            'hrv_value': latestHrv,
            'reason': distressReason,
            'severity': 'high',
            'status': 'pending_confirmation',
          }
        });
      }
    } else {
      // First time? Record current as baseline seed
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

  // 4. Consent Management
  Future<void> updateConsent(String userId, String dataType, bool granted) async {
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
