// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';
// import 'package:well_check_v3/core/design/shield_theme.dart';
// import 'package:well_check_v3/core/data/tools_repository.dart';
// import 'package:well_check_v3/core/data/user_profile_provider.dart';
//
// class SafeZoneConfigScreen extends ConsumerWidget {
//   const SafeZoneConfigScreen({super.key});
//
//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final profileAsync = ref.watch(currentUserProfileProvider);
//     final safe = ref.invalidate(safeZonesStreamProvider);
//
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Safety Fences'),
//         centerTitle: false,
//         actions: [
//           IconButton(
//             onPressed: () {
//               context.push('/add-safe-zone');
//             },
//             icon: Icon(Icons.add),
//           ),
//         ],
//       ),
//       body: profileAsync.when(
//         data: (profile) {
//           if (profile == null) {
//             return const Center(child: Text('Unable to load family context.'));
//           }
//
//           final zonesStream = ref.watch(
//             safeZonesStreamProvider(profile.familyId),
//           );
//
//           return zonesStream.when(
//             data: (zones) {
//               if (zones.isEmpty) {
//                 return Center(
//                   child: Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       const Icon(
//                         Icons.fence_outlined,
//                         size: 80,
//                         color: Colors.grey,
//                       ),
//                       const SizedBox(height: 16),
//                       const Text(
//                         'No active safe zones established.',
//                         style: TextStyle(color: Colors.grey),
//                       ),
//                       const SizedBox(height: 24),
//                       ElevatedButton.icon(
//                         onPressed: () => context.push('/add-safe-zone'),
//                         icon: const Icon(Icons.add),
//                         label: const Text('CREATE FIRST ZONE'),
//                       ),
//                     ],
//                   ),
//                 );
//               }
//
//               return ListView.builder(
//                 padding: const EdgeInsets.all(24),
//                 itemCount: zones.length,
//                 itemBuilder: (context, index) {
//                   final zone = zones[index];
//                   return Card(
//                     shadowColor: Colors.grey.shade300,
//                     surfaceTintColor: Colors.white,
//                     elevation: 3,
//                     margin: const EdgeInsets.only(bottom: 16),
//                     child: ListTile(
//                       contentPadding: const EdgeInsets.all(16),
//                       leading: const CircleAvatar(
//                         backgroundColor: ShieldColors.softMint,
//                         child: Icon(
//                           Icons.location_on,
//                           color: ShieldColors.activeTeal,
//                         ),
//                       ),
//                       title: Text(
//                         zone['name'] ?? 'Unnamed Zone',
//                         style: const TextStyle(fontWeight: FontWeight.bold),
//                       ),
//                       subtitle: Text('Radius: ${zone['radius_meters']}m'),
//                       trailing: IconButton(
//                         icon: const Icon(
//                           Icons.delete_outline,
//                           color: ShieldColors.urgentRed,
//                         ),
//                         onPressed: () =>
//                             _confirmDelete(context, ref, zone['id']),
//                       ),
//                     ),
//                   );
//                 },
//               );
//             },
//             loading: () => const Center(child: CircularProgressIndicator()),
//             error: (err, stack) => Center(child: Text('Error: $err')),
//           );
//         },
//         loading: () => const Center(child: CircularProgressIndicator()),
//         error: (err, stack) => Center(child: Text('Error: $err')),
//       ),
//     );
//   }
//
//   Future<void> _confirmDelete(
//     BuildContext context,
//     WidgetRef ref,
//     String zoneId,
//   ) async {
//     final confirmed = await showDialog<bool>(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Delete Safe Zone?'),
//         content: const Text(
//           'This will disable alerts for this perimeter immediately.',
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.of(context).pop(false),
//             child: const Text('CANCEL'),
//           ),
//           ElevatedButton(
//             onPressed: () => Navigator.of(context).pop(true),
//             style: ElevatedButton.styleFrom(
//               backgroundColor: ShieldColors.urgentRed,
//             ),
//             child: const Text('DELETE'),
//           ),
//         ],
//       ),
//     );
//
//     if (confirmed == true) {
//       await ref.read(toolsRepositoryProvider).deleteSafeZone(zoneId);
//       ref.invalidate(safeZonesStreamProvider);
//     }
//   }
// }
//
// final safeZonesStreamProvider =
//     StreamProvider.family<List<Map<String, dynamic>>, String>((ref, familyId) {
//       return ref.watch(toolsRepositoryProvider).streamSafeZones(familyId);
//     });
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/tools_repository.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';

