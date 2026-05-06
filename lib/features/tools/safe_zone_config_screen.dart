import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/tools_repository.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';

class SafeZoneConfigScreen extends ConsumerWidget {
  const SafeZoneConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final safe = ref.invalidate(safeZonesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Safety Fences'), centerTitle: false),
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
                      ElevatedButton.icon(
                        onPressed: () => context.push('/add-safe-zone'),
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
                      subtitle: Text('Radius: ${zone['radius_meters']}m'),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: ShieldColors.urgentRed,
                        ),
                        onPressed: () =>
                            _confirmDelete(context, ref, zone['id']),
                      ),
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
