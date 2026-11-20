import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/navigation/shield_router.dart';
import 'package:well_check_v3/core/data/auth_repository.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';

import '../safety/services/pulse_service.dart';

// class RoleSelectionScreen extends ConsumerWidget {
//   const RoleSelectionScreen({super.key});
//
//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Define Your Role')),
//       body: SafeArea(
//         child: Padding(
//           padding: const EdgeInsets.all(24.0),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.stretch,
//             children: [
//               Text(
//                 'Welcome to Shield',
//                 style: Theme.of(context).textTheme.headlineMedium?.copyWith(
//                   fontWeight: FontWeight.bold,
//                   color: ShieldColors.activeTeal,
//                 ),
//                 textAlign: TextAlign.center,
//               ),
//               const SizedBox(height: 12),
//               const Text(
//                 'Are you establishing a new protection network, or joining an existing one?',
//                 style: TextStyle(color: ShieldColors.textLabel),
//                 textAlign: TextAlign.center,
//               ),
//               const Spacer(),
//               _RoleCard(
//                 title: 'Start a New Family Shield',
//                 subtitle: 'Become the Leader and invite your loved ones.',
//                 icon: Icons.shield_outlined,
//                 onTap: () => _createFamilyAndGo(context, ref),
//               ),
//               const SizedBox(height: 16),
//               _RoleCard(
//                 title: 'Join with Code',
//                 subtitle: 'I have a 6-digit invite PIN from a Family Leader.',
//                 icon: Icons.pin_outlined,
//                 onTap: () => context.push('/join-with-code'),
//               ),
//               const Spacer(),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   Future<void> _createFamilyAndGo(BuildContext context, WidgetRef ref) async {
//     try {
//       ref.read(userRoleProvider.notifier).setRole(ShieldRole.leader);
//       final authRepo = ref.read(authRepositoryProvider);
//
//       await authRepo.createFamilyWithRole('My Family Shield', 'leader');
//       ref.invalidate(currentUserProfileProvider);
//       await PulseService().broadcastPulse(null);
//
//       if (context.mounted) {
//         context.go('/profile-setup');
//       }
//     } catch (e) {
//       print(e.toString());
//       if (context.mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Failed setting role: $e'),
//             backgroundColor: ShieldColors.urgentRed,
//           ),
//         );
//         // Fallback go to profile setup
//         context.go('/profile-setup');
//       }
//     }
//   }
// }
//
// class _RoleCard extends StatelessWidget {
//   final String title;
//   final String subtitle;
//   final IconData icon;
//   final VoidCallback onTap;
//
//   const _RoleCard({
//     required this.title,
//     required this.subtitle,
//     required this.icon,
//     required this.onTap,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     return Card(
//       margin: const EdgeInsets.only(bottom: 16),
//       child: ListTile(
//         contentPadding: const EdgeInsets.all(16),
//         leading: Icon(icon, size: 32, color: ShieldColors.activeTeal),
//         title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
//         subtitle: Text(subtitle),
//         trailing: const Icon(Icons.chevron_right),
//         onTap: onTap,
//       ),
//     );
//   }
// }

