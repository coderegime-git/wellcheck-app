import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'auth_repository.g.dart';

class AuthRepository {
  final SupabaseClient _supabase;

  AuthRepository(this._supabase);

  // Magic Link Registration / Login
  Future<void> signInWithMagicLink(String email, String password) async {
    //
    await _supabase.auth.signInWithOtp(
      email: email,
      //  password: password,
      emailRedirectTo: 'io.supabase.wellcheck://login-callback/',
    );
  }

  Future<void> signInWithPassword(String email, String password) async {
    print("passwordpassword");
    await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
      // emailRedirectTo: 'io.supabase.wellcheck://login-callback/',
    );
  }

  // Verify PIN
  Future<void> verifyOTP(String email, String token) async {
    await _supabase.auth.verifyOTP(
      type: OtpType.email,
      email: email,
      token: token,
    );
  }

  Future<void> createFamilyWithRole(
    String familyName,
    String roleString,
  ) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    // 1. Insert Family
    final familyResponse = await _supabase
        .from('families')
        .insert({'name': familyName})
        .select('id')
        .single();

    final familyId = familyResponse['id'];

    // 2. Assign root leader
    await _supabase.from('family_members').insert({
      'family_id': familyId,
      'user_id': userId,
      'role': roleString,
      'status': 'active', // Leader is instantly active
    });
  }

  // Generate a secure 6-digit invite code
  Future<String> createInviteCode(String familyId, String roleString) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    final random = Random();
    String code = (100000 + random.nextInt(900000)).toString();

    await _supabase.from('family_invites').insert({
      'family_id': familyId,
      'code': code,
      'role': roleString,
      'created_by': userId,
    });

    return code;
  }

  // Join a shield using a 6-digit code via the secure RPC function
  Future<void> joinFamilyWithPin(String code) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await _supabase.rpc('join_family_with_code', params: {'invite_code': code});
  }

  // Stream current user auth state
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
}

@riverpod
AuthRepository authRepository(Ref ref) {
  return AuthRepository(Supabase.instance.client);
}

final sessionProvider = FutureProvider<Session?>((ref) async {
  // Give Supabase time to restore session from shared_preferences
  final completer = Completer<Session?>();

  final subscription = Supabase.instance.client.auth.onAuthStateChange.listen((
    data,
  ) {
    if (!completer.isCompleted) {
      completer.complete(data.session);
    }
  });

  // Timeout after 3 seconds — if no event, session is truly null
  Future.delayed(const Duration(seconds: 3), () {
    if (!completer.isCompleted) {
      completer.complete(Supabase.instance.client.auth.currentSession);
    }
  });

  final session = await completer.future;
  subscription.cancel();
  return session;
});
