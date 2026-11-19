import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_branch_sdk/flutter_branch_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReferralService {
  ReferralService._();

  static final ReferralService instance = ReferralService._();

  final AppLinks _appLinks = AppLinks();

  StreamSubscription<Uri>? _subscription;

  static const String _referralKey = 'pending_referral_code';
  bool _initialized = false;

  Future<void> initialize() async {
    await initializeBranch();

    String? a = await getReferralCode();
    print("REFERRAL: initialize $a");
    // if (_initialized) {
    //   debugPrint('REFERRAL: already initialized');
    //   return;
    // }
    //
    // _initialized = true;
    // 1. Listen first for links when app is already running
    // _subscription = _appLinks.uriLinkStream.listen(
    //   (uri) async {
    //     print("REFERRAL: stream URI: $uri");
    //     await _handleUri(uri);
    //   },
    //   onError: (error) {
    //     print("REFERRAL: stream error: $error");
    //   },
    // );
    //
    // // 2. Then check the link that launched the app
    // try {
    //   final initialUri = await _appLinks.getInitialLink();
    //
    //   print("REFERRAL: initial URI: $initialUri");
    //
    //   if (initialUri != null) {
    //     await _handleUri(initialUri);
    //   }
    // } catch (e) {
    //   print("REFERRAL: initial error: $e");
    // }
  }

  Future<void> initializeBranch() async {
    if (_initialized) return;
    _initialized = true;
    FlutterBranchSdk.listSession().listen(
      (data) async {
        print("REFERRAL: branch session data: $data");
        await handleBranchData(data);
      },
      onError: (error) {
        print("REFERRAL: branch stream error: $error");
      },
    );
  }

  // Future<void> _handleBranchData(Map<dynamic, dynamic> data) async {
  //   if (data['+clicked_branch_link'] != true) return;
  //   final referralCode = data['ref_code'] as String?;
  //   if (referralCode == null || referralCode.isEmpty) return;
  //   print('Referral saved: $referralCode');
  //
  //   await saveReferralCode(referralCode);
  // }
  Future<void> handleBranchData(Map<dynamic, dynamic> data) async {
    final clicked = data['+clicked_branch_link'];
    final wasClicked = clicked == true || clicked == 1;
    print("wasClickedwasClicked");
    print(wasClicked);
    if (!wasClicked) return;
    print(data);
    final referralCode = data['ref_code'] as String?;
    if (referralCode == null || referralCode.isEmpty) return;

    print('Referral saved: $referralCode');
    final userId = Supabase.instance.client.auth.currentUser?.id;

    // if (userId != null) {
    //   return;
    // }
    await saveReferralCode(referralCode);
  }

  Future<void> _handleUri(Uri uri) async {
    print('Received referral URI: $uri');
    print("xxzxzxzxz");

    if (uri.pathSegments.length < 2) {
      return;
    }

    if (uri.pathSegments[0] != 'ref') {
      return;
    }

    final referralCode = uri.pathSegments[1];

    if (referralCode.isEmpty) {
      return;
    }

    await saveReferralCode(referralCode);

    print('Referral saved: $referralCode');
  }

  Future<void> saveReferralCode(String referralCode) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_referralKey, referralCode);
  }

  Future<String?> getReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_referralKey);
  }

  Future<void> clearReferralCode() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_referralKey);
  }

  void dispose() {
    _subscription?.cancel();
  }
}
