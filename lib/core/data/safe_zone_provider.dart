import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';

part 'safe_zone_provider.g.dart';

class SafeZone {
  final String id;
  final String zoneName;
  final double latitude;
  final double longitude;
  final int radiusMeters;

  SafeZone({
    required this.id,
    required this.zoneName,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  factory SafeZone.fromJson(Map<String, dynamic> json) {
    return SafeZone(
      id: json['id'] as String,
      zoneName: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: json['radius_meters'] as int,
    );
  }
}

@riverpod
Stream<List<SafeZone>> familySafeZones(Ref ref) async* {
  final profile = await ref.watch(currentUserProfileProvider.future);
  if (profile == null) {
    yield [];
    return;
  }

  final supabase = Supabase.instance.client;
  yield* supabase
      .from('locations_safe_zones')
      .stream(primaryKey: ['id'])
      .eq('family_id', profile.familyId)
      .order('created_at', ascending: true)
      .map((zones) => zones.map((z) => SafeZone.fromJson(z)).toList());
}