class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  bool _isCreating = false;

  Future<void> _createFamilyAndGo() async {
    if (_isCreating) return;
    setState(() => _isCreating = true);
    HapticFeedback.selectionClick();

    try {
      await ref
          .read(authRepositoryProvider)
          .createFamilyWithRole('My Family Shield', 'leader');

      // Only set the role once the backend confirms it
      ref.read(userRoleProvider.notifier).setRole(ShieldRole.leader);
      ref.invalidate(currentUserProfileProvider);

      // Non-critical: must never block onboarding
      try {
        await PulseService().broadcastPulse(null);
      } catch (e) {
        debugPrint('Pulse broadcast failed: $e');
      }

      if (!mounted) return;
      context.go('/profile-setup');
    } catch (e) {
      debugPrint('createFamilyWithRole failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't create your Family Shield. Check your connection and try again.",
            ),
            backgroundColor: ShieldColors.urgentRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isCreating, // no back-nav mid-request
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading:
              false, // remove if this route can be popped
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, child) => Opacity(
                        opacity: v,
                        child: Transform.translate(
                          offset: Offset(0, 16 * (1 - v)),
                          child: child,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Spacer(),
                            const _ShieldBadge(),
                            const SizedBox(height: 28),
                            Text(
                              'Welcome to WellCheck',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Are you setting up a new protection network, or joining an existing one?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: ShieldColors.textLabel,
                                fontSize: 15,
                                height: 1.4,
                              ),
                            ),
                            const Spacer(),
                            _RoleCard(
                              title: 'Start a New Family Shield',
                              subtitle:
                                  'Become the Leader and invite your loved ones.',
                              icon: Icons.shield_outlined,
                              isPrimary: true,
                              isLoading: _isCreating,
                              onTap: _isCreating ? null : _createFamilyAndGo,
                            ),
                            const SizedBox(height: 14),
                            _RoleCard(
                              title: 'Join with Code',
                              subtitle:
                                  'I have a 6-digit invite PIN from a Family Leader.',
                              icon: Icons.pin_outlined,
                              onTap: _isCreating
                                  ? null
                                  : () {
                                      HapticFeedback.selectionClick();
                                      context.push('/join-with-code');
                                    },
                            ),
                            const SizedBox(height: 16),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShieldBadge extends StatelessWidget {
  const _ShieldBadge();

  @override
  Widget build(BuildContext context) {
    const teal = ShieldColors.activeTeal;
    return Center(
      child: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              teal.withValues(alpha: 0.28),
              teal.withValues(alpha: 0.04),
            ],
          ),
          border: Border.all(color: teal.withValues(alpha: 0.35), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: teal.withValues(alpha: 0.25),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        //   child: const Icon(Icons.shield_outlined, size: 52, color: teal),
        child: Image.asset(
          'assets/logo_splash_android12.png',

          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isLoading;
  final bool isPrimary;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.isLoading = false,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    const teal = ShieldColors.activeTeal;
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(20);

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: '$title. $subtitle',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: onTap == null && !isLoading ? 0.5 : 1,
        child: Material(
          color: isPrimary
              ? teal.withValues(alpha: 0.12)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: isPrimary
                  ? teal.withValues(alpha: 0.6)
                  : scheme.outlineVariant,
              width: isPrimary ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: teal.withValues(alpha: isPrimary ? 0.22 : 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 28, color: teal),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            color: ShieldColors.textLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: isLoading
                        ? const SizedBox(
                            key: ValueKey('loading'),
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Icon(
                            Icons.arrow_forward_ios_rounded,
                            key: const ValueKey('arrow'),
                            size: 16,
                            color: isPrimary ? teal : ShieldColors.textLabel,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// class RoleSelectionScreen extends ConsumerStatefulWidget {
//   final bool isSms;
//
//   const RoleSelectionScreen({super.key, this.isSms = false});
//
//   @override
//   ConsumerState<RoleSelectionScreen> createState() =>
//       _RoleSelectionScreenState();
// }
//
// class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
//   bool _isCreating = false;
//
//   Future<void> _createFamilyAndGo() async {
//     if (_isCreating) return;
//     setState(() => _isCreating = true);
//     HapticFeedback.selectionClick();
//
//     try {
//       await ref
//           .read(authRepositoryProvider)
//           .createFamilyWithRole('My Family Shield', 'leader');
//
//       // Only set the role once the backend confirms it
//       ref.read(userRoleProvider.notifier).setRole(ShieldRole.leader);
//       ref.invalidate(currentUserProfileProvider);
//
//       // Non-critical: must never block onboarding
//       try {
//         await PulseService().broadcastPulse(null);
//       } catch (e) {
//         debugPrint('Pulse broadcast failed: $e');
//       }
//
//       if (!mounted) return;
//       context.go('/profile-setup');
//     } catch (e) {
//       debugPrint('createFamilyWithRole failed: $e');
//       if (!mounted) return;
//       ScaffoldMessenger.of(context)
//         ..hideCurrentSnackBar()
//         ..showSnackBar(
//           const SnackBar(
//             content: Text(
//               "Couldn't create your Family Shield. Check your connection and try again.",
//             ),
//             backgroundColor: ShieldColors.urgentRed,
//             behavior: SnackBarBehavior.floating,
//           ),
//         );
//     } finally {
//       if (mounted) setState(() => _isCreating = false);
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return PopScope(
//       canPop: !_isCreating, // no back-nav mid-request
//       child: Scaffold(
//         appBar: AppBar(
//           backgroundColor: Colors.transparent,
//           elevation: 0,
//           scrolledUnderElevation: 0,
//           automaticallyImplyLeading:
//               false, // remove if this route can be popped
//         ),
//         body: SafeArea(
//           child: Center(
//             child: ConstrainedBox(
//               constraints: const BoxConstraints(maxWidth: 480),
//               child: CustomScrollView(
//                 slivers: [
//                   SliverFillRemaining(
//                     hasScrollBody: false,
//                     child: TweenAnimationBuilder<double>(
//                       tween: Tween(begin: 0, end: 1),
//                       duration: const Duration(milliseconds: 500),
//                       curve: Curves.easeOutCubic,
//                       builder: (_, v, child) => Opacity(
//                         opacity: v,
//                         child: Transform.translate(
//                           offset: Offset(0, 16 * (1 - v)),
//                           child: child,
//                         ),
//                       ),
//                       child: Padding(
//                         padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.stretch,
//                           children: [
//                             const Spacer(),
//                             const _ShieldBadge(),
//                             const SizedBox(height: 28),
//                             Text(
//                               'Welcome to Shield',
//                               textAlign: TextAlign.center,
//                               style: Theme.of(context).textTheme.headlineMedium
//                                   ?.copyWith(
//                                     fontWeight: FontWeight.w700,
//                                     letterSpacing: -0.5,
//                                   ),
//                             ),
//                             const SizedBox(height: 12),
//                             const Text(
//                               'Are you setting up a new protection network, or joining an existing one?',
//                               textAlign: TextAlign.center,
//                               style: TextStyle(
//                                 color: ShieldColors.textLabel,
//                                 fontSize: 15,
//                                 height: 1.4,
//                               ),
//                             ),
//                             const Spacer(),
//                             _RoleCard(
//                               title: 'Start a New Family Shield',
//                               subtitle:
//                                   'Become the Leader and invite your loved ones.',
//                               icon: Icons.shield_outlined,
//                               isPrimary: true,
//                               isLoading: _isCreating,
//                               onTap: _isCreating ? null : _createFamilyAndGo,
//                             ),
//                             const SizedBox(height: 14),
//                             _RoleCard(
//                               title: 'Join with Code',
//                               subtitle:
//                                   'I have a 6-digit invite PIN from a Family Leader.',
//                               icon: Icons.pin_outlined,
//                               onTap: _isCreating
//                                   ? null
//                                   : () {
//                                       HapticFeedback.selectionClick();
//                                       context.push('/join-with-code');
//                                     },
//                             ),
//                             const SizedBox(height: 16),
//                             const SizedBox(height: 16),
//                           ],
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// class _ShieldBadge extends StatelessWidget {
//   const _ShieldBadge();
//
//   @override
//   Widget build(BuildContext context) {
//     const teal = ShieldColors.activeTeal;
//     return Center(
//       child: Container(
//         width: 104,
//         height: 104,
//         decoration: BoxDecoration(
//           shape: BoxShape.circle,
//           gradient: RadialGradient(
//             colors: [
//               teal.withValues(alpha: 0.28),
//               teal.withValues(alpha: 0.04),
//             ],
//           ),
//           border: Border.all(color: teal.withValues(alpha: 0.35), width: 1.5),
//           boxShadow: [
//             BoxShadow(
//               color: teal.withValues(alpha: 0.25),
//               blurRadius: 32,
//               spreadRadius: 2,
//             ),
//           ],
//         ),
//         //   child: const Icon(Icons.shield_outlined, size: 52, color: teal),
//         child: Image.asset(
//           'assets/logo_splash_android12.png',
//
//           fit: BoxFit.cover,
//         ),
//       ),
//     );
//   }
// }
//
// class _RoleCard extends StatelessWidget {
//   final String title;
//   final String subtitle;
//   final IconData icon;
//   final VoidCallback? onTap;
//   final bool isLoading;
//   final bool isPrimary;
//
//   const _RoleCard({
//     required this.title,
//     required this.subtitle,
//     required this.icon,
//     required this.onTap,
//     this.isLoading = false,
//     this.isPrimary = false,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     const teal = ShieldColors.activeTeal;
//     final scheme = Theme.of(context).colorScheme;
//     final radius = BorderRadius.circular(20);
//
//     return Semantics(
//       button: true,
//       enabled: onTap != null,
//       label: '$title. $subtitle',
//       child: AnimatedOpacity(
//         duration: const Duration(milliseconds: 200),
//         opacity: onTap == null && !isLoading ? 0.5 : 1,
//         child: Material(
//           color: isPrimary
//               ? teal.withValues(alpha: 0.12)
//               : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
//           shape: RoundedRectangleBorder(
//             borderRadius: radius,
//             side: BorderSide(
//               color: isPrimary
//                   ? teal.withValues(alpha: 0.6)
//                   : scheme.outlineVariant,
//               width: isPrimary ? 1.5 : 1,
//             ),
//           ),
//           clipBehavior: Clip.antiAlias,
//           child: InkWell(
//             onTap: onTap,
//             child: Padding(
//               padding: const EdgeInsets.all(18),
//               child: Row(
//                 children: [
//                   Container(
//                     width: 52,
//                     height: 52,
//                     decoration: BoxDecoration(
//                       color: teal.withValues(alpha: isPrimary ? 0.22 : 0.12),
//                       borderRadius: BorderRadius.circular(14),
//                     ),
//                     child: Icon(icon, size: 28, color: teal),
//                   ),
//                   const SizedBox(width: 16),
//                   Expanded(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           title,
//                           style: const TextStyle(
//                             fontSize: 16,
//                             fontWeight: FontWeight.w700,
//                           ),
//                         ),
//                         const SizedBox(height: 4),
//                         Text(
//                           subtitle,
//                           style: const TextStyle(
//                             fontSize: 13.5,
//                             height: 1.35,
//                             color: ShieldColors.textLabel,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                   const SizedBox(width: 8),
//                   AnimatedSwitcher(
//                     duration: const Duration(milliseconds: 200),
//                     child: isLoading
//                         ? const SizedBox(
//                             key: ValueKey('loading'),
//                             width: 22,
//                             height: 22,
//                             child: CircularProgressIndicator(strokeWidth: 2.5),
//                           )
//                         : Icon(
//                             Icons.arrow_forward_ios_rounded,
//                             key: const ValueKey('arrow'),
//                             size: 16,
//                             color: isPrimary ? teal : ShieldColors.textLabel,
//                           ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
