// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'calendar_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(familyCalendarEvents)
final familyCalendarEventsProvider = FamilyCalendarEventsProvider._();

final class FamilyCalendarEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CalendarEvent>>,
          List<CalendarEvent>,
          Stream<List<CalendarEvent>>
        >
    with
        $FutureModifier<List<CalendarEvent>>,
        $StreamProvider<List<CalendarEvent>> {
  FamilyCalendarEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'familyCalendarEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$familyCalendarEventsHash();

  @$internal
  @override
  $StreamProviderElement<List<CalendarEvent>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<CalendarEvent>> create(Ref ref) {
    return familyCalendarEvents(ref);
  }
}

String _$familyCalendarEventsHash() =>
    r'b208cdadaf9a663df1edef2c5eb16461966fa80d';
