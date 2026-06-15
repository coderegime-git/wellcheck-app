import 'dart:async';
import 'dart:developer';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../config/rc_config.dart';

class PurchasesService {
  PurchasesService._();
  static final PurchasesService instance = PurchasesService._();

  // ──────────────────────────────────────────────
  // Identity
  // ──────────────────────────────────────────────

  /// Call after a user logs in (e.g. Supabase auth success).
  /// Merges anonymous purchase history with the identified user.
  Future<void> identifyUser(String userId) async {
    try {
      final logInResult = await Purchases.logIn(userId);
      log('[RC] Identified user: $userId | created: ${logInResult.created}');
    } on PlatformException catch (e) {
      log('[RC] identifyUser error: ${e.message}', error: e);
    }
  }

  /// Call on logout.
  Future<void> logOut() async {
    try {
      await Purchases.logOut();
      log('[RC] Logged out, reverted to anonymous user');
    } on PlatformException catch (e) {
      log('[RC] logOut error: ${e.message}', error: e);
    }
  }

  // ──────────────────────────────────────────────
  // Customer Info
  // ──────────────────────────────────────────────

  /// Fetch the latest CustomerInfo from RevenueCat.
  Future<CustomerInfo?> getCustomerInfo() async {
    try {
      return await Purchases.getCustomerInfo();
    } on PlatformException catch (e) {
      log('[RC] getCustomerInfo error: ${e.message}', error: e);
      return null;
    }
  }

  /// Listen to real-time customer info updates.
  /// Attach this stream to a StreamBuilder or a ChangeNotifier.
  Stream<CustomerInfo> get customerInfoStream {
    late StreamController<CustomerInfo> controller;
    CustomerInfoUpdateListener? listener;

    controller = StreamController<CustomerInfo>.broadcast(
      onListen: () {
        listener = (customerInfo) => controller.add(customerInfo);
        Purchases.addCustomerInfoUpdateListener(listener!);
      },
      onCancel: () {
        if (listener != null) {
          Purchases.removeCustomerInfoUpdateListener(listener!);
        }
        controller.close();
      },
    );

    return controller.stream;
  }

  // ──────────────────────────────────────────────
  // Entitlement Checking
  // ──────────────────────────────────────────────

  /// Returns true if the current user has an active WellCheck Pro entitlement.
  Future<bool> hasWellCheckPro() async {
    final info = await getCustomerInfo();
    return _isProActive(info);
  }

  bool _isProActive(CustomerInfo? info) {
    if (info == null) return false;
    return info.entitlements.active
        .containsKey(RCConfig.entitlementWellCheckPro);
  }

  // ──────────────────────────────────────────────
  // Offerings & Manual Purchase (fallback)
  // ──────────────────────────────────────────────

  /// Fetch the current offering from RevenueCat.
  Future<Offering?> getCurrentOffering() async {
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current;
    } on PlatformException catch (e) {
      log('[RC] getOfferings error: ${e.message}', error: e);
      return null;
    }
  }

  /// Purchase a specific package (e.g. from a custom paywall UI).
  /// Returns updated CustomerInfo on success, null on failure.
  Future<CustomerInfo?> purchasePackage(Package package) async {
    try {
      final result = await Purchases.purchasePackage(package);
      return result.customerInfo;
    } on PlatformException catch (e) {
      if (e.code == PurchasesErrorCode.purchaseCancelledError.index.toString()) {
        log('[RC] Purchase cancelled by user');
        return null;
      }
      log('[RC] purchasePackage error: ${e.message}', error: e);
      rethrow;
    }
  }

  /// Restore previous purchases (required button in settings per Apple / Google guidelines).
  Future<CustomerInfo?> restorePurchases() async {
    try {
      final info = await Purchases.restorePurchases();
      log('[RC] Restore complete. Active: ${info.entitlements.active.keys}');
      return info;
    } on PlatformException catch (e) {
      log('[RC] restorePurchases error: ${e.message}', error: e);
      rethrow;
    }
  }
}