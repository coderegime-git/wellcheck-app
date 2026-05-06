import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class LocationProcessor {
  final SupabaseClient _client;

  LocationProcessor(this._client);

  /// Resolves raw coordinates into a semantic label based on [location_metadata].
  Future<String?> resolveSemanticLocation({
    required String familyId,
    required double latitude,
    required double longitude,
    required double? altitude,
  }) async {
    try {
      final List<dynamic> metadata = await _client
          .from('location_metadata')
          .select()
          .eq('family_id', familyId);

      if (metadata.isEmpty) return null;

      final currentPos = LatLng(latitude, longitude);
      final Distance distance = const Distance();

      for (final point in metadata) {
        final pointPos = LatLng(point['latitude'], point['longitude']);
        final meters = distance.as(LengthUnit.Meter, currentPos, pointPos);
        final double radius = (point['radius'] as num?)?.toDouble() ?? 10.0;

        if (meters <= radius) {
          final String baseLabel = point['semantic_label'] ?? 'Safe Zone';

          if (altitude != null) {
            final double? zoneAlt = (point['altitude'] as num?)?.toDouble();
            final String? floorName = point['floor_name'];

            if (zoneAlt != null && (altitude - zoneAlt).abs() < 3.0) {
              return floorName != null ? '$baseLabel ($floorName)' : baseLabel;
            }
          }
          return baseLabel;
        }
      }
    } catch (e) {
      debugPrint('Error resolving semantic location: $e');
    }
    return null;
  }

  /// Updates the profile and sends a pulse with semantic info if resolved.
  Future<void> updateSemanticState({
    required String userId,
    required String familyId,
    required double latitude,
    required double longitude,
    required double? altitude,
  }) async {
    final semantic = await resolveSemanticLocation(
      familyId: familyId,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
    );

    if (semantic != null) {
      await _client.from('profiles').update({
        'semantic_location': semantic,
        'altitude': altitude,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
    }
  }
}
