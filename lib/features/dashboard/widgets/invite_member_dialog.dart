import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/data/auth_repository.dart';

class InviteMemberDialog extends ConsumerStatefulWidget {
  const InviteMemberDialog({super.key});

  @override
  ConsumerState<InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends ConsumerState<InviteMemberDialog> {
  String _selectedRole =
      'monitor'; // Default - valid shield_role enum values: leader, monitor, senior, student, pet
  bool _isLoading = false;
  String? _generatedCode;

  Future<void> _generateInvitation() async {
    setState(() => _isLoading = true);

    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile found');

      final code = await ref
          .read(authRepositoryProvider)
          .createInviteCode(profile.familyId, _selectedRole);

      if (mounted) {
        setState(() {
          _generatedCode = code;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to generate code: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: ShieldDesign.roundedTwelve),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Family Member',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: ShieldColors.textBody,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Send them an invite code to join your Shield network.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: ShieldColors.textLabel),
            ),
            const SizedBox(height: 24),
            if (_generatedCode == null) ...[
              DropdownButtonFormField<String>(
                value: _selectedRole,
                decoration: InputDecoration(
                  labelText: 'Assign Role',
                  border: OutlineInputBorder(
                    borderRadius: ShieldDesign.roundedTwelve,
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'monitor',
                    child: Text('Monitor (Co-Parent)'),
                  ),
                  DropdownMenuItem(
                    value: 'senior',
                    child: Text('Elder / Senior'),
                  ),
                  DropdownMenuItem(value: 'student', child: Text('Student')),
                  DropdownMenuItem(value: 'pet', child: Text('Pet Tracker')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedRole = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => context.pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _generateInvitation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ShieldColors.activeTeal,
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: ShieldDesign.roundedTwelve,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Generate Code'),
                  ),
                ],
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: ShieldColors.softMint,
                  borderRadius: ShieldDesign.roundedTwelve,
                  border: Border.all(color: ShieldColors.activeTeal),
                ),
                child: Center(
                  child: SelectableText(
                    _generatedCode!,
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                      color: ShieldColors.activeTeal,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Share this code. It will expire in 24 hours.',
                style: TextStyle(color: ShieldColors.textLabel),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Would use share_plus plugin in production to invoke OS share sheet
                    context.pop();
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Done'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
