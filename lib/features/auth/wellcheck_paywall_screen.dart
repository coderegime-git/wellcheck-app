import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WellCheckPaywallScreen extends StatefulWidget {
  const WellCheckPaywallScreen({super.key});

  @override
  State<WellCheckPaywallScreen> createState() => _WellCheckPaywallScreenState();
}

class _WellCheckPaywallScreenState extends State<WellCheckPaywallScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _presentPaywall());
  }

  Future<void> _presentPaywall() async {
    final offerings = await Purchases.getOfferings();
    print("RC availablePackages:");

    print(offerings.current?.availablePackages);
    final supabaseUserId = Supabase.instance.client.auth.currentUser?.id;
    if (supabaseUserId != null) {
      await Purchases.logIn(supabaseUserId);
      print("RC identified as: $supabaseUserId");
    }

    final result = await RevenueCatUI.presentPaywall(
      offering: offerings.getOffering("premium_monthly"),
    );

    if (!mounted) return;
    final customerInfo = await Purchases.getCustomerInfo();

    final hasSubscription =
        customerInfo.entitlements.active.containsKey('WellCheck Pro') ||
        customerInfo.entitlements.active.containsKey('WellCheck Premium');

    if (result == PaywallResult.purchased ||
        result == PaywallResult.restored ||
        hasSubscription) {
      context.go('/dashboard');
    } else {
      await Supabase.instance.client.auth.signOut();
      if (mounted) context.go('/');
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
