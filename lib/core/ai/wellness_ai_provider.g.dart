// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wellness_ai_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(wellnessAi)
final wellnessAiProvider = WellnessAiProvider._();

final class WellnessAiProvider
    extends
        $FunctionalProvider<
          WellnessAiService,
          WellnessAiService,
          WellnessAiService
        >
    with $Provider<WellnessAiService> {
  WellnessAiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'wellnessAiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$wellnessAiHash();

  @$internal
  @override
  $ProviderElement<WellnessAiService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WellnessAiService create(Ref ref) {
    return wellnessAi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WellnessAiService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WellnessAiService>(value),
    );
  }
}

String _$wellnessAiHash() => r'27810c2bfca0818033508b232524efaa955726c5';
