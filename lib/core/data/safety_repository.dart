import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'safety_repository.g.dart';

class SafetyRepository {
  final SupabaseClient _supabase;

  SafetyRepository(this._supabase);

  // Submit a background pulse or manual location update
  Future<void> submitPulse({
    required String familyId,
    required double latitude,
    required double longitude,
    required int batteryLevel,
    String type = 'heartbeat',
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    await _supabase.from('well_events').insert({
      'user_id': userId,
      'family_id': familyId,
      'event_type': type,
      'latitude': latitude,
      'longitude': longitude,
      'battery_level': batteryLevel,
      'verification_source': 'app_foreground', // or 'background_service'
    });
  }

  // Trigger highest-level alarm state
  Future<void> triggerSiren(String familyId, String reason) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in — cannot trigger SOS');

    await _supabase.from('well_events').insert({
      'user_id': userId,
      'family_id': familyId,
      'event_type': 'sos',
      'title': '🚨 Emergency SOS',
      'description': reason,
      'metadata': {'reason': reason, 'status': 'active'},
    });
  }

  // Stream recent events for the family (live updates)
  Stream<List<Map<String, dynamic>>> streamFamilyEvents(String familyId) {
    return _supabase
        .from('well_events')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId)
        .order(
          'created_at',
          ascending: false,
        ) // Corrected from timestamp to created_at
        .limit(50);
  }

  // Stream active family members
  Stream<List<Map<String, dynamic>>> streamActiveMembers(String familyId) async* {
    final stream = _supabase
        .from('family_members')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId);

    await for (final list in stream) {
      final activeList = list.where((item) => item['status'] == 'active').toList();
      if (activeList.isEmpty) {
        yield [];
        continue;
      }
      
      final userIds = activeList.map((e) => e['user_id']).toSet().toList();
      try {
        final profiles = await _supabase.from('profiles').select().inFilter('id', userIds);
        final profileMap = {for (var p in profiles) p['id'] as String: p};
        
        final enriched = activeList.map((item) {
          final enrichedItem = Map<String, dynamic>.from(item);
          final profile = profileMap[item['user_id']];
          if (profile != null) {
            enrichedItem['full_name'] = profile['full_name'] ?? '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
            enrichedItem['avatar_url'] = profile['avatar_url'];
          }
          return enrichedItem;
        }).toList();
        yield enriched;
      } catch (e) {
        // If profile fetch fails, yield unenriched data as fallback
        yield activeList;
      }
    }
  }

  // Stream pending family members
  Stream<List<Map<String, dynamic>>> streamPendingMembers(String familyId) async* {
    final stream = _supabase
        .from('family_members')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId);

    await for (final list in stream) {
      final pendingList = list.where((item) => item['status'] == 'pending').toList();
      if (pendingList.isEmpty) {
        yield [];
        continue;
      }
      
      final userIds = pendingList.map((e) => e['user_id']).toSet().toList();
      try {
        final profiles = await _supabase.from('profiles').select().inFilter('id', userIds);
        final profileMap = {for (var p in profiles) p['id'] as String: p};
        
        final enriched = pendingList.map((item) {
          final enrichedItem = Map<String, dynamic>.from(item);
          final profile = profileMap[item['user_id']];
          if (profile != null) {
            enrichedItem['full_name'] = profile['full_name'] ?? '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
            enrichedItem['avatar_url'] = profile['avatar_url'];
          }
          return enrichedItem;
        }).toList();
        yield enriched;
      } catch (e) {
        yield pendingList;
      }
    }
  }

  // Approve a pending member
  Future<void> approveMember(String memberId) async {
    await _supabase
        .from('family_members')
        .update({'status': 'active'})
        .eq('id', memberId);
  }

  // Reject a pending member
  Future<void> rejectMember(String memberId) async {
    await _supabase.from('family_members').delete().eq('id', memberId);
  }

  // Get binary latest status event WITH LOCATION for a specific member
  Stream<Map<String, dynamic>?> streamMemberLatestEvent(String userId) {
    return _supabase
        .from('well_events')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        // Note: Realtime streams don't support .not('latitude', 'is', null) server-side easily in the public schema without filters on stream
        // So we filter on the client side to only yield the first event that HAS a location
        .map((list) {
          try {
            return list.firstWhere(
              (evt) => evt['latitude'] != null && evt['longitude'] != null && evt['latitude'] != 0 && evt['longitude'] != 0,
            );
          } catch (_) {
            return null;
          }
        });
  }

  // Stream latest vitals for a specific member
  Stream<List<Map<String, dynamic>>> streamMemberVitals(String userId) {
    return _supabase
        .from('health_vitals')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('timestamp', ascending: false)
        .limit(10);
  }

  // Get the family name from families table (or fallback)
  Future<String> getFamilyName(String familyId) async {
    try {
      final result = await _supabase
          .from('families')
          .select('name')
          .eq('id', familyId)
          .maybeSingle();
      return result?['name'] ?? 'My Family Shield';
    } catch (_) {
      return 'My Family Shield';
    }
  }

  // Fetch the single latest event for a specific user WITH LOCATION (for map pins)
  Future<Map<String, dynamic>?> getLatestEventForUser(String userId) async {
    try {
      final result = await _supabase
          .from('well_events')
          .select()
          .eq('user_id', userId)
          .neq('latitude', 0.0)
          .neq('longitude', 0.0)
          .not('latitude', 'is', null)
          .not('longitude', 'is', null)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return result;
    } catch (_) {
      return null;
    }
  }
}

@riverpod
SafetyRepository safetyRepository(Ref ref) {
  return SafetyRepository(Supabase.instance.client);
}
