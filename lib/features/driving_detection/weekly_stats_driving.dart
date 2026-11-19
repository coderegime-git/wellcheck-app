// life360_driving_report.dart
//
// Feature: Weekly driving report, matching Life360's driver report cards.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';

class WeeklyDrivingStats {
  final int tripCount;
  final double totalDistanceKm;
  final Duration totalDrivingTime;
  final double topSpeedKmh;
  final int hardBrakeCount;
  final int rapidAccelCount;
  final int speedingEvents;
  final Duration speedingDuration;
  final int distractedEvents;

  const WeeklyDrivingStats({
    required this.tripCount,
    required this.totalDistanceKm,
    required this.totalDrivingTime,
    required this.topSpeedKmh,
    required this.hardBrakeCount,
    required this.rapidAccelCount,
    required this.speedingEvents,
    required this.speedingDuration,
    required this.distractedEvents,
  });

  static const empty = WeeklyDrivingStats(
    tripCount: 0,
    totalDistanceKm: 0,
    totalDrivingTime: Duration.zero,
    topSpeedKmh: 0,
    hardBrakeCount: 0,
    rapidAccelCount: 0,
    speedingEvents: 0,
    speedingDuration: Duration.zero,
    distractedEvents: 0,
  );
}

class DrivingReportRepository {
  DrivingReportRepository(this._supabase);

  final SupabaseClient _supabase;

  // Future<WeeklyDrivingStats> fetchWeeklyStats(String userId) async {
  //   final since = DateTime.now().subtract(const Duration(days: 7));
  //   final rows = await _supabase
  //       .from('driving_trips')
  //       .select()
  //       .eq('user_id', userId)
  //       .eq('status', 'completed')
  //       .gte('start_time', since.toIso8601String());
  //
  //   if (rows.isEmpty) return WeeklyDrivingStats.empty;
  //
  //   double totalDistance = 0;
  //   int totalSeconds = 0;
  //   double topSpeed = 0;
  //   int hardBrakes = 0;
  //   int rapidAccels = 0;
  //   int speedingEvents = 0;
  //   int speedingSeconds = 0;
  //   int distractedEvents = 0;
  //
  //   for (final r in rows) {
  //     totalDistance += (r['distance_km'] as num?)?.toDouble() ?? 0;
  //     topSpeed = topSpeed < ((r['max_speed_kmh'] as num?)?.toDouble() ?? 0)
  //         ? (r['max_speed_kmh'] as num).toDouble()
  //         : topSpeed;
  //     hardBrakes += (r['hard_brake_count'] as int?) ?? 0;
  //     rapidAccels += (r['rapid_accel_count'] as int?) ?? 0;
  //     speedingEvents += (r['speeding_events'] as int?) ?? 0;
  //     speedingSeconds += (r['speeding_duration_sec'] as int?) ?? 0;
  //     distractedEvents += (r['distracted_events'] as int?) ?? 0;
  //
  //     final start = DateTime.tryParse(r['start_time'] as String? ?? '');
  //     final end = DateTime.tryParse(r['end_time'] as String? ?? '');
  //     if (start != null && end != null) {
  //       totalSeconds += end.difference(start).inSeconds;
  //     }
  //   }
  //
  //   return WeeklyDrivingStats(
  //     tripCount: rows.length,
  //     totalDistanceKm: totalDistance,
  //     totalDrivingTime: Duration(seconds: totalSeconds),
  //     topSpeedKmh: topSpeed,
  //     hardBrakeCount: hardBrakes,
  //     rapidAccelCount: rapidAccels,
  //     speedingEvents: speedingEvents,
  //     speedingDuration: Duration(seconds: speedingSeconds),
  //     distractedEvents: distractedEvents,
  //   );
  // }
  Future<WeeklyDrivingStats> fetchWeeklyStats(String userId) async {
    final since = DateTime.now().subtract(const Duration(days: 7));

    final rows = await _supabase
        .from('driving_trips')
        .select()
        .eq('user_id', userId)
        .eq('status', 'completed')
        .gte('start_time', since.toIso8601String());

    if (rows.isEmpty) return WeeklyDrivingStats.empty;

    double totalDistance = 0;
    int totalSeconds = 0;
    double topSpeed = 0;
    int hardBrakes = 0;
    int rapidAccels = 0;
    int speedingEvents = 0;
    int speedingSeconds = 0;
    int distractedEvents = 0;

    for (final r in rows) {
      final distanceKm = (r['distance_km'] as num?)?.toDouble() ?? 0.0;

      final maxSpeedKmh = (r['max_speed_kmh'] as num?)?.toDouble() ?? 0.0;

      final hardBrakeCount = (r['hard_brake_count'] as num?)?.toInt() ?? 0;

      final rapidAccelCount = (r['rapid_accel_count'] as num?)?.toInt() ?? 0;

      final speedingEventCount = (r['speeding_events'] as num?)?.toInt() ?? 0;

      final speedingDurationSec =
          (r['speeding_duration_sec'] as num?)?.toInt() ?? 0;

      final distractedEventCount =
          (r['distracted_events'] as num?)?.toInt() ?? 0;

      totalDistance += distanceKm;

      if (maxSpeedKmh > topSpeed) {
        topSpeed = maxSpeedKmh;
      }

      hardBrakes += hardBrakeCount;
      rapidAccels += rapidAccelCount;
      speedingEvents += speedingEventCount;
      speedingSeconds += speedingDurationSec;
      distractedEvents += distractedEventCount;

      final start = DateTime.tryParse(r['start_time'] as String? ?? '');

      final end = DateTime.tryParse(r['end_time'] as String? ?? '');

      if (start != null && end != null) {
        totalSeconds += end.difference(start).inSeconds;
      }
    }
    //

    return WeeklyDrivingStats(
      tripCount: rows.length,
      totalDistanceKm: totalDistance,
      totalDrivingTime: Duration(seconds: totalSeconds),
      topSpeedKmh: topSpeed,
      hardBrakeCount: hardBrakes,
      rapidAccelCount: rapidAccels,
      speedingEvents: speedingEvents,
      speedingDuration: Duration(seconds: speedingSeconds),
      distractedEvents: distractedEvents,
    );
  }
}

