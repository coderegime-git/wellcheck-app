import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/auth_repository.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/navigation/shield_router.dart';

class JoinWithCodeScreen extends ConsumerStatefulWidget {
  const JoinWithCodeScreen({super.key});

  @override
  ConsumerState<JoinWithCodeScreen> createState() => _JoinWithCodeScreenState();
}

class _JoinWithCodeScreenState extends ConsumerState<JoinWithCodeScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
final focusNode = FocusNode();
  Future<void> _handleJoin() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Code must be exactly 6 digits'),
          backgroundColor: ShieldColors.urgentRed,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      debugPrint('Attempting RPC Join...');
      await ref.read(authRepositoryProvider).joinFamilyWithPin(code);
      debugPrint('RPC Success! Invalidating profiles...');

      // Successfully joined! Force re-fetch of the profile map
      ref.invalidate(currentUserProfileProvider);

      // We MUST await the new profile to get the role before jumping to the dashboard
      // otherwise GoRouter defaults to ShieldRole.none and throws a blank loading screen
      final updatedProfile = await ref.read(currentUserProfileProvider.future);
      debugPrint('Profile Read: ${updatedProfile?.role}');

      if (updatedProfile != null && mounted) {
        // Evaluate the string into our internal enum
        ShieldRole assignedRole = ShieldRole.none;
        switch (updatedProfile.role) {
          case 'leader':
            assignedRole = ShieldRole.leader;
            break;
          case 'monitor':
            assignedRole = ShieldRole.monitor;
            break;
          case 'senior':
            assignedRole = ShieldRole.senior;
            break;
          case 'student':
            assignedRole = ShieldRole.student;
            break;
          case 'pet':
            assignedRole = ShieldRole.pet;
            break;
        }
        focusNode.unfocus();
        ref.read(userRoleProvider.notifier).setRole(assignedRole);
        context.go('/profile-setup');
      } else {
        throw Exception('Profile read returned null after join.');
      }
    } catch (e) {
      debugPrint('Code Verification Failed Final: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid or expired code. \n$e'),
            backgroundColor: ShieldColors.urgentRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        focusNode.unfocus();

        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Network'),
        backgroundColor: ShieldColors.backgroundWhite,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                const Icon(
                  Icons.shield_outlined,
                  size: 80,
                  color: ShieldColors.activeTeal,
                ),
                const SizedBox(height: 24),
                Text(
                  'Enter Invitation PIN',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: ShieldColors.textBody,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ask your Family Leader for the 6-digit secure code to seamlessly link your account to theirs.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ShieldColors.textLabel),
                ),
                const SizedBox(height: 48),
                TextField(
                  focusNode: focusNode,
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  onSubmitted: (_) => _handleJoin(),
                  style: const TextStyle(
                    fontSize: 32,
                    letterSpacing: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '000000',
                    hintStyle: TextStyle(color: Colors.grey.shade300),
                    border: OutlineInputBorder(
                      borderRadius: ShieldDesign.roundedTwelve,
                      borderSide: const BorderSide(
                        color: ShieldColors.activeTeal,
                        width: 2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: ShieldDesign.roundedTwelve,
                      borderSide: const BorderSide(
                        color: ShieldColors.activeTeal,
                        width: 3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleJoin,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : const Text(
                          'VERIFY AND JOIN',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
