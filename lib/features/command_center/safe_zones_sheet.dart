import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/safe_zone_provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class SafeZonesSheet extends ConsumerWidget {
  const SafeZonesSheet({super.key});

  Future<void> _deleteZone(BuildContext context, String id) async {
    try {
      await Supabase.instance.client
          .from('locations_safe_zones')
          .delete()
          .eq('id', id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete zone: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonesAsync = ref.watch(familySafeZonesProvider);

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Safe Zones',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ShieldColors.textBody,
                ),
              ),
              IconButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close sheet first
                  context.push('/add-safe-zone');
                },
                icon: const Icon(
                  Icons.add_location_alt,
                  color: ShieldColors.activeTeal,
                  size: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Live Map
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: ShieldDesign.roundedTwelve,
              border: Border.all(color: Colors.grey.shade300),
            ),
            clipBehavior: Clip.hardEdge,
            child: zonesAsync.when(
              data: (zones) {
                final center = zones.isNotEmpty 
                    ? LatLng(zones.first.latitude, zones.first.longitude)
                    : const LatLng(37.7749, -122.4194); // Default SF if none
                return FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 12.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.well_check_v3',
                    ),
                    CircleLayer(
                      circles: zones.map((z) => CircleMarker(
                        point: LatLng(z.latitude, z.longitude),
                        color: ShieldColors.activeTeal.withValues(alpha: 0.3),
                        borderColor: ShieldColors.activeTeal,
                        borderStrokeWidth: 2,
                        radius: z.radiusMeters.toDouble(), // Radius in meters
                        useRadiusInMeter: true,
                      )).toList(),
                    ),
                    MarkerLayer(
                      markers: zones.map((z) => Marker(
                        point: LatLng(z.latitude, z.longitude),
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_on,
                          color: ShieldColors.alertRed,
                          size: 30,
                        ),
                      )).toList(),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => const Center(child: Text('Map Error')),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: zonesAsync.when(
              data: (zones) {
                if (zones.isEmpty) {
                  return const Center(
                    child: Text(
                      "No safe zones created. Add Home, School, etc.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: zones.length,
                  itemBuilder: (context, index) {
                    final zone = zones[index];
                    return Dismissible(
                      key: Key(zone.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: ShieldColors.alertRed,
                          borderRadius: ShieldDesign.roundedTwelve,
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _deleteZone(context, zone.id),
                      child: _buildZoneCard(
                        zone.zoneName,
                        '${zone.latitude.toStringAsFixed(3)}, ${zone.longitude.toStringAsFixed(3)}',
                        zone.radiusMeters,
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(
                  'Error: $err',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneCard(String name, String address, int radius) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: ShieldDesign.roundedTwelve),
      elevation: 2,
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: ShieldColors.surfaceLight,
          child: Icon(Icons.place, color: ShieldColors.activeTeal),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          'Radius: ${radius}m',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Switch(
          value: true,
          activeThumbColor: ShieldColors.activeTeal,
          onChanged: (val) {},
        ),
      ),
    );
  }
}

