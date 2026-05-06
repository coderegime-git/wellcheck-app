// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shield_router.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(UserRole)
final userRoleProvider = UserRoleProvider._();

final class UserRoleProvider extends $NotifierProvider<UserRole, ShieldRole> {
  UserRoleProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'userRoleProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$userRoleHash();

  @$internal
  @override
  UserRole create() => UserRole();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShieldRole value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShieldRole>(value),
    );
  }
}

String _$userRoleHash() => r'0aabdaea51b0bcb224039f0754d3c22ca6c05143';

abstract class _$UserRole extends $Notifier<ShieldRole> {
  ShieldRole build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ShieldRole, ShieldRole>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ShieldRole, ShieldRole>,
              ShieldRole,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(shieldRouter)
final shieldRouterProvider = ShieldRouterProvider._();

final class ShieldRouterProvider
    extends $FunctionalProvider<GoRouter, GoRouter, GoRouter>
    with $Provider<GoRouter> {
  ShieldRouterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shieldRouterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shieldRouterHash();

  @$internal
  @override
  $ProviderElement<GoRouter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GoRouter create(Ref ref) {
    return shieldRouter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GoRouter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GoRouter>(value),
    );
  }
}

String _$shieldRouterHash() => r'5636ad13a1b7f658bfc260e940b4ed38b872c9d7';
