// life360_family_status_list.dart
//
// The member list shown under the map (image 2 reference) — each row shows
// either a normal status line, or a "Physical activity permissions off /
// Since <time>" warning when that member's motion permission is disabled.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../features/driving_detection/life360_screen.dart';

class FamilyStatusList extends StatelessWidget {
  const FamilyStatusList({super.key, required this.members, this.onMemberTap});

  final List<MemberLocation> members;
  final void Function(MemberLocation member)? onMemberTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: members.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = members[i];
        return ListTile(
          onTap: onMemberTap != null ? () => onMemberTap!(m) : null,
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: m.color,
            backgroundImage: m.avatarUrl != null
                ? NetworkImage(m.avatarUrl!)
                : null,
            child: m.avatarUrl == null
                ? Text(
                    m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          title: Text(
            m.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: _StatusLine(member: m),
        );
      },
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.member});

  final MemberLocation member;

  @override
  Widget build(BuildContext context) {
    if (!member.motionPermissionEnabled) {
      final since = member.permissionChangedAt;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Physical activity permissions off',
            style: TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (since != null)
            Text(
              'Since ${DateFormat('h:mma').format(since).toLowerCase()}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
        ],
      );
    }

    String text;
    switch (member.effectiveStatus) {
      case MovementStatus.driving:
        text = 'Driving • ${member.speedKmh.toStringAsFixed(0)} km/h';
        break;
      case MovementStatus.walking:
        text = 'Walking';
        break;
      case MovementStatus.stopped:
        text = member.address ?? 'At a stop';
        break;
      case MovementStatus.unknown:
        text = member.address ?? 'Location unknown';
        break;
    }
    return Text(text, style: TextStyle(color: Colors.grey.shade700));
  }
}
