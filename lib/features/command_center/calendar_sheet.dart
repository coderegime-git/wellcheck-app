import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/features/command_center/add_event_sheet.dart';
import 'package:well_check_v3/core/data/calendar_provider.dart';

class CalendarSheet extends ConsumerStatefulWidget {
  const CalendarSheet({super.key});

  @override
  ConsumerState<CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends ConsumerState<CalendarSheet> {
  Future<void> _deleteEvent(BuildContext context, String id) async {
    try {
      await Supabase.instance.client
          .from('calendar_events')
          .delete()
          .eq('id', id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<void> _deleteCalendarEvent(
    CalendarEvent event,
    BuildContext context,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Event?'),
          content: Text('Are you sure you want to delete "${event.title}"?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client
          .from('calendar_events')
          .delete()
          .eq('id', event.id);

      if (!context.mounted) return;
      final eventsAsync = ref.invalidate(familyCalendarEventsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event deleted successfully')),
      );

      // Refresh your calendar/event list here.
      setState(() {});
    } catch (e) {
      debugPrint('Failed to delete calendar event: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete event: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(familyCalendarEventsProvider);

    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: ShieldColors.backgroundWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        // constraints: BoxConstraints(
        //   //  maxHeight: MediaQuery.of(context).size.height * 0.85,
        // ),
        child: Column(
          // mainAxisSize: MainAxisSize.min,
          children: [
            // Container(
            //   width: 40,
            //   height: 4,
            //   margin: const EdgeInsets.only(bottom: 24),
            //   decoration: BoxDecoration(
            //     color: Colors.grey.shade300,
            //     borderRadius: BorderRadius.circular(2),
            //   ),
            // ),
            Row(
              //  mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Family Calendar',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Spacer(),
                IconButton(
                  padding: EdgeInsets.all(0),
                  visualDensity: VisualDensity(horizontal: -3),
                  icon: const Icon(
                    Icons.add_circle,
                    color: ShieldColors.activeTeal,
                    size: 30,
                  ),
                  onPressed: () async {
                    // await showModalBottomSheet(
                    //   context: context,
                    //   isScrollControlled: true,
                    //   backgroundColor: Colors.transparent,
                    //   builder: (context) => const AddEventSheet(),
                    // );
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => AddEventSheet()),
                    );
                    final eventsAsync = ref.invalidate(
                      familyCalendarEventsProvider,
                    );
                  },
                ),
                IconButton(
                  icon: Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),

                    child: const Icon(
                      Icons.close,
                      color: Colors.black,
                      size: 18,
                    ),
                  ),
                  onPressed: () async {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: eventsAsync.when(
                data: (events) {
                  if (events.isEmpty) {
                    return const Center(
                      child: Text(
                        'No upcoming events.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      final isPast = event.eventDatetime.isBefore(
                        DateTime.now(),
                      );
                      final color = isPast
                          ? Colors.grey
                          : ShieldColors.activeTeal;

                      return Dismissible(
                        key: Key(event.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: ShieldColors.alertRed,
                            borderRadius: ShieldDesign.roundedTwelve,
                          ),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => _deleteEvent(context, event.id),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: ShieldDesign.roundedTwelve,
                            side: BorderSide(
                              color: color.withValues(alpha: 0.3),
                            ),
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 12,
                              height: double.infinity,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: const BorderRadius.horizontal(
                                  left: Radius.circular(12),
                                ),
                              ),
                            ),
                            title: Text(
                              event.title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                decoration: isPast
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${DateFormat.yMMMd().format(event.eventDatetime)} at ${DateFormat.jm().format(event.eventDatetime)}',
                                ),
                                if (event.location != null &&
                                    event.location!.isNotEmpty)
                                  Text('📍 ${event.location}'),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              color: Colors.white,
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  // Edit calendar event
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          AddEventSheet(event: event),
                                    ),
                                  );
                                  final eventsAsync = ref.invalidate(
                                    familyCalendarEventsProvider,
                                  );
                                } else if (value == 'delete') {
                                  // Delete calendar event
                                  _deleteCalendarEvent(event, context);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem<String>(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.edit,
                                        color: ShieldColors.activeTeal,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Edit',
                                        style: TextStyle(
                                          color: ShieldColors.activeTeal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Delete',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text('Error: $err')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
