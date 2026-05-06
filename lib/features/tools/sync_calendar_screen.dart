import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
//import 'package:device_calendar/device_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

class SyncCalendarScreen extends ConsumerStatefulWidget {
  const SyncCalendarScreen({super.key});

  @override
  ConsumerState<SyncCalendarScreen> createState() => _SyncCalendarScreenState();
}

class _SyncCalendarScreenState extends ConsumerState<SyncCalendarScreen> {
  final DeviceCalendarPlugin _calendarPlugin = DeviceCalendarPlugin();
  List<Calendar> _calendars = [];
  String? _selectedCalendarId;
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _hasPermission = false;
  String? _lastSyncTime;
  int _syncedCount = 0;

  static const _prefKeyCalendarId = 'well_check_synced_calendar_id';
  static const _prefKeyLastSync = 'well_check_last_calendar_sync';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);

     // Check / request permissions
    var permResult = await _calendarPlugin.hasPermissions();
    if (permResult.isSuccess && !(permResult.data ?? false)) {
      permResult = await _calendarPlugin.requestPermissions();
    }

    final granted = permResult.isSuccess && (permResult.data ?? false);
    setState(() => _hasPermission = granted);

    if (granted) {
      await _loadCalendars();
    }

    // Load persisted selection
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_prefKeyCalendarId);
    final lastSync = prefs.getString(_prefKeyLastSync);

    setState(() {
      _selectedCalendarId = savedId;
      _lastSyncTime = lastSync;
      _isLoading = false;
    });
  }

  Future<void> _loadCalendars() async {
    final result = await _calendarPlugin.retrieveCalendars();
    if (result.isSuccess && result.data != null) {
      // Filter to writable calendars (null-safe check — iOS sometimes reports isReadOnly as null)
      var writable = result.data!
          .where((c) => c.isReadOnly != true)
          .toList();

      // Fallback: if no writable calendars found, show all calendars
      // so the user can still see what's available
      if (writable.isEmpty && result.data!.isNotEmpty) {
        writable = result.data!.toList();
        debugPrint('[CalendarSync] No writable calendars found, showing all ${writable.length} calendars');
      }

      setState(() => _calendars = writable);
    }
  }

  Future<void> _toggleCalendar(String calendarId) async {
    final prefs = await SharedPreferences.getInstance();

    if (_selectedCalendarId == calendarId) {
      // Disconnect
      await prefs.remove(_prefKeyCalendarId);
      setState(() => _selectedCalendarId = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Calendar disconnected.'),
            backgroundColor: Colors.grey,
          ),
        );
      }
    } else {
      // Connect and sync
      await prefs.setString(_prefKeyCalendarId, calendarId);
      setState(() => _selectedCalendarId = calendarId);
      await _syncEvents(calendarId);
    }
  }

  Future<void> _syncEvents(String calendarId) async {
    setState(() {
      _isSyncing = true;
      _syncedCount = 0;
    });

    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile');

      // Fetch all upcoming events from Supabase
      // final events = await Supabase.instance.client
      //     .from('calendar_events')
      //     .select()
      //     .eq('family_id', profile.familyId)
      //     .gte('event_datetime', DateTime.now().toUtc().toIso8601String())
      //     .order('event_datetime', ascending: true);
      final now = DateTime.now().toUtc().subtract(const Duration(days: 1));

      final events = await Supabase.instance.client
          .from('calendar_events')
          .select()
          .eq('family_id', profile.familyId)
          .gte('event_datetime', now.toIso8601String())
          .order('event_datetime', ascending: true);

      int count = 0;
      for (final evt in events) {
        final title = evt['title'] as String? ?? 'Well-Check Event';
        final dtStr = evt['event_datetime'] as String;
        final notes = evt['notes'] as String?;

        final startDt = DateTime.parse(dtStr).toLocal();
        final endDt = startDt.add(const Duration(hours: 1)); // Default 1hr

        final event = Event(
          calendarId,
          title: title,
          start: tz.TZDateTime.from(startDt, tz.local),
          end: tz.TZDateTime.from(endDt, tz.local),
          description: notes ?? 'Synced from Well-Check Family Shield',
        );

        final result = await _calendarPlugin.createOrUpdateEvent(event);
        if (result?.isSuccess ?? false) {
          count++;
        }
      }

      // Save sync timestamp
      final prefs = await SharedPreferences.getInstance();
      final noww = DateFormat.yMd().add_jm().format(DateTime.now());
      await prefs.setString(_prefKeyLastSync, noww);

      setState(() {
        _syncedCount = count;
        _lastSyncTime = noww;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Synced $count event${count != 1 ? 's' : ''} to calendar!'),
            backgroundColor: ShieldColors.safeZoneGreen,
          ),
        );
      }
    } catch (e) {
      debugPrint('[CalendarSync] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Unified Family Schedule',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: ShieldColors.activeTeal,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Link your personal calendar to automatically sync family appointments and medication windows.',
                    style: TextStyle(color: ShieldColors.textLabel),
                  ),
                  const SizedBox(height: 8),
                  if (_lastSyncTime != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: ShieldColors.activeTeal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle,
                              color: ShieldColors.safeZoneGreen, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Last sync: $_lastSyncTime ($_syncedCount events)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: ShieldColors.textBody,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  if (!_hasPermission)
                    _buildPermissionDenied()
                  else if (_calendars.isEmpty)
                    _buildNoCalendars()
                  else
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Available Calendars',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Select a calendar to sync Well-Check events to:',
                            style: TextStyle(
                              fontSize: 13,
                              color: ShieldColors.textLabel,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _calendars.length,
                              itemBuilder: (context, index) {
                                final cal = _calendars[index];
                                final isConnected =
                                    _selectedCalendarId == cal.id;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: ShieldDesign.roundedTwelve,
                                    side: isConnected
                                        ? const BorderSide(
                                            color: ShieldColors.activeTeal,
                                            width: 2)
                                        : BorderSide.none,
                                  ),
                                  child: ListTile(
                                    leading: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Color(cal.color ?? 0xFF007F80),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.calendar_month,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                    title: Text(
                                      cal.name ?? 'Unnamed Calendar',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      isConnected
                                          ? 'Syncing Active'
                                          : cal.accountName ?? 'Local',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isConnected
                                            ? ShieldColors.safeZoneGreen
                                            : ShieldColors.textLabel,
                                        fontWeight: isConnected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    trailing: _isSyncing &&
                                            _selectedCalendarId == cal.id
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: ShieldColors.activeTeal,
                                            ),
                                          )
                                        : Switch(
                                            value: isConnected,
                                            activeThumbColor:
                                                ShieldColors.activeTeal,
                                            onChanged: _isSyncing
                                                ? null
                                                : (_) => _toggleCalendar(
                                                    cal.id!),
                                          ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (_hasPermission && _selectedCalendarId != null)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSyncing
                            ? null
                            : () => _syncEvents(_selectedCalendarId!),
                        icon: _isSyncing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.sync),
                        label: Text(
                            _isSyncing ? 'Syncing...' : 'SYNC NOW'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ShieldColors.activeTeal,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: ShieldDesign.roundedTwelve,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(
                            color: ShieldColors.activeTeal),
                        shape: RoundedRectangleBorder(
                          borderRadius: ShieldDesign.roundedTwelve,
                        ),
                      ),
                      child: const Text(
                        'RETURN TO COMMAND CENTER',
                        style: TextStyle(color: ShieldColors.activeTeal),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPermissionDenied() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'Calendar Access Required',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please grant calendar permission in Settings to sync your family events.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ShieldColors.textLabel),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _initialize,
              style: ElevatedButton.styleFrom(
                backgroundColor: ShieldColors.activeTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: ShieldDesign.roundedTwelve,
                ),
              ),
              child: const Text('TRY AGAIN'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoCalendars() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'No Calendars Found',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Make sure you have at least one calendar account (iCloud, Google, etc.) configured on this device.\n\n'
              'Go to Settings → Calendar → Accounts to add one.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ShieldColors.textLabel),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _initialize,
              icon: const Icon(Icons.refresh),
              label: const Text('RETRY'),
              style: ElevatedButton.styleFrom(
                backgroundColor: ShieldColors.activeTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: ShieldDesign.roundedTwelve,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
