import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../features/safety/services/purchase_services.dart';

// ── State ──────────────────────────────────────────────────────────────────

class SubscriptionState {
  final CustomerInfo? customerInfo;
  final bool isLoading;

  const SubscriptionState({this.customerInfo, this.isLoading = true});

  bool get isWellCheckPro =>
      customerInfo?.entitlements.active.containsKey('WellCheck Pro') ?? false;

  SubscriptionState copyWith({CustomerInfo? customerInfo, bool? isLoading}) {
    return SubscriptionState(
      customerInfo: customerInfo ?? this.customerInfo,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// ── Notifier ───────────────────────────────────────────────────────────────

class SubscriptionNotifier extends AsyncNotifier<SubscriptionState> {
  @override
  Future<SubscriptionState> build() async {
    final customerInfo = await PurchasesService.instance.getCustomerInfo();

    // Keep in sync with RC push updates
    Purchases.addCustomerInfoUpdateListener((info) {
      state = AsyncData(
        SubscriptionState(customerInfo: info, isLoading: false),
      );
    });

    return SubscriptionState(customerInfo: customerInfo, isLoading: false);
  }

  Future<void> refresh() async {
    final customerInfo = await PurchasesService.instance.getCustomerInfo();
    state = AsyncData(
      SubscriptionState(customerInfo: customerInfo, isLoading: false),
    );
  }
}

final subscriptionProvider =
AsyncNotifierProvider<SubscriptionNotifier, SubscriptionState>(
  SubscriptionNotifier.new,
);