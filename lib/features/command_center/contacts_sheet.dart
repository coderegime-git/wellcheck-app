import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactsSheet extends ConsumerStatefulWidget {
  const ContactsSheet({super.key});

  @override
  ConsumerState<ContactsSheet> createState() => _ContactsSheetState();
}

class _ContactsSheetState extends ConsumerState<ContactsSheet> {
  List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Future<void> _fetchContacts() async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;

      // Fetch family members with profile data including phone
      // final res = await Supabase.instance.client
      //     .from('family_members')
      //     .select('user_id, role, profiles(full_name, phone, email)')
      //     .eq('family_id', profile.familyId);
      final res = await Supabase.instance.client
          .from('family_members')
          .select('user_id, role, profiles(full_name, phone)')
          .eq('family_id', profile.familyId);
      print(res);
      print("resresres");
      if (mounted) {
        setState(() {
          _contacts = List<Map<String, dynamic>>.from(res);
          _contacts.sort((a, b) {
            final roleA = a['role'] as String;
            final roleB = b['role'] as String;
            if (roleA == 'leader') return -1;
            if (roleB == 'leader') return 1;
            return 0;
          });
          _isLoading = false;
        });
      }
    } catch (e) {
      print(e.toString());
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _launchUrl(String scheme, String path) async {
    final Uri url = Uri(scheme: scheme, path: path);
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch application.')),
        );
      }
    }
  }

  void _showAddContactInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: ShieldDesign.roundedTwelve),
        title: const Row(
          children: [
            Icon(Icons.person_add, color: ShieldColors.activeTeal),
            SizedBox(width: 8),
            Text('Add Contact'),
          ],
        ),
        content: const Text(
          'To add a new family member, go to the Family Shield dashboard and use the Invite Member feature. '
          'Once they accept and join your shield, they\'ll automatically appear here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'GOT IT',
              style: TextStyle(color: ShieldColors.activeTeal),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactRow(
    String name,
    String relation,
    String? phone,
    bool isMe,
  ) {
    final hasPhone = phone != null && phone.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: ShieldDesign.roundedTwelve),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: ShieldColors.surfaceLight,
          child: Text(
            name.isNotEmpty ? name[0] : '?',
            style: const TextStyle(
              color: ShieldColors.activeTeal,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          name + (isMe ? ' (Me)' : ''),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              relation.toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            if (hasPhone && !isMe)
              Text(
                phone,
                style: const TextStyle(
                  fontSize: 11,
                  color: ShieldColors.textLabel,
                ),
              ),
            if (!hasPhone && !isMe)
              const Text(
                'No phone on file',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
        trailing: isMe
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.message,
                      color: hasPhone
                          ? ShieldColors.activeTeal
                          : Colors.grey.shade300,
                    ),
                    onPressed: hasPhone ? () => _launchUrl('sms', phone) : null,
                    tooltip: hasPhone ? 'Send SMS' : 'No phone number',
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.phone,
                      color: hasPhone
                          ? ShieldColors.alertRed
                          : Colors.grey.shade300,
                    ),
                    onPressed: hasPhone ? () => _launchUrl('tel', phone) : null,
                    tooltip: hasPhone ? 'Call' : 'No phone number',
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ShieldColors.backgroundWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Text(
                'Emergency Contacts',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ShieldColors.textBody,
                ),
              ),
              Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.person_add,
                  color: ShieldColors.activeTeal,
                ),
                onPressed: _showAddContactInfo,
                tooltip: 'Add Contact',
              ),
              SizedBox(width: 10),
              GestureDetector(
                onTap: () async {
                  Navigator.of(context).pop();
                },
                child: Container(
                  padding: EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade400,
                        offset: Offset(0, 0),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.close, color: Colors.black, size: 16),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _contacts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No family members yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _contacts.length,
                    itemBuilder: (context, index) {
                      final contact = _contacts[index];
                      final profileData =
                          contact['profiles'] as Map<String, dynamic>?;
                      final name =
                          profileData?['full_name'] ??
                          profileData?['email'] ??
                          'Member';
                      final phone = contact['profiles']?['phone'] as String?;
                      final role = contact['role'] as String;
                      final isMe =
                          contact['user_id'] ==
                          ref.read(currentUserProfileProvider).value?.userId;
                      return _buildContactRow(name, role, phone, isMe);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
