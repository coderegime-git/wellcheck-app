import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/features/command_center/medication_history.dart';
import 'package:well_check_v3/features/dashboard/widgets/invite_member_dialog.dart';
import 'package:well_check_v3/features/command_center/medications_sheet.dart';
import 'package:well_check_v3/features/command_center/check_in_sheet.dart';
import 'package:well_check_v3/features/command_center/contacts_sheet.dart';
import 'package:well_check_v3/features/command_center/status_sheet.dart';
import 'package:well_check_v3/features/command_center/vault_sheet.dart';
import 'package:well_check_v3/features/command_center/driving_sheet.dart';
import 'package:well_check_v3/features/command_center/campus_watch_sheet.dart';
import 'package:well_check_v3/features/messaging/family_chat_screen.dart';
import 'package:well_check_v3/features/profile/profile_settings_view.dart';

class CommandCenterSheet extends StatefulWidget {
  bool? fromLeader = false;

  CommandCenterSheet({super.key, this.fromLeader = false});

  @override
  State<CommandCenterSheet> createState() => _CommandCenterSheetState();
}

class _CommandCenterSheetState extends State<CommandCenterSheet> {
  @override
  Widget build(BuildContext context) {
    final items = [
      _CmdItem(
        Icons.medical_services,
        'Medications',
        'View your meds',
        ShieldColors.activeTeal,
        () => _pushSheet(
          context,
          MedicationsSheet(fromLeader: widget.fromLeader),
          true,
        ),
      ),
      if (widget.fromLeader == true)
        _CmdItem(
          Icons.history,
          'Medications history',
          'Meds history',
          ShieldColors.activeTeal,
          () => _pushSheet(
            context,
            MedicationHistoryScreen(fromLeader: widget.fromLeader),
            true,
          ),
        ),
      _CmdItem(
        Icons.calendar_month,
        'Calendar',
        'Your schedule',
        const Color(0xFF6B4EE6),
        () {
          context.pop();
          context.push('/sync-calendar');
        },
      ),
      // _CmdItem(
      //   Icons.how_to_reg,
      //   'Check-in',
      //   'Daily check-in',
      //
      //   ShieldColors.safeZoneGreen,
      //   () => _pushSheet(context, const CheckInSheet(), true),
      // ),
      if (widget.fromLeader == true)
        _CmdItem(
          Icons.how_to_reg,
          'Schedule Check-in',
          'Assign check-in',

          ShieldColors.safeZoneGreen,
          () => _pushSheet(context, const ScheduleCheckInSheet(), true),
        ),
      _CmdItem(
        Icons.contacts,
        'Contacts',
        'Important people',

        const Color(0xFF3366FF),
        () => _pushSheet(context, const ContactsSheet(), true),
      ),
      _CmdItem(
        Icons.map,
        'Safe Zones',
        'Your safe places',

        const Color(0xFFE6894E),
        () {
          context.pop();
          context.push('/safe-zone-config', extra: widget.fromLeader);
        },
      ),
      _CmdItem(
        Icons.favorite,
        'Status',
        'Health & wellness',

        ShieldColors.urgentRed,
        () => _pushSheet(context, const StatusSheet(), true),
      ),
      // _CmdItem(
      //   Icons.local_hospital,
      //   'Medical Vault',
      //   'Health records',
      //
      //   const Color(0xFF9B59B6),
      //   () => _pushSheet(
      //     context,
      //     VaultSheet(isMedical: true, fromLeader: widget.fromLeader ?? false),
      //     true,
      //   ),
      // ),
      // _CmdItem(
      //   Icons.lock,
      //   'Vault',
      //   'Secure storage',
      //
      //   const Color(0xFF2C3E50),
      //   () => _pushSheet(
      //     context,
      //     VaultSheet(isMedical: false, fromLeader: widget.fromLeader ?? false),
      //     true,
      //   ),
      // ),
      _CmdItem(
        Icons.drive_eta,
        'Driving',
        'Driving safety',

        Colors.orange,
        () => _pushSheet(context, const DrivingSheet(), true),
      ),
      _CmdItem(
        Icons.school,
        'Campus Watch',
        'School updates',
        const Color(0xFF1ABC9C),
        () => _pushSheet(
          context,
          CampusWatchSheet(fromLeader: widget.fromLeader ?? false),
          true,
        ),
      ),
      _CmdItem(
        Icons.chat_bubble_outlined,
        'Family Chat',
        'Stay connected',
        const Color(0xFF3498DB),
        () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => FamilyChatScreen()),
          );
        },
        //_pushSheet(context, const FamilyChatScreen(), true),
      ),
      _CmdItem(
        Icons.person_add,
        'Invite',
        'Add loved ones',
        ShieldColors.activeTeal,
        () {
          context.pop();
          showDialog(
            context: context,
            builder: (context) => const InviteMemberDialog(),
          );
        },
      ),
      _CmdItem(
        Icons.settings,
        'Profile',
        'Account settings',
        const Color(0xFF7F8C8D),
        () => _pushSheet(context, const ProfileSettingsView(), true),
      ),
    ];

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: ShieldColors.activeTeal,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 15),

            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.privacy_tip_outlined, color: Colors.white, size: 30),
                SizedBox(width: 10),
                Text(
                  'Command Center',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: ShieldColors.backgroundWhite,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),

            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.0,
              children: items
                  .map((item) => _AnimatedCmdTile(item: item))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _pushSheet(BuildContext ctx, Widget sheet, bool isScrollable) {
    Navigator.of(ctx).pop(); // still close command center
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showModalBottomSheet(
        context: ctx,
        useSafeArea: true,
        isScrollControlled: isScrollable,
        backgroundColor: Colors.transparent,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            return sheet;
          },
        ),
      );

      //  Navigator.push(context, MaterialPageRoute(builder: (context)=>sheet));
    });
  }
}

class _CmdItem {
  final IconData icon;
  final String label;
  final String desc;
  final Color color;
  final VoidCallback onTap;

  const _CmdItem(this.icon, this.label, this.desc, this.color, this.onTap);
}

class _AnimatedCmdTile extends StatefulWidget {
  final _CmdItem item;

  const _AnimatedCmdTile({required this.item});

  @override
  State<_AnimatedCmdTile> createState() => _AnimatedCmdTileState();
}

class _AnimatedCmdTileState extends State<_AnimatedCmdTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.lightImpact();
        widget.item.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: ShieldDesign.roundedTwelve,
            // border: Border.all(
            //   color: _pressed
            //       ? widget.item.color.withValues(alpha: 0.5)
            //       : Colors.grey.shade200,
            // ),
            boxShadow: [
              BoxShadow(
                color: widget.item.color.withValues(
                  alpha: _pressed ? 0.15 : 0.04,
                ),
                blurRadius: _pressed ? 16 : 4,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.item.icon, size: 35, color: widget.item.color),
              const SizedBox(height: 6),
              Text(
                widget.item.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: ShieldColors.textBody,
                ),
              ),
              Text(
                widget.item.desc,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Colors.black),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
