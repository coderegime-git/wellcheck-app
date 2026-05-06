import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';

part 'calendar_provider.g.dart';

class CalendarEvent {
  final String id;
  final String title;
  final DateTime eventDatetime;
  final String? location;
  final List<String> participants;
  final String? notes;

  CalendarEvent({
    required this.id,
    required this.title,
    required this.eventDatetime,
    this.location,
    required this.participants,
    this.notes,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: json['id'] as String,
      title: json['title'] as String,
      eventDatetime: DateTime.parse(json['event_datetime'] as String).toLocal(),
      location: json['location'] as String?,
      participants: List<String>.from(json['participants'] ?? []),
      notes: json['notes'] as String?,
    );
  }
}

@riverpod
Stream<List<CalendarEvent>> familyCalendarEvents(Ref ref) async* {
  final profile = await ref.watch(currentUserProfileProvider.future);
  if (profile == null) {
    yield [];
    return;
  }

  final supabase = Supabase.instance.client;
  yield* supabase
      .from('calendar_events')
      .stream(primaryKey: ['id'])
      .eq('family_id', profile.familyId)
      .order('event_datetime', ascending: true) // Soonest first
      .map((events) => events.map((e) => CalendarEvent.fromJson(e)).toList());
}
