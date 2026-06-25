import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    final prefs = await SharedPreferences.getInstance();
    final profileRes = await Supabase.instance.client
        .from('profiles')
        .select('full_name')
        .eq('id', userId)
        .single();
    final fullName = profileRes['full_name'];
    final heartRateEnabled = prefs.getBool('priv_heartbeat') ?? true;

    if (heartRateEnabled && type == "heartbeat") {
      await _supabase.from('well_events').insert({
        'user_id': userId,
        'family_id': familyId,
        'event_type': type,
        "title": type == "check_in"
            ? "Manual Check-in"
            : type == "safe_zone_enter"
            ? "Entered Safe Zone"
            : type == "safe_zone_exit"
            ? "Exited Safe Zone"
            : type == "heartbeat"
            ? "Heartbeat Alert"
            : type == "driving"
            ? "Driving Detected"
            : "Activity Update",

        "description": type == "check_in"
            ? "Check-in completed successfully"
            : type == "safe_zone_enter"
            ? "Has entered the safe zone"
            : type == "safe_zone_exit"
            ? "Has exited the safe zone"
            : type == "heartbeat"
            ? "Heartbeat event recorded"
            : type == "driving"
            ? "$fullName is currently driving"
            : "Activity recorded",
        'latitude': latitude,
        'longitude': longitude,
        'user_name': fullName,
        'battery_level': batteryLevel,
        'verification_source': 'app_foreground', // or 'background_service'
      });
    } else {
      await _supabase.from('well_events').insert({
        'user_id': userId,
        'family_id': familyId,
        'event_type': "Activity",
        "title": "Activity Update",

        "description": "Activity recorded",
        'latitude': latitude,
        'longitude': longitude,
        'user_name': fullName,
        'battery_level': batteryLevel,
        'verification_source': 'app_foreground', // or 'background_service'
      });
    }
    final members = await Supabase.instance.client
        .from('family_members')
        .select('user_id, role')
        .eq('family_id', familyId);
    if (type == 'check_in') {
      for (final m in members) {
        final targetUserId = m['user_id'];

        if (targetUserId == userId ||
            (m['role'] != "leader" && m['role'] != "monitor")) {
          continue;
        }
        try {
          await Supabase.instance.client.functions.invoke(
            'push-router',
            body: {
              "target_user_id": targetUserId,
              "title": "Check-In",
              "body": "${fullName ?? 'Someone'}: Checked in just now",
              "action": "check_in",
              "sound": "custom_sound",
            },
          );
        } catch (e) {
          print("Push failed: $e");
        }
      }
    }
    // if (type == 'safe_zone_enter') {
    //   for (final m in members) {
    //     final targetUserId = m['user_id'];
    //
    //     if (targetUserId == userId) continue;
    //
    //     try {
    //       await Supabase.instance.client.functions.invoke(
    //         'push-router',
    //         body: {
    //           "target_user_id": targetUserId,
    //           "title": "Safe zone entered",
    //           "body": "${fullName ?? 'Someone'}: Enter safe zone",
    //           "action": "check_in",
    //         },
    //       );
    //     } catch (e) {
    //       print("Push failed: $e");
    //     }
    //   }
    // }
  }

  // Trigger highest-level alarm state
  Future<void> triggerSiren(String familyId, String reason) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null)
      throw Exception('User not logged in — cannot trigger SOS');
    if (userId == null) return;
    final profileRes = await Supabase.instance.client
        .from('profiles')
        .select('full_name')
        .eq('id', userId)
        .single();
    final fullName = profileRes['full_name'];
    int batteryLevel =
        100; // Safe default for simulators and aggressive background iOS policies
    try {
      final battery = Battery();
      batteryLevel = await battery.batteryLevel;
    } catch (e) {
      debugPrint('Battery info not available over isolate, using default: $e');
    }
    await _supabase.from('well_events').insert({
      'user_id': userId,
      'family_id': familyId,
      'user_name': fullName,
      'event_type': 'sos',
      'title': '🚨 Emergency SOS',
      'description': reason,
      'metadata': {'reason': reason, 'status': 'active'},
      'battery_level': batteryLevel,
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

  Stream<List<Map<String, dynamic>>> streamFamilyLocation(String familyId) {
    return _supabase
        .from('live_locations')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId);
  }

  // Stream active family members
  Stream<List<Map<String, dynamic>>> streamActiveMembers(
    String familyId,
  ) async* {
    final stream = _supabase
        .from('family_members')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId);

    await for (final list in stream) {
      final activeList = list
          .where((item) => item['status'] == 'active')
          .toList();
      if (activeList.isEmpty) {
        yield [];
        continue;
      }

      final userIds = activeList.map((e) => e['user_id']).toSet().toList();
      try {
        final profiles = await _supabase
            .from('profiles')
            .select()
            .inFilter('id', userIds);
        final profileMap = {for (var p in profiles) p['id'] as String: p};

        final enriched = activeList.map((item) {
          final enrichedItem = Map<String, dynamic>.from(item);
          final profile = profileMap[item['user_id']];
          if (profile != null) {
            enrichedItem['full_name'] =
                profile['full_name'] ??
                '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
                    .trim();
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
  Stream<List<Map<String, dynamic>>> streamPendingMembers(
    String familyId,
  ) async* {
    final stream = _supabase
        .from('family_members')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId);

    await for (final list in stream) {
      final pendingList = list
          .where((item) => item['status'] == 'pending')
          .toList();
      if (pendingList.isEmpty) {
        yield [];
        continue;
      }

      final userIds = pendingList.map((e) => e['user_id']).toSet().toList();
      try {
        final profiles = await _supabase
            .from('profiles')
            .select()
            .inFilter('id', userIds);
        final profileMap = {for (var p in profiles) p['id'] as String: p};

        final enriched = pendingList.map((item) {
          final enrichedItem = Map<String, dynamic>.from(item);
          final profile = profileMap[item['user_id']];
          if (profile != null) {
            enrichedItem['full_name'] =
                profile['full_name'] ??
                '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
                    .trim();
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
  // Stream<Map<String, dynamic>?> streamMemberLatestEvent(String userId) {
  //   return _supabase
  //       .from('well_events')
  //       .stream(primaryKey: ['id'])
  //       .eq('user_id', userId)
  //       .order('created_at', ascending: false)
  //       // Note: Realtime streams don't support .not('latitude', 'is', null) server-side easily in the public schema without filters on stream
  //       // So we filter on the client side to only yield the first event that HAS a location
  //       .map((list) {
  //         try {
  //           return list.firstWhere(
  //             (evt) =>
  //                 evt['latitude'] != null &&
  //                 evt['longitude'] != null &&
  //                 evt['latitude'] != 0 &&
  //                 evt['longitude'] != 0,
  //           );
  //         } catch (_) {
  //           return null;
  //         }
  //       });
  // }
  // Stream<Map<String, dynamic>?> streamMemberLatestEvent(String userId) {
  //   return _supabase.from('well_events').stream(primaryKey: ['id']).map((rows) {
  //     final filtered = rows.where((evt) => evt['user_id'] == userId).toList();
  //
  //     if (filtered.isEmpty) return null;
  //
  //     filtered.sort(
  //       (a, b) => DateTime.parse(
  //         b['created_at'],
  //       ).compareTo(DateTime.parse(a['created_at'])),
  //     );
  //
  //     return filtered.first;
  //   });
  // }
  Stream<List<Map<String, dynamic>>> streamMemberEvents(String userId) async* {
    while (true) {
      try {
        final data = await _supabase
            .from('well_events')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false);

        yield List<Map<String, dynamic>>.from(data);
      } catch (e) {
        print("EVENTS STREAM ERROR => $e");
        yield [];
      }

      await Future.delayed(const Duration(seconds: 5));
    }
  }

  Stream<Map<String, dynamic>?> streamMemberLatestEvent(String userId) async* {
    while (true) {
      try {
        final data = await _supabase
            .from('well_events')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(1);

        //  print("LATEST EVENT QUERY => $data");

        if (data.isNotEmpty) {
          yield data.first;
        } else {
          yield null;
        }
      } catch (e) {
        print("EVENT STREAM ERROR => $e");
      }

      await Future.delayed(const Duration(seconds: 5));
    }
  }

  // Stream latest vitals for a specific member
  Stream<List<Map<String, dynamic>>> streamMemberVitals(String userId) {
    print("datadata");

    return _supabase
        .from('health_vitals')
        .stream(primaryKey: ['user_id', 'vital_type', 'timestamp'])
        .eq('user_id', userId)
        .order('timestamp', ascending: false)
        .limit(10);
  }

  // Stream<List<Map<String, dynamic>>> streamMemberVitals(String userId) {
  //   return _supabase
  //       .from('health_vitals')
  //       .stream(primaryKey: ['id'])
  //       .map(
  //         (data) => data.where((item) => item['user_id'] == userId).toList(),
  //       );
  // }

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
          .from('live_locations')
          .select()
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();
      return result;
    } catch (_) {
      return null;
    }
  }

  Stream<List<Map<String, dynamic>>> streamMyCheckinSchedules(String userId) {
    return Supabase.instance.client
        .from('checkin_schedules')
        .stream(primaryKey: ['id'])
        .eq('assigned_user_id', userId)
        .map(
          (data) => data.where((e) {
            return e['is_completed'] != true;
          }).toList(),
        );
  }

  Stream<List<Map<String, dynamic>>> streamLeaderSchedules(String familyId) {
    //final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Supabase.instance.client
        .from('checkin_schedules')
        .stream(primaryKey: ['id'])
        .map((data) {
          return data.where((e) {
            return e['family_id'] == familyId &&
                // e['checkin_date'] == today &&
                e['is_active'] == true &&
                e['is_completed'] != true;
          }).toList();
        });
  }
}

//
@riverpod
SafetyRepository safetyRepository(Ref ref) {
  return SafetyRepository(Supabase.instance.client);
}
