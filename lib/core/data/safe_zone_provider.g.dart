// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'safe_zone_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(familySafeZones)
final familySafeZonesProvider = FamilySafeZonesProvider._();

final class FamilySafeZonesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SafeZone>>,
          List<SafeZone>,
          Stream<List<SafeZone>>
        >
    with $FutureModifier<List<SafeZone>>, $StreamProvider<List<SafeZone>> {
  FamilySafeZonesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'familySafeZonesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$familySafeZonesHash();

  @$internal
  @override
  $StreamProviderElement<List<SafeZone>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<SafeZone>> create(Ref ref) {
    return familySafeZones(ref);
  }
}

String _$familySafeZonesHash() => r'32d8395bb801d5883ceb3127a3e2de0e45c6f6ab';
