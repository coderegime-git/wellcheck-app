import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/referral_repository.dart';
import '../../core/navigation/shield_router.dart';
import '../../core/notifications/push_notification_service.dart';
import '../../services/referral_service.dart';
import '../safety/services/purchase_services.dart';

class WellCheckPaywallScreen extends ConsumerStatefulWidget {
  const WellCheckPaywallScreen({super.key});

  @override
  ConsumerState<WellCheckPaywallScreen> createState() =>
      _WellCheckPaywallScreenState();
}

class _WellCheckPaywallScreenState
    extends ConsumerState<WellCheckPaywallScreen> {
  bool _failed = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _presentPaywall());
  }

  void _handleFailure() {
    if (!mounted) return;
    if (_attempt < 2) {
      _attempt++;
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _presentPaywall();
      });
    } else {
      setState(() => _failed = true);
    }
  }

  // Future<void> _presentPaywall() async {
  //   // final offerings = await Purchases.getOfferings();
  //   // final supabaseUserId = Supabase.instance.client.auth.currentUser?.id;
  //   // if (supabaseUserId != null) {
  //   //   await Purchases.logIn(supabaseUserId);
  //   // }
  //   //
  //   // final result = await RevenueCatUI.presentPaywall(
  //   //   offering: offerings.getOffering("premium_monthly"),
  //   // );
  //   final offerings = await Purchases.getOfferings();
  //   print("Current offering: ${offerings.current?.identifier}");
  //   print("Available packages: ${offerings.current?.availablePackages}");
  //
  //   final supabaseUserId = Supabase.instance.client.auth.currentUser?.id;
  //   if (supabaseUserId != null) {
  //     await Purchases.logIn(supabaseUserId);
  //   }
  //
  //   final result = await RevenueCatUI.presentPaywall(
  //     offering: offerings.current,
  //     displayCloseButton: false,
  //     presentationConfiguration: PaywallPresentationConfiguration(
  //       ios: IOSPaywallPresentationStyle.fullScreen,
  //     ),
  //   );
  //   if (!mounted) return;
  //   final customerInfo = await Purchases.getCustomerInfo();
  //
  //   final hasSubscription =
  //       customerInfo.entitlements.active.containsKey('WellCheck Pro') ||
  //       customerInfo.entitlements.active.containsKey('WellCheck Premium');
  //
  //   if (result == PaywallResult.purchased ||
  //       result == PaywallResult.restored ||
  //       hasSubscription) {
  //     if (mounted) context.go('/dashboard');
  //   } else {
  //     final prefs = await SharedPreferences.getInstance();
  //     await prefs.setBool('priv_biometric', false);
  //     await prefs.setBool('is_logged_in', false);
  //
  //     PushNotificationService.saveTokenToProfile(null);
  //     FlutterBackgroundService().invoke('stopService');
  //
  //     try {
  //       await PurchasesService.instance.logOut();
  //     } catch (e) {
  //       debugPrint('[RC] logOut skipped: $e');
  //     }
  //
  //     ref.read(shieldRouterProvider).go('/');
  //   }
  // }
  Future<void> _presentPaywall() async {
    try {
      if (_failed && mounted) setState(() => _failed = false);

      if (!await Purchases.isConfigured) {
        throw Exception('Purchases not configured yet');
      }
      final offerings = await Purchases.getOfferings();

      print("Current offering: ${offerings.current?.identifier}");
      print("Available packages: ${offerings.current?.availablePackages}");

      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;

      if (userId == null) {
        debugPrint('[Referral] User not logged in');
        _handleFailure();
        return;
      }

      await Purchases.logIn(userId);

      final result = await RevenueCatUI.presentPaywall(
        offering: offerings.current,
        displayCloseButton: false,
        customVariables: {},
        presentationConfiguration: PaywallPresentationConfiguration(
          ios: IOSPaywallPresentationStyle.fullScreen,
        ),
      );

      if (!mounted) return;
      if (result == PaywallResult.notPresented ||
          result == PaywallResult.error) {
        debugPrint('[RC] Paywall not presented: $result');
        _handleFailure();
        return;
      }
      // ---------------------------------------------------------
      // CHECK PURCHASE
      // ---------------------------------------------------------
      await Purchases.invalidateCustomerInfoCache();

      var customerInfo = await Purchases.getCustomerInfo();
      print("customerInfocustomerInfo1223");
      print(customerInfo);
      var hasSubscription =
          customerInfo.entitlements.active.containsKey('WellCheck Pro') ||
          customerInfo.entitlements.active.containsKey('WellCheck Premium');
      if (!hasSubscription) {
        try {
          debugPrint('[RC] No entitlement. Trying restore...');

          customerInfo = await Purchases.restorePurchases();
          print("customerInfocustomerInfo");
          print(customerInfo);
          hasSubscription =
              customerInfo.entitlements.active.containsKey('WellCheck Pro') ||
              customerInfo.entitlements.active.containsKey('WellCheck Premium');

          debugPrint(
            '[RC] Active entitlements after restore: '
            '${customerInfo.entitlements.active.keys}',
          );
        } catch (e) {
          debugPrint('[RC] Restore failed: $e');
        }
      }
      if (result == PaywallResult.purchased ||
          result == PaywallResult.restored ||
          hasSubscription) {
        debugPrint('[Payment] Subscription successful');

        // -------------------------------------------------------
        // CHECK REFERRAL
        // -------------------------------------------------------

        final referralCode = await ReferralService.instance.getReferralCode();

        debugPrint('[Referral] Saved referral code: $referralCode');
        final prefs = await SharedPreferences.getInstance();
        bool isNew = prefs.getBool('is_new_user') ?? false;

        // if (isNew) {
        //   if (referralCode != null && referralCode.isNotEmpty) {
        //     try {
        //       // ---------------------------------------------------
        //       // Get purchased product/plan
        //       // ---------------------------------------------------
        //
        //       double? planPrice;
        //       String? planId;
        //
        //       if (customerInfo.entitlements.active.containsKey(
        //         'WellCheck Pro',
        //       )) {
        //         planId = 'wellcheck_pro';
        //
        //         // Change this if your actual Pro price is different.
        //         planPrice = 5.99;
        //       } else if (customerInfo.entitlements.active.containsKey(
        //         'WellCheck Premium',
        //       )) {
        //         planId = 'wellcheck_premium';
        //
        //         // Change this if your actual Premium price is different.
        //         planPrice = 7.99;
        //       }
        //
        //       if (planId != null && planPrice != null) {
        //         debugPrint(
        //           '[Referral] Creating commission '
        //           'code=$referralCode '
        //           'plan=$planId '
        //           'price=$planPrice',
        //         );
        //
        //         final response = await supabase.functions.invoke(
        //           'create-referral-commission',
        //           body: {
        //             'user_id': userId,
        //             'referral_code': referralCode,
        //             'plan_id': planId,
        //             'plan_price': planPrice,
        //           },
        //         );
        //
        //         debugPrint('[Referral] Commission response: ${response.data}');
        //
        //         if (response.data != null && response.data['success'] == true) {
        //           // Clear referral only after commission was
        //           // successfully processed.
        //           await ReferralService.instance.clearReferralCode();
        //           await prefs.setBool('is_new_user', false);
        //
        //           debugPrint('[Referral] Commission successfully created');
        //         }
        //       }
        //     } catch (e, stackTrace) {
        //       // Commission failure MUST NOT prevent the user
        //       // from entering the dashboard.
        //       debugPrint('[Referral] Commission creation failed: $e');
        //       debugPrint(stackTrace.toString());
        //     }
        //   }
        // } else {
        //   debugPrint('[Referral] No referral code. No commission.');
        // }
        //
        // // -------------------------------------------------------
        // // GO DASHBOARD
        // // -------------------------------------------------------
        //
        // if (mounted) {
        //   context.go('/dashboard');
        // }
        //
        // return;
        if (result == PaywallResult.purchased ||
            result == PaywallResult.restored ||
            hasSubscription) {
          debugPrint('[Payment] Subscription successful');
          // -------------------------------------------------------
          // CHECK REFERRAL
          // -------------------------------------------------------

          final referralCode = await ReferralService.instance.getReferralCode();

          debugPrint('[Referral] Saved referral code: $referralCode');
          final prefs = await SharedPreferences.getInstance();
          bool isNew = prefs.getBool('is_new_user') ?? false;

          // Commission only applies to a genuine new purchase —
          // never for restores or pre-existing subscriptions.
          final isGenuinePurchase =
              result == PaywallResult.purchased &&
              _isRecentPurchase(customerInfo);
          print(result);
          print("resultresultresult");
          print(_isRecentPurchase(customerInfo));
          if (isNew && isGenuinePurchase) {
            if (referralCode != null && referralCode.isNotEmpty) {
              try {
                // ---------------------------------------------------
                // Get purchased product/plan
                // ---------------------------------------------------
                await ReferralRepository().associateReferral(userId: userId);
                double? planPrice;
                String? planId;

                if (customerInfo.entitlements.active.containsKey(
                  'WellCheck Pro',
                )) {
                  planId = 'wellcheck_pro';

                  // Change this if your actual Pro price is different.
                  planPrice = 5.99;
                } else if (customerInfo.entitlements.active.containsKey(
                  'WellCheck Premium',
                )) {
                  planId = 'wellcheck_premium';

                  // Change this if your actual Premium price is different.
                  planPrice = 7.99;
                }

                if (planId != null && planPrice != null) {
                  debugPrint(
                    '[Referral] Creating commission '
                    'code=$referralCode '
                    'plan=$planId '
                    'price=$planPrice',
                  );

                  final response = await supabase.functions.invoke(
                    'create-referral-commission',
                    body: {
                      'user_id': userId,
                      'referral_code': referralCode,
                      'plan_id': planId,
                      'plan_price': planPrice,
                    },
                  );

                  debugPrint(
                    '[Referral] Commission response: ${response.data}',
                  );

                  if (response.data != null &&
                      response.data['success'] == true) {
                    // Clear referral only after commission was
                    // successfully processed.
                    await ReferralService.instance.clearReferralCode();
                    await prefs.setBool('is_new_user', false);

                    debugPrint('[Referral] Commission successfully created');
                  }
                }
              } catch (e, stackTrace) {
                // Commission failure MUST NOT prevent the user
                // from entering the dashboard.
                debugPrint('[Referral] Commission creation failed: $e');
                debugPrint(stackTrace.toString());
              }
            }
          } else if (isNew && !isGenuinePurchase) {
            await prefs.setBool('is_new_user', false);
            debugPrint(
              '[Referral] Subscription via restore/existing — no commission.',
            );
          } else {
            await prefs.setBool('is_new_user', false);
            debugPrint('[Referral] No referral code. No commission.');
          }

          // -------------------------------------------------------
          // GO DASHBOARD
          // -------------------------------------------------------

          if (mounted) {
            context.go('/dashboard');
          }

          return;
        }
      }

      // ---------------------------------------------------------
      // PAYMENT NOT COMPLETED
      // ---------------------------------------------------------

      final prefs = await SharedPreferences.getInstance();

      //await prefs.setBool('priv_biometric', false);
      // await prefs.setBool('is_logged_in', false);

      PushNotificationService.saveTokenToProfile(null);

      FlutterBackgroundService().invoke('stopService');

      try {
        await PurchasesService.instance.logOut();
      } catch (e) {
        debugPrint('[RC] logOut skipped: $e');
      }
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        ref.read(shieldRouterProvider).go('/');
      }
    } catch (e, stackTrace) {
      debugPrint('[Payment] Paywall error: $e');
      debugPrint(stackTrace.toString());
      _handleFailure();
    }
  }

  bool _isRecentPurchase(CustomerInfo customerInfo) {
    final activeEntitlement =
        customerInfo.entitlements.active.values.firstOrNull;
    if (activeEntitlement == null) return false;

    print(
      "activeEntitlement.originalPurchaseDate ${activeEntitlement!.originalPurchaseDate}",
    );
    //
    print(
      "activeEntitlement.latestPurchaseDate ${activeEntitlement.latestPurchaseDate}",
    );

    final original = DateTime.tryParse(activeEntitlement.latestPurchaseDate);
    if (original == null) return false;

    final diff = DateTime.now().toUtc().difference(original.toUtc());

    // Original purchase must be recent — proves this is a brand new
    // subscription, not an existing one reused under a shared Apple ID.
    return diff.inSeconds.abs() < 300;
  }

  //

  // @override
  // Widget build(BuildContext context) {
  // return const Scaffold(
  //   backgroundColor: Color(0xFF007F80),
  //   // ← teal so the 1-second flash matches RC's sheet bg
  //   body: Center(child: CircularProgressIndicator(color: Colors.white)),
  // );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: _failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Unable to load subscription plans.',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      _attempt = 0;
                      _presentPaywall();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              )
            : const CircularProgressIndicator(color: Color(0xFF007F80)),
      ),
    );
  }
}
