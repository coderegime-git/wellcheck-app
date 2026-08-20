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
  String? currentUserRole;

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Future<void> _fetchContacts() async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);

      if (profile == null) return;

      final res = await Supabase.instance.client
          .from('family_members')
          .select('user_id, role, profiles(full_name, phone)')
          .eq('family_id', profile.familyId);

      // find current logged-in user role
      final myData = res.firstWhere((e) => e['user_id'] == profile.userId);

      currentUserRole = myData['role'];

      setState(() {
        _contacts = List<Map<String, dynamic>>.from(res);

        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print(e);
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
    String memberId,
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
          child: Text(name.isNotEmpty ? name[0] : '?'),
        ),

        title: Text(
          name + (isMe ? ' (Me)' : ''),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),

        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(relation.toUpperCase()),

            if (hasPhone && !isMe) Text(phone),

            if (!hasPhone && !isMe) const Text('No phone on file'),
          ],
        ),

        trailing: isMe
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  /// DELETE
                  if (currentUserRole == "leader")
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text("Remove Member"),
                            content: Text("Remove $name from family?"),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                                child: const Text("Cancel"),
                              ),

                              TextButton(
                                onPressed: () async {
                                  Navigator.pop(context);

                                  await removeMember(memberId);
                                },
                                child: const Text(
                                  "Remove",
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                  IconButton(
                    icon: Icon(
                      Icons.message,
                      color: hasPhone ? ShieldColors.activeTeal : Colors.grey,
                    ),
                    onPressed: hasPhone ? () => _launchUrl('sms', phone) : null,
                  ),

                  IconButton(
                    icon: Icon(
                      Icons.phone,
                      color: hasPhone ? ShieldColors.alertRed : Colors.grey,
                    ),
                    onPressed: hasPhone ? () => _launchUrl('tel', phone) : null,
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> removeMember(String memberId) async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;
      await Supabase.instance.client
          .from('family_members')
          .delete()
          .eq('family_id', profile!.familyId)
          .eq('user_id', memberId);

      _contacts.removeWhere((e) => e['user_id'] == memberId);

      setState(() {});

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Member removed')));
    } catch (e) {
      print(e);
    }
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
              if (currentUserRole == "leader")
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
                      print(profileData);
                      final name =
                          profileData?['full_name'] ??
                          profileData?['email'] ??
                          'Member';
                      final phone = contact['profiles']?['phone'] as String?;
                      final role = contact['role'] as String;
                      final isMe =
                          contact['user_id'] ==
                          ref.read(currentUserProfileProvider).value?.userId;
                      final memberId = contact['user_id'];

                      return _buildContactRow(
                        contact['user_id'],
                        name,
                        role,
                        phone,
                        isMe,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
