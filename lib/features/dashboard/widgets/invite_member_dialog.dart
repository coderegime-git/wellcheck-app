import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/data/auth_repository.dart';

class InviteMemberDialog extends ConsumerStatefulWidget {
  const InviteMemberDialog({super.key});

  @override
  ConsumerState<InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends ConsumerState<InviteMemberDialog> {
  String _selectedRole = 'monitor';
  bool _isLoading = false;
  bool _isCheckingPlan = true;
  String? _generatedCode;
  String? _planError;

  bool _hasPremium = false;
  bool _hasBasic = false;
  int _currentMemberCount = 0; // fetch from your family members list

  @override
  void initState() {
    super.initState();
    _checkPlanAndMembers();
  }

  Future<void> _checkPlanAndMembers() async {
    setState(() => _isCheckingPlan = true);

    try {
      // 1. Check RevenueCat plan
      final customerInfo = await Purchases.getCustomerInfo();
      final active = customerInfo.entitlements.active;

      _hasPremium = active.containsKey('WellCheck Premium');
      _hasBasic = active.containsKey('WellCheck Pro');

      // 2. Get current family member count from your provider
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile != null) {
        final members = await Supabase.instance.client
            .from('family_members')
            .select()
            .eq('family_id', profile.familyId);
        _currentMemberCount = (members as List).length;
        // includes the leader
      }

      // 3. Validate limits
      if (!_hasBasic && !_hasPremium) {
        _planError = 'No active subscription found.';
      } else if (_hasBasic && !_hasPremium) {
        // Basic: leader + 1 = max 2 members
        if (_currentMemberCount >= 2) {
          _planError =
              'Basic plan allows only 1 additional member.\nUpgrade to Premium to add up to 5 users.';
        }
        // Basic users can only add child/elder, not co-monitor
        if (_selectedRole == 'monitor') {
          _selectedRole = 'senior'; // default to elder for basic
        }
      } else if (_hasPremium) {
        // Premium: up to 5 users total
        if (_currentMemberCount >= 5) {
          _planError = 'Premium plan allows up to 5 members total.';
        }
      }
    } catch (e) {
      _planError = 'Failed to verify plan: $e';
    } finally {
      if (mounted) setState(() => _isCheckingPlan = false);
    }
  }

  // Basic plan only allows child/elder — not co-monitor
  List<DropdownMenuItem<String>> get _allowedRoles {
    if (_hasBasic && !_hasPremium) {
      return const [
        DropdownMenuItem(value: 'parent', child: Text('Parent')),

        DropdownMenuItem(value: 'senior', child: Text('Elder / Senior')),
        DropdownMenuItem(value: 'student', child: Text('Student')),
        DropdownMenuItem(value: 'child', child: Text('Child')),
        DropdownMenuItem(value: 'other', child: Text('Other')),
        // DropdownMenuItem(value: 'pet', child: Text('Pet Tracker')),
      ];
    }
    // Premium gets all roles
    return const [
      DropdownMenuItem(value: 'parent', child: Text('Parent')),
      DropdownMenuItem(value: 'monitor', child: Text('Monitor (Co-Parent)')),
      DropdownMenuItem(value: 'senior', child: Text('Elder / Senior')),
      DropdownMenuItem(value: 'student', child: Text('Student')),
      DropdownMenuItem(value: 'child', child: Text('Child')),
      DropdownMenuItem(value: 'other', child: Text('Other')),
      //  DropdownMenuItem(value: 'pet', child: Text('Pet Tracker')),
    ];
  }

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
        child: _isCheckingPlan
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ShieldColors.textLabel,
                    ),
                  ),

                  // Plan badge
                  const SizedBox(height: 12),
                  _PlanBadge(isPremium: _hasPremium),

                  const SizedBox(height: 16),

                  // Block if limit reached
                  if (_planError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: ShieldDesign.roundedTwelve,
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline, color: Colors.red),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _planError!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_hasBasic && !_hasPremium)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            context.pop();
                            // Navigate to paywall/upgrade screen
                            context.push('/paywall');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ShieldColors.activeTeal,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Upgrade to Premium'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => context.pop(),
                        child: const Text('Close'),
                      ),
                    ),
                  ] else if (_generatedCode == null) ...[
                    DropdownButtonFormField<String>(
                      value: _selectedRole,
                      decoration: InputDecoration(
                        labelText: 'Assign Role',
                        border: OutlineInputBorder(
                          borderRadius: ShieldDesign.roundedTwelve,
                        ),
                      ),
                      items: _allowedRoles,
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedRole = val);
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
                        onPressed: () => context.pop(),
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

// Small badge showing current plan
class _PlanBadge extends StatelessWidget {
  final bool isPremium;

  const _PlanBadge({required this.isPremium});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isPremium ? Colors.amber.shade50 : ShieldColors.softMint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPremium ? Colors.amber.shade400 : ShieldColors.activeTeal,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPremium ? Icons.star : Icons.shield_outlined,
            size: 14,
            color: isPremium ? Colors.amber.shade700 : ShieldColors.activeTeal,
          ),
          const SizedBox(width: 4),
          Text(
            isPremium
                ? 'Premium — up to 5 members'
                : 'Basic — 1 additional member',
            style: TextStyle(
              fontSize: 12,
              color: isPremium
                  ? Colors.amber.shade700
                  : ShieldColors.activeTeal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
