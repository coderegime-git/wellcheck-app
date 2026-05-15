import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'user_profile_provider.g.dart';

class UserProfile {
  final String userId;
  final String familyId;
  final String role;
  final String? phone;
  final String? fullName; // From joined profiles view
  final String? avatarUrl; // From joined profiles view

  UserProfile({
    required this.userId,
    required this.familyId,
    required this.role,
    this.fullName,
    this.phone,
    this.avatarUrl,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['user_id'] as String,
      familyId: json['family_id'] as String,
      role: json['role'] as String,
      phone: json['phone'] as String?,
      fullName: json['full_name'] as String?, // May be null if not joined
      avatarUrl: json['avatar_url'] as String?, // May be null if not joined
    );
  }
}

@riverpod
Future<UserProfile?> currentUserProfile(Ref ref) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;

  if (userId == null) return null;

  // We fetch the family_members record that corresponds to the active user
  // We use postgrest inner join syntax to pull the associated profile's full_name
  try {
    final response = await supabase
        .from('family_members')
        .select('*, profiles(full_name, avatar_url)')
        .eq('user_id', userId)
        .limit(1)
        .maybeSingle();

    if (response != null) {
      // Flatten the payload before handing it to the generic fromJson
      final profileData = response['profiles'] as Map<String, dynamic>?;
      response['full_name'] = profileData?['full_name'];
      response['avatar_url'] = profileData?['avatar_url'];

      final profile = UserProfile.fromJson(response);

      // Persist for background isolate access
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_user_id', profile.userId);
      await prefs.setString('last_family_id', profile.familyId);

      return profile;
    }
  } catch (e) {
    // If it throws a PostgrestException, likely due to RLS, it means the row might not exist
    // for this user or they haven't joined a family.
    debugPrint('Error fetching profile: $e');
  }

  return null;
}
