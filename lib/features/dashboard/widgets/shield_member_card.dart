import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';

class ShieldMemberCard extends StatelessWidget {
  final String name;
  final String status;
  final List<Map<String, String>> metrics;
  final IconData subStatusIcon;
  final String subStatusText;
  final bool isAlert;
  final bool isReadOnly;
  final VoidCallback? onTap;
  final String? avatarUrl;
  final String? title;
  final String? description;

  // ── New: bottom stat chips ────────────────────────────────────────────────
  /// Pass the raw battery level (int/double) from lastEvent['battery_level'].
  final num? batteryLevel;

  /// Pass vitals list from streamMemberVitals so the card can read HR & SpO2.
  final List<Map<String, dynamic>> vitals;

  /// Number of check-in events (filter externally: events.where(...).length).
  final int checkInCount;

  /// Whether any heartbeat / event was received at all.
  final bool isActive;

  const ShieldMemberCard({
    super.key,
    required this.name,
    required this.status,
    required this.metrics,
    required this.subStatusIcon,
    required this.subStatusText,
    this.isAlert = false,
    this.isReadOnly = false,
    this.onTap,
    this.avatarUrl,
    this.title,
    this.description,
    // stat chip params
    this.batteryLevel,
    this.vitals = const [],
    this.checkInCount = 0,
    this.isActive = false,
  });

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _batteryColor() {
    if (batteryLevel == null) return Colors.grey;
    final v = batteryLevel!.toDouble();
    if (v <= 20) return Colors.red;
    if (v <= 50) return Colors.orange;
    return const Color(0xFF2ECC71);
  }

  String _heartRateLabel() {
    final hrEntry = vitals
        .where((v) => v['vital_type'] == 'HEART_RATE')
        .toList();
    if (hrEntry.isEmpty) return '--';
    final hrVal = hrEntry.first['value'];
    final hrNum = (hrVal is num)
        ? hrVal.round()
        : (double.tryParse(hrVal.toString())?.round() ?? 0);
    return '$hrNum';
  }

