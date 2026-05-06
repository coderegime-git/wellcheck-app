import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ToolsRepository {
  final SupabaseClient _supabase;

  ToolsRepository(this._supabase);

  // === CHAT HUB ===
  Stream<List<Map<String, dynamic>>> streamChatMessages(String familyId) {
    return _supabase
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId)
        .order('created_at', ascending: true); // Oldest first for chat UI
  }

  Future<void> sendMessage(String familyId, String content) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    await _supabase.from('chat_messages').insert({
      'family_id': familyId,
      'sender_id': userId,
      'content': content,
    });
  }

  // === MEDICATION ===
  Stream<List<Map<String, dynamic>>> streamMedications(String familyId) {
    return _supabase
        .from('medications')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId);
  }

  Future<void> addMedication({
    required String familyId,
    required String assignedUserId,
    required String name,
    required String dosage,
    required String scheduleTime, // e.g. "08:00:00"
    required int inventoryCount,
  }) async {
    await _supabase.from('medications').insert({
      'family_id': familyId,
      'assigned_user_id': assignedUserId,
      'name': name,
      'dosage': dosage,
      'schedule_time': scheduleTime,
      'inventory_count': inventoryCount,
    });
  }

  // === SAFE ZONES ===
  Stream<List<Map<String, dynamic>>> streamSafeZones(String familyId) {
    return _supabase
        .from('locations_safe_zones')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId);
  }

  Future<void> addSafeZone({
    required String familyId,
    required String name,
    required double latitude,
    required double longitude,
    required int radiusMeters,
  }) async {
    await _supabase.from('locations_safe_zones').insert({
      'family_id': familyId,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
    });
  }

  Future<void> deleteSafeZone(String zoneId) async {
    await _supabase.from('locations_safe_zones').delete().eq('id', zoneId);
  }
}

final toolsRepositoryProvider = Provider<ToolsRepository>((ref) {
  return ToolsRepository(Supabase.instance.client);
});
