import 'package:flutter/material.dart';

class HealthKitInfoScreen extends StatelessWidget {
  const HealthKitInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health Monitoring')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.favorite, size: 60, color: Colors.red),
            const SizedBox(height: 24),

            const Text(
              'Connect Apple Health',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),

            const Text(
              'Well Check integrates with Apple Health to securely access '
              'health and wellness data to support health monitoring and '
              'family safety features.',
              style: TextStyle(fontSize: 16),
            ),

            const SizedBox(height: 24),

            const Text(
              'Data Used',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            const ListTile(
              leading: Icon(Icons.favorite_outline),
              title: Text('Heart Rate'),
            ),

            const ListTile(
              leading: Icon(Icons.directions_walk),
              title: Text('Steps'),
            ),

            const ListTile(
              leading: Icon(Icons.monitor_heart_outlined),
              title: Text('Activity Data'),
            ),

            const SizedBox(height: 20),

            const Text(
              'Your health data is only accessed with your permission. '
              'You can manage or revoke access at any time through '
              'Apple Health settings.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),

            //const Spacer(flex: 2),
            SizedBox(
              width: double.infinity,
              child: const Text(
                'You can connect Apple Health and enable Heart Rate Monitoring in Notification Preferences under Settings.',
              ),
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