  String _spo2Label() {
    final spo2Entry = vitals
        .where((v) => v['vital_type'] == 'BLOOD_OXYGEN')
        .toList();
    if (spo2Entry.isEmpty) return '--';
    final spo2Val = spo2Entry.first['value'];
    final spo2Num = (spo2Val is num)
        ? spo2Val.round()
        : (double.tryParse(spo2Val.toString())?.round() ?? 0);
    return '$spo2Num%';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isReadOnly ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isAlert ? const Color(0xFFFFF3E0) : Colors.white,
          borderRadius: ShieldDesign.roundedTwelve,
          boxShadow: [
            BoxShadow(
              color: isAlert
                  ? ShieldColors.urgentRed.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isAlert
                        ? ShieldColors.urgentRed.withValues(alpha: 0.1)
                        : ShieldColors.softMint,
                    shape: BoxShape.circle,
                    image: avatarUrl != null
                        ? DecorationImage(
                            image: CachedNetworkImageProvider(
                              '$avatarUrl?t=${DateTime.now().minute}',
                            ),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: avatarUrl == null
                      ? Icon(
                          isAlert ? Icons.face : Icons.person,
                          color: isAlert
                              ? ShieldColors.urgentRed
                              : ShieldColors.activeTeal,
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: ShieldColors.textBody,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        status,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 12.5,
                          color: isAlert
                              ? ShieldColors.urgentRed
                              : ShieldColors.activeTeal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Icon(
                          //   Icons.monitor_heart,
                          //   color: isAlert
                          //       ? ShieldColors.urgentRed
                          //       : ShieldColors.activeTeal,
                          //   size: 18,
                          // ),
                          // const SizedBox(width: 8),
                          if (title != "" &&
                              description != "" &&
                              title != null &&
                              description != null) ...[
                            RichText(
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                children: [
                                  if (name != null && name != '')
                                    TextSpan(
                                      text: '$name - ',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                        fontSize: 12,
                                      ),
                                    ),

                                  TextSpan(
                                    text: title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: ShieldColors.activeTeal,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              description ?? "",
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontSize: 12,
                                    color: Colors.grey,
                                    fontWeight: isAlert
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                            ),
                          ] else ...[
                            Text(
                              subStatusText ?? "",
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: isAlert
                                        ? ShieldColors.urgentRed
                                        : ShieldColors.textBody,
                                    fontWeight: isAlert
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (!isReadOnly)
                  Icon(
                    isAlert ? Icons.help_outline : Icons.check_circle,
                    color: isAlert
                        ? ShieldColors.textLabel
                        : ShieldColors.activeTeal,
                    size: 28,
                  ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Metrics container ─────────────────────────────────────────
            // if (metrics.isNotEmpty)
            //   Container(
            //     padding: const EdgeInsets.symmetric(vertical: 16),
            //     decoration: BoxDecoration(
            //       color: isAlert
            //           ? Colors.white.withValues(alpha: 0.5)
            //           : const Color(0xFFF8F9FA),
            //       borderRadius: ShieldDesign.roundedTwelve,
            //     ),
            //     child: Row(
            //       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            //       children: metrics.map((metric) {
            //         return _buildMetric(
            //           context,
            //           metric['label']!,
            //           metric['value']!,
            //           metric['unit']!,
            //         );
            //       }).toList(),
            //     ),
            //   ),
            //
            // if (metrics.isNotEmpty) const SizedBox(height: 12),
            Divider(),
            // ── Stats chip strip ──────────────────────────────────────────
            _buildStatsStrip(context),
          ],
        ),
      ),
    );
  }

  // ── Stats strip ───────────────────────────────────────────────────────────

  Widget _buildStatsStrip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
      decoration: BoxDecoration(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatChip(
            context,
            bgColor: Colors.red,
            icon: Icons.favorite_rounded,
            color: Colors.red.shade400,
            value: _heartRateLabel(),
            label: 'Heart Rate',
            unit: vitals.any((v) => v['vital_type'] == 'HEART_RATE')
                ? 'BPM'
                : '',
          ),
          //   _buildDivider(),
          _buildStatChip(
            bgColor: Colors.green,

            context,
            icon: CupertinoIcons.battery_75_percent,
            color: _batteryColor(),
            value: batteryLevel != null ? '$batteryLevel' : '--',
            label: 'Battery',
            unit: batteryLevel != null ? '%' : '',
          ),
          // _buildDivider(),
          _buildStatChip(
            bgColor: Colors.blue,

            context,
            icon: Icons.how_to_reg_rounded,
            color: Colors.blue.shade400,
            value: '$checkInCount',
            label: 'Check-ins',
            unit: '',
          ),
          // _buildDivider(),
          _buildStatChip(
            bgColor: Colors.green,

            context,
            icon: Icons.shield_moon,
            color: isActive ? ShieldColors.activeTeal : Colors.grey,
            value: isActive ? 'Active' : 'Offline',
            label: 'Status',
            unit: '',
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 36,
      color: ShieldColors.activeTeal.withValues(alpha: 0.15),
    );
  }

  Widget _buildStatChip(
    BuildContext context, {
    required IconData icon,
    required Color bgColor,
    required Color color,
    required String value,
    required String label,
    required String unit,
  }) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.all(2),
        padding: EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: bgColor.withAlpha(25),
          // color: isAlert
          //     ? Colors.white.withValues(alpha: 0.4)
          //     : const Color(0xFFF0FAF8),
          borderRadius: ShieldDesign.roundedTwelve,
          // border: Border.all(
          //   color: isAlert
          //       ? ShieldColors.urgentRed.withValues(alpha: 0.12)
          //       : ShieldColors.activeTeal.withValues(alpha: 0.15),
          // ),
        ),

        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 18),
                SizedBox(width: 3),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: value,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: ShieldColors.textBody,
                          fontSize: 13,
                        ),
                      ),
                      if (unit.isNotEmpty)
                        TextSpan(
                          text: unit,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: ShieldColors.textLabel,
                                fontSize: 10,
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            //const SizedBox(height: 4),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: ShieldColors.textLabel,
                fontSize: 10,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Metric tile (unchanged) ───────────────────────────────────────────────

  Widget _buildMetric(
    BuildContext context,
    String label,
    String value,
    String unit,
  ) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ShieldColors.textLabel,
            letterSpacing: 1.2,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: ShieldColors.textBody,
                fontSize: 24,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                unit,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ShieldColors.textLabel,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
