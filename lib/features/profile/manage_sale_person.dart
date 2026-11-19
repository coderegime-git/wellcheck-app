import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/features/profile/sales_person_qr_code.dart';
import 'package:well_check_v3/features/profile/salesperson_ref_detail.dart';

import 'edit_sales_person.dart';

class ManageSalePerson extends StatefulWidget {
  const ManageSalePerson({super.key});

  @override
  State<ManageSalePerson> createState() => _ManageSalePersonState();
}

class _ManageSalePersonState extends State<ManageSalePerson> {
  List<Map<String, dynamic>> _salespersons = [];
  bool _isLoadingSalespersons = true;
  final supabase = Supabase.instance.client;

  Future<void> _toggleSalespersonStatus(
    Map<String, dynamic> salesperson,
  ) async {
    final salespersonId = salesperson['id']?.toString();

    if (salespersonId == null) return;

    final currentStatus = salesperson['is_active'] == true;
    final newStatus = !currentStatus;

    try {
      await supabase
          .from('salespersons')
          .update({
            'is_active': newStatus,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', salespersonId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus ? 'Salesperson activated' : 'Salesperson deactivated',
          ),
        ),
      );

      setState(() {});

      // Reload your salesperson list here
      // await _loadSalespersons();
    } catch (e) {
      debugPrint('Toggle salesperson status error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to update status: $e')));
    }
  }

  Future<void> _loadSalespersons(isLoad) async {
    setState(() {
      _isLoadingSalespersons = isLoad;
    });

    try {
      final data = await supabase
          .from('salespersons')
          .select(
            'id, user_id, name, email, phone, business_card_url, '
            'referral_code, referral_url, qr_code_url, is_active, created_at',
          )
          .order('created_at', ascending: false);

      setState(() {
        _salespersons = List<Map<String, dynamic>>.from(data);
        _isLoadingSalespersons = false;
      });
    } catch (e) {
      debugPrint('Load salespersons error: $e');

      setState(() {
        _isLoadingSalespersons = false;
      });
    }
  }

  Widget _buildSalespersonCard(Map<String, dynamic> salesperson) {
    final name = salesperson['name'] ?? 'Unknown';
    final email = salesperson['email'] ?? '';
    final phone = salesperson['phone'] ?? '';
    final referralCode = salesperson['referral_code'] ?? '';
    final referralUrl = salesperson['referral_url'] ?? '';
    final isActive = salesperson['is_active'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                if (email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ],

                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    phone,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ],

                const SizedBox(height: 8),

                Text(
                  'Referral: $referralCode',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 6),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: isActive
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                  ),
                  child: Text(
                    isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),

          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'edit') {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        EditSalespersonScreen(salesperson: salesperson),
                  ),
                );

                if (result == true) {
                  await _loadSalespersons(false);
                  setState(() {});
                }
              } else if (value == 'qr') {
                showModalBottomSheet(
                  context: context,
                  useSafeArea: true,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => SalespersonQrScreen(referralUrl: referralUrl),
                );

                // Navigator.push(context, MaterialPageRoute(
                //     builder: (context) => SalespersonQrScreen(referralUrl: referralUrl)));
              } else if (value == 'status') {
                await _toggleSalespersonStatus(salesperson);
                await _loadSalespersons(false);
              } else if (value == 'referrals') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SalespersonReferralDetailsScreen(
                      salesperson: salesperson,
                    ),
                  ),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'qr', child: Text('View QR')),
              PopupMenuItem(
                value: 'referrals',
                child: Row(
                  children: [
                    Icon(Icons.people_outline),
                    SizedBox(width: 12),
                    Text('View Referral Details'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'status',
                child: Text('Activate / Deactivate'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildSalesperson() {
    return SingleChildScrollView(
      child: Container(
        padding: EdgeInsets.all(12),
        child: Column(
          children: _salespersons
              .map((salesperson) => _buildSalespersonCard(salesperson))
              .toList(),
        ),
      ),
    );
  }

  @override
  void initState() {
    _loadSalespersons(true);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Manage Salesperson")),
      body: _isLoadingSalespersons
          ? Center(child: CircularProgressIndicator())
          : buildSalesperson(),
    );
  }
}
