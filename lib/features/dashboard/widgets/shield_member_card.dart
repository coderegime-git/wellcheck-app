import 'package:flutter/material.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';

class ShieldMemberCard extends StatelessWidget {
  final String name;
  final String status;
  final List<Map<String, String>> metrics;
  final IconData subStatusIcon;
  final String subStatusText;
  final bool isAlert;
  final bool isReadOnly; // False for leaders/monitors, true for students
  final VoidCallback? onTap; // Nullable if read-only
  final String? avatarUrl; // Profile Image URL

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
  });

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
                            image: NetworkImage(avatarUrl!),
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
                      SizedBox(height: 5),
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
                      SizedBox(height: 5),

                      Row(
                        children: [
                          Icon(
                            Icons.monitor_heart,
                            color: isAlert
                                ? ShieldColors.urgentRed
                                : ShieldColors.activeTeal,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              subStatusText,
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
                          ),
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
            if (metrics.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: isAlert
                      ? Colors.white.withValues(alpha: 0.5)
                      : const Color(0xFFF8F9FA),
                  borderRadius: ShieldDesign.roundedTwelve,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: metrics.map((metric) {
                    return _buildMetric(
                      context,
                      metric['label']!,
                      metric['value']!,
                      metric['unit']!,
                    );
                  }).toList(),
                ),
              ),
            if (metrics.isNotEmpty) const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

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
