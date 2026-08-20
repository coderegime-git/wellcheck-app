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

import '../../core/navigation/shield_router.dart';
import '../../core/notifications/push_notification_service.dart';
import '../safety/services/purchase_services.dart';

class WellCheckPaywallScreen extends ConsumerStatefulWidget {
  const WellCheckPaywallScreen({super.key});

  @override
  ConsumerState<WellCheckPaywallScreen> createState() =>
      _WellCheckPaywallScreenState();
}

class _WellCheckPaywallScreenState
    extends ConsumerState<WellCheckPaywallScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _presentPaywall());
  }

  Future<void> _presentPaywall() async {
    // final offerings = await Purchases.getOfferings();
    // final supabaseUserId = Supabase.instance.client.auth.currentUser?.id;
    // if (supabaseUserId != null) {
    //   await Purchases.logIn(supabaseUserId);
    // }
    //
    // final result = await RevenueCatUI.presentPaywall(
    //   offering: offerings.getOffering("premium_monthly"),
    // );
    final offerings = await Purchases.getOfferings();
    print("Current offering: ${offerings.current?.identifier}");
    print("Available packages: ${offerings.current?.availablePackages}");

    final supabaseUserId = Supabase.instance.client.auth.currentUser?.id;
    if (supabaseUserId != null) {
      await Purchases.logIn(supabaseUserId);
    }

    final result = await RevenueCatUI.presentPaywall(
      offering: offerings.current,
      displayCloseButton: false,
      presentationConfiguration: PaywallPresentationConfiguration(
        ios: IOSPaywallPresentationStyle.fullScreen,
      ),
    );
    if (!mounted) return;
    final customerInfo = await Purchases.getCustomerInfo();

    final hasSubscription =
        customerInfo.entitlements.active.containsKey('WellCheck Pro') ||
        customerInfo.entitlements.active.containsKey('WellCheck Premium');

    if (result == PaywallResult.purchased ||
        result == PaywallResult.restored ||
        hasSubscription) {
      if (mounted) context.go('/dashboard');
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('priv_biometric', false);
      await prefs.setBool('is_logged_in', false);

      PushNotificationService.saveTokenToProfile(null);
      FlutterBackgroundService().invoke('stopService');

      try {
        await PurchasesService.instance.logOut();
      } catch (e) {
        debugPrint('[RC] logOut skipped: $e');
      }

      ref.read(shieldRouterProvider).go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF007F80),
      // ← teal so the 1-second flash matches RC's sheet bg
      body: Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}
