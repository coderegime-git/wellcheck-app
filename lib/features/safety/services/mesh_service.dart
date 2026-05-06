import 'package:nearby_connections/nearby_connections.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/foundation.dart';

class MeshService {
  final Strategy strategy = Strategy.P2P_CLUSTER;
  final String deviceName = "ShieldNode"; // In production, use userId or similar

  /// Activates the "SOS Beacon" (Broadcasting Distres)
  Future<void> startSOSBeacon(String sosPayload) async {
    try {
      await Nearby().startAdvertising(
        deviceName,
        strategy,
        onConnectionInitiated: (id, info) {
          // Relays don't need full connection, just payload broadcast
          Nearby().acceptConnection(id, onPayLoadRecieved: (id, payload) {});
        },
        onConnectionResult: (id, status) {},
        onDisconnected: (id) {},
        serviceId: "com.wellcheck.sos",
      );
    } catch (e) {
      debugPrint('SOS Beacon failed: $e');
    }
  }

  /// Activates "Guardian Mode" (Listening for others' distress)
  Future<void> startMeshScanning(SupabaseClient client) async {
    try {
      await Nearby().startDiscovery(
        deviceName,
        strategy,
        onEndpointFound: (id, name, serviceId) {
          // If we found an SOS beacon, try to relay it!
          // Note: In a real mesh, we'd establish a connection to get the full encrypted packet.
          debugPrint('Found SOS Node: $name');
        },
        onEndpointLost: (id) {},
        serviceId: "com.wellcheck.sos",
      );
    } catch (e) {
      debugPrint('Mesh Scanning failed: $e');
    }
  }

  Future<void> stopAll() async {
    await Nearby().stopAdvertising();
    await Nearby().stopDiscovery();
  }
}