// ---------------------------------------------------------------------------
// PER-MEMBER SUMMARY (for the family-wide report screen)
// ---------------------------------------------------------------------------

class MemberDrivingSummary {
  final String userId;
  final String name;
  final Color color;
  final WeeklyDrivingStats stats;

  const MemberDrivingSummary({
    required this.userId,
    required this.name,
    required this.color,
    required this.stats,
  });

  int get riskyEvents =>
      stats.hardBrakeCount +
      stats.rapidAccelCount +
      stats.speedingEvents +
      stats.distractedEvents;
}

/// Family-wide report matching Life360's "Weekly Driving Report" screen:
/// top category badges, Top Speed / Drives+mi twin cards, then one summary
/// card per family member.
class WeeklyDrivingReportScreen extends StatefulWidget {
  const WeeklyDrivingReportScreen({
    super.key,
    required this.members, // [(userId, name, color), ...] — your family roster
    required this.repository,
  });

  final List<({String userId, String name, Color color})> members;
  final DrivingReportRepository repository;

  @override
  State<WeeklyDrivingReportScreen> createState() =>
      _WeeklyDrivingReportScreenState();
}

class _WeeklyDrivingReportScreenState extends State<WeeklyDrivingReportScreen> {
  List<MemberDrivingSummary>? _summaries;
  late String? selectedUserName = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final summaries = await Future.wait(
      widget.members.map((m) async {
        final stats = await widget.repository.fetchWeeklyStats(m.userId);
        return MemberDrivingSummary(
          userId: m.userId,
          name: m.name,
          color: m.color,
          stats: stats,
        );
      }),
    );
    final selectedMember = widget.members.first;