class SafeZoneConfigScreen extends ConsumerWidget {
  final bool fromLeader;

  const SafeZoneConfigScreen({super.key, this.fromLeader = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Fences'),
        centerTitle: false,
        actions: [
          if (fromLeader == true)
            IconButton(
              onPressed: () async {
                await context.push('/add-safe-zone');
                ref.invalidate(safeZonesStreamProvider);
              },
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('Unable to load family context.'));
          }

          final zonesStream = ref.watch(
            safeZonesStreamProvider(profile.familyId),
          );

          return zonesStream.when(
            data: (zones) {
              if (zones.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.fence_outlined,
                        size: 80,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No active safe zones established.',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      if (fromLeader == true)
                        ElevatedButton.icon(
                          onPressed: () async {
                            await context.push('/add-safe-zone');
                            ref.invalidate(safeZonesStreamProvider);
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('CREATE FIRST ZONE'),
                        ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: zones.length,
                itemBuilder: (context, index) {
                  final zone = zones[index];
                  return Card(
                    shadowColor: Colors.grey.shade300,
                    surfaceTintColor: Colors.white,
                    elevation: 3,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const CircleAvatar(
                        backgroundColor: ShieldColors.softMint,
                        child: Icon(
                          Icons.location_on,
                          color: ShieldColors.activeTeal,
                        ),
                      ),
                      title: Text(
                        zone['name'] ?? 'Unnamed Zone',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Radius: ${zone['radius_meters']}m'),
                          // const SizedBox(height: 4),
                          // Row(
                          //   children: [
                          //     _alertChip(
                          //       label: 'Entry',
                          //       active: zone['alert_on_entry'] ?? false,
                          //     ),
                          //     const SizedBox(width: 6),
                          //     _alertChip(
                          //       label: 'Exit',
                          //       active: zone['alert_on_exit'] ?? false,
                          //     ),
                          //   ],
                          // ),
                        ],
                      ),
                      //   isThreeLine: true,
                      trailing: fromLeader == true
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // ── EDIT BUTTON ──────────────────────────
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    color: ShieldColors.activeTeal,
                                  ),
                                  tooltip: 'Edit',
                                  onPressed: () async {
                                    await context.push(
                                      '/add-safe-zone',
                                      extra:
                                          zone, // pass full zone map for editing
                                    );
                                    ref.invalidate(safeZonesStreamProvider);
                                  },
                                ),
                                // ── DELETE BUTTON ────────────────────────
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: ShieldColors.urgentRed,
                                  ),
                                  tooltip: 'Delete',
                                  onPressed: () =>
                                      _confirmDelete(context, ref, zone['id']),
                                ),
                              ],
                            )
                          : SizedBox.shrink(),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _alertChip({required String label, required bool active}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active
            ? ShieldColors.safeZoneGreen.withOpacity(0.15)
            : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? ShieldColors.safeZoneGreen : Colors.grey.shade400,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: active ? ShieldColors.safeZoneGreen : Colors.grey,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String zoneId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Safe Zone?'),
        content: const Text(
          'This will disable alerts for this perimeter immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: ShieldColors.urgentRed,
            ),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(toolsRepositoryProvider).deleteSafeZone(zoneId);
      ref.invalidate(safeZonesStreamProvider);
    }
  }
}

final safeZonesStreamProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, familyId) {
      return ref.watch(toolsRepositoryProvider).streamSafeZones(familyId);
    });
