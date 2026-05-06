// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'medication_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(familyMedications)
final familyMedicationsProvider = FamilyMedicationsProvider._();

final class FamilyMedicationsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Medication>>,
          List<Medication>,
          Stream<List<Medication>>
        >
    with $FutureModifier<List<Medication>>, $StreamProvider<List<Medication>> {
  FamilyMedicationsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'familyMedicationsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$familyMedicationsHash();

  @$internal
  @override
  $StreamProviderElement<List<Medication>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Medication>> create(Ref ref) {
    return familyMedications(ref);
  }
}

String _$familyMedicationsHash() => r'46fc0a865099d0dbf62a8ac509c08c0d8688849e';

@ProviderFor(allDoseLogs)
final doseLogsProvider = DoseLogsFamily._();

final class DoseLogsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<DoseLog>>,
          List<DoseLog>,
          Stream<List<DoseLog>>
        >
    with $FutureModifier<List<DoseLog>>, $StreamProvider<List<DoseLog>> {
  DoseLogsProvider._({
    required DoseLogsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'doseLogsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$doseLogsHash();

  @override
  String toString() {
    return r'doseLogsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<DoseLog>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<DoseLog>> create(Ref ref) {
    final argument = this.argument as String;
    return allDoseLogs(ref);
  }

  @override
  bool operator ==(Object other) {
    return other is DoseLogsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$doseLogsHash() => r'7a692c110a00ffed5b16ae44a97e080dc0468a22';

final class DoseLogsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<DoseLog>>, String> {
  DoseLogsFamily._()
    : super(
        retry: null,
        name: r'doseLogsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  DoseLogsProvider call(String medicationId) =>
      DoseLogsProvider._(argument: medicationId, from: this);

  @override
  String toString() => r'doseLogsProvider';
}