    selectedUserName = selectedMember.name;
    final selectedUserColor = selectedMember.color;
    if (mounted) setState(() => _summaries = summaries);
  }

  void _showTopSpeedPopup(
    BuildContext context, {
    required String userName,
    required double topSpeed,
  }) {
    final firstLetter = userName.trim().isNotEmpty
        ? userName.trim()[0].toUpperCase()
        : '?';

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Top Speed',
      barrierColor: Colors.black.withOpacity(0.65),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: EdgeInsets.all(25),
                margin: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Stack(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar
                        if (firstLetter.isNotEmpty && topSpeed >= 80) ...[
                          Container(
                            width: 50,
                            height: 50,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.green,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              firstLetter,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          const SizedBox(height: 28),
                        ],
                        const Text(
                          'Top Speed',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 12),
                        if (firstLetter.isNotEmpty && topSpeed >= 80) ...[
                          Text.rich(
                            TextSpan(
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.45,
                                color: Colors.black,
                              ),
                              children: [
                                const TextSpan(text: 'This week, '),
                                TextSpan(
                                  text: userName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const TextSpan(
                                  text:
                                      ' had the fastest recorded speed '
                                      'in the Circle at ',
                                ),
                                TextSpan(
                                  text: '${topSpeed.toStringAsFixed(0)} mph.',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 32),

                        const Text(
                          'What is Top Speed?',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 12),

                        const Text(
                          'Shows the fastest speed recorded by any '
                          'Circle member during their drives this week. '
                          'This metric helps you understand driving '
                          'patterns across your Circle.',
                          style: TextStyle(fontSize: 14.5, height: 1.45),
                        ),

                        const SizedBox(height: 32),

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF332B3D),
                              foregroundColor: Colors.white,
                              elevation: 5,
                              shadowColor: Colors.black26,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: const Text(
                              'Got it',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Close button
                    Positioned(
                      top: 10,
                      right: 5,
                      child: Material(
                        color: Colors.white,
                        elevation: 4,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.pop(context),
                          child: const SizedBox(
                            width: 25,
                            height: 25,
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showIncidentPopup(
    BuildContext context, {
    required String title,
    required int count,
    required String? userName,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: title,
      barrierColor: Colors.black.withOpacity(0.65),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        final hasUser = userName != null && userName!.trim().isNotEmpty;

        final firstLetter = hasUser ? userName!.trim()[0].toUpperCase() : '?';
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.only(left: 24, right: 24, bottom: 16),
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(36),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: color, size: 22),
                        ),

                        const SizedBox(width: 14),

                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        Container(
                          // top: 10,
                          // right: 5,
                          child: Material(
                            color: Colors.white,
                            elevation: 4,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => Navigator.pop(context),
                              child: const SizedBox(
                                width: 25,
                                height: 25,
                                child: Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),
                    if (hasUser) ...[
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          firstLetter,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      Text(
                        userName!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 6),
                    ],
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: Colors.black,
                        ),
                        children: [
                          TextSpan(
                            text: '$count',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: ' incidents this week',
                            style: TextStyle(color: Colors.grey.shade800),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 26),

                    Text(
                      'What is $title?',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 26),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF332B3D),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: const Text(
                          'Got it',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDrivingStatsBottomSheet(BuildContext context, dynamic s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.70,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Column(
                        children: [
                          // Drag handle
                          Container(
                            width: 42,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Header
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: s.color.withValues(
                                  alpha: 0.15,
                                ),
                                child: Text(
                                  s.name.isNotEmpty
                                      ? s.name[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    color: s.color,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),

                              const SizedBox(width: 14),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.name,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Driving Statistics',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              Material(
                                color: Colors.white,
                                elevation: 3,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => Navigator.pop(context),
                                  child: const SizedBox(
                                    width: 25,
                                    height: 25,
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // Summary title
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Driving Summary',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),

                  // Summary cards
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverGrid(
                      delegate: SliverChildListDelegate([
                        _DrivingStatCard(
                          icon: Icons.directions_car_rounded,
                          title: 'Total Drives',
                          value: '${s.stats.tripCount}',
                        ),

                        _DrivingStatCard(
                          icon: Icons.route_rounded,
                          title: 'Distance',
                          value:
                              '${(s.stats.totalDistanceKm * 0.621371).toStringAsFixed(1)} mi',
                        ),

                        _DrivingStatCard(
                          icon: Icons.speed_rounded,
                          title: 'Top Speed',
                          value:
                              '${s.stats.topSpeedKmh.toStringAsFixed(1)} km/h',
                        ),

                        _DrivingStatCard(
                          icon: Icons.warning_amber_rounded,
                          title: 'Risky Events',
                          value: '${s.riskyEvents}',
                        ),
                      ]),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.35,
                          ),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Driving Behavior',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 12),

                          _DrivingEventCard(
                            icon: Icons.speed_rounded,
                            title: 'Speeding',
                            value: '${s.stats.speedingEvents}',
                          ),

                          _DrivingEventCard(
                            icon: Icons.pan_tool_alt_rounded,
                            title: 'Hard Braking',
                            value: '${s.stats.hardBrakeCount}',
                          ),

                          _DrivingEventCard(
                            icon: Icons.bolt_rounded,
                            title: 'Rapid Acceleration',
                            value: '${s.stats.rapidAccelCount}',
                          ),

                          _DrivingEventCard(
                            icon: Icons.phone_android_rounded,
                            title: 'Distracted Driving',
                            value: '${s.stats.distractedEvents}',
                          ),

                          const SizedBox(height: 22),

                          const Text(
                            'Safety Overview',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 12),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 5,
                                  spreadRadius: 0.5,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                              //   border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: ShieldColors.activeTeal.withValues(
                                      alpha: 0.10,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.shield_outlined,
                                    color: ShieldColors.activeTeal,
                                  ),
                                ),

                                const SizedBox(width: 14),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Risky Events',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${s.riskyEvents} events recorded',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                Text(
                                  '${s.riskyEvents}',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final summaries = _summaries;
    if (summaries == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Family-wide totals across every member.
    final topSpeed = summaries.fold<double>(
      0,
      (acc, s) => s.stats.topSpeedKmh > acc ? s.stats.topSpeedKmh : acc,
    );
    final totalDrives = summaries.fold<int>(0, (a, s) => a + s.stats.tripCount);
    final totalMiles = summaries.fold<double>(
      0,
      (a, s) => a + s.stats.totalDistanceKm * 0.621371,
    );

    final totalSpeeding = summaries.fold<int>(
      0,
      (a, s) => a + s.stats.speedingEvents,
    );
    final totalHardBrake = summaries.fold<int>(
      0,
      (a, s) => a + s.stats.hardBrakeCount,
    );
    final totalRapidAccel = summaries.fold<int>(
      0,
      (a, s) => a + s.stats.rapidAccelCount,
    );
    final totalDistracted = summaries.fold<int>(
      0,
      (a, s) => a + s.stats.distractedEvents,
    );
    final topSpeedMember = summaries.reduce(
      (a, b) => a.stats.topSpeedKmh > b.stats.topSpeedKmh ? a : b,
    );
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        titleSpacing: 10,
        title: const Text(
          'Weekly Driving Report',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const SizedBox(height: 16),

            // Category badge row.
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _showIncidentPopup(
                        context,
                        title: 'Speeding',
                        count: totalSpeeding,
                        userName: selectedUserName,
                        description:
                            'Captures when a vehicle exceeds 80 mph for at least 30 seconds. '
                            'Going over 80 mph is considered a high-risk speed.',
                        icon: Icons.warning_amber,
                        color: Colors.redAccent,
                      );
                    },
                    child: _CategoryBadge(
                      icon: Icons.warning_amber,
                      color: Colors.redAccent,
                      count: totalSpeeding,
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _showIncidentPopup(
                        context,
                        title: 'Hard Braking',
                        count: totalHardBrake,
                        userName: selectedUserName,
                        description:
                            'Shown when the vehicle comes to an abrupt stop or hits the '
                            'brakes aggressively. Hard braking may be a sign of distracted '
                            'driving or speeding.',
                        icon: Icons.report_gmailerrorred,
                        color: Colors.lightBlue,
                      );
                    },
                    child: _CategoryBadge(
                      icon: Icons.report_gmailerrorred,
                      color: Colors.lightBlue,
                      count: totalHardBrake,
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _showIncidentPopup(
                        context,
                        title: 'Rapid Acceleration',
                        count: totalRapidAccel,
                        userName: selectedUserName,
                        description:
                            'Identifies a sudden burst of speed in a short amount of time. '
                            'Rapid acceleration can be a possible sign of reckless or '
                            'distracted driving.',
                        icon: Icons.bolt,
                        color: Colors.pinkAccent,
                      );
                    },
                    child: _CategoryBadge(
                      icon: Icons.bolt,
                      color: Colors.pinkAccent,
                      count: totalRapidAccel,
                    ),
                  ),
                ),

                // const SizedBox(width: 10),
                //
                // Expanded(
                //   child: GestureDetector(
                //     onTap: () {
                //       _showIncidentPopup(
                //         context,
                //         title: 'Distracted',
                //         count: totalDistracted,
                //         userName: selectedUserName,
                //         description:
                //             'Detects texting, phone calls, social app or other use of the '
                //             'phone while driving. It will not detect use when the vehicle '
                //             'is stopped or with a hands-free device.',
                //         icon: Icons.phone_android,
                //         color: Colors.amber,
                //       );
                //     },
                //     child: _CategoryBadge(
                //       icon: Icons.phone_android,
                //       color: Colors.amber,
                //       count: totalDistracted,
                //     ),
                //   ),
                // ),
              ],
            ),
            const SizedBox(height: 20),
            // Top Speed / Drives + Total mi cards
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showTopSpeedPopup(
                      context,
                      userName: topSpeedMember.name,
                      topSpeed: topSpeed,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 8,
                            spreadRadius: 0,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Circular avatar
                          if (topSpeedMember.name.isNotEmpty &&
                              topSpeed >= 80) ...[
                            Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.green,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                topSpeedMember.name.isNotEmpty
                                    ? topSpeedMember.name
                                          .trim()[0]
                                          .toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),

                            const SizedBox(width: 14),
                          ],

                          // Top speed information
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Top Speed',
                                  style: TextStyle(fontSize: 14),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${topSpeed.toStringAsFixed(0)} mph',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          spreadRadius: 0,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Drives'),
                            Text(
                              '$totalDrives',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total mi'),
                            Text(
                              totalMiles.toStringAsFixed(1),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Top Speed / Drives+mi twin cards.
            // Row(
            //   crossAxisAlignment: CrossAxisAlignment.stretch,
            //   children: [
            //     Expanded(
            //       child: _InfoCard(
            //         child: Row(
            //           children: [
            //             const CircleAvatar(
            //               radius: 16,
            //               backgroundColor: Colors.green,
            //               child: Text(
            //                 'A',
            //                 style: TextStyle(color: Colors.white, fontSize: 12),
            //               ),
            //             ),
            //             const SizedBox(width: 10),
            //             Expanded(
            //               child: Column(
            //                 crossAxisAlignment: CrossAxisAlignment.start,
            //                 children: [
            //                   const Text('Top Speed'),
            //                   Text(
            //                     '${topSpeed.toStringAsFixed(0)} mph',
            //                     style: const TextStyle(
            //                       fontWeight: FontWeight.bold,
            //                       fontSize: 16,
            //                     ),
            //                   ),
            //                 ],
            //               ),
            //             ),
            //           ],
            //         ),
            //       ),
            //     ),
            //     const SizedBox(width: 10),
            //     Expanded(
            //       child: _InfoCard(
            //         child: Column(
            //           crossAxisAlignment: CrossAxisAlignment.start,
            //           children: [
            //             Row(
            //               mainAxisAlignment: MainAxisAlignment.spaceBetween,
            //               children: [
            //                 const Text('Drives'),
            //                 Text(
            //                   '$totalDrives',
            //                   style: const TextStyle(
            //                     fontWeight: FontWeight.bold,
            //                   ),
            //                 ),
            //               ],
            //             ),
            //             const SizedBox(height: 6),
            //             Row(
            //               mainAxisAlignment: MainAxisAlignment.spaceBetween,
            //               children: [
            //                 const Text('Total mi'),
            //                 Text(
            //                   totalMiles.toStringAsFixed(0),
            //                   style: const TextStyle(
            //                     fontWeight: FontWeight.bold,
            //                   ),
            //                 ),
            //               ],
            //             ),
            //           ],
            //         ),
            //       ),
            //     ),
            //   ],
            // ),
            const SizedBox(height: 16),

            // Per-member cards.
            ...summaries.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  onTap: () {
                    _showDrivingStatsBottomSheet(context, s);
                  },
                  child: _InfoCard(
                    child: Row(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: s.color.withValues(alpha: 0.15),
                              child: Text(
                                s.name.isNotEmpty
                                    ? s.name[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: s.color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: CircleAvatar(
                                radius: 12,
                                backgroundColor: Colors.deepPurple,
                                child: const Icon(
                                  Icons.lock,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                s.stats.tripCount == 0
                                    ? 'No drives yet'
                                    : '${s.stats.tripCount} drive${s.stats.tripCount == 1 ? '' : 's'} • '
                                          '${(s.stats.totalDistanceKm * 0.621371).toStringAsFixed(1)} mi',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.lock,
                                    size: 14,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${s.riskyEvents} Risky Events',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({
    required this.icon,
    required this.color,
    required this.count,
  });

  final IconData icon;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 6),
          Text('$count', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      // color: Theme.of(context).colorScheme.surface,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            spreadRadius: 1,
            offset: const Offset(0, 3),
          ),
        ],
      ),

      //  elevation: 1,
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class _DrivingStatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _DrivingStatCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 3,
            spreadRadius: 0.5,
            offset: const Offset(0, 3),
          ),
        ],
        borderRadius: BorderRadius.circular(18),
        // border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: ShieldColors.activeTeal.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: ShieldColors.activeTeal),
          ),

          const Spacer(),

          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 2),

          Text(
            title,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _DrivingEventCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _DrivingEventCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 3,
            spreadRadius: 0.5,
            offset: const Offset(0, 2),
          ),
        ],
        borderRadius: BorderRadius.circular(16),
        //border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: ShieldColors.activeTeal),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),

          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
