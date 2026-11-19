import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/features/profile/manage_sale_person.dart';
import 'package:well_check_v3/features/profile/sales_person_qr_code.dart';

import '../../core/data/user_profile_provider.dart';
import '../../core/design/shield_theme.dart';
import '../../core/navigation/shield_router.dart';
import '../../core/notifications/push_notification_service.dart';
import '../../services/referral_service.dart';
import '../safety/services/purchase_services.dart';
import 'add_sale_person.dart';
import 'edit_sales_person.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isPayingAll = false;
  bool isLoad = false;

  List<Map<String, dynamic>> _commissions = [];

  double _totalEarnings = 0;
  double _pendingEarnings = 0;
  double _paidEarnings = 0;
  bool _isLoggingOut = false;
  List<Map<String, dynamic>> _salespersons = [];
  bool _isLoadingSalespersons = true;

  @override
  void initState() {
    super.initState();
    _loadCommissions(true);

    _loadSalespersons();
    //_calculateEarnings();
  }

  Widget _buildSalespersonManagement() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  child: const Icon(Icons.badge_outlined, size: 26),
                ),

                const SizedBox(width: 14),

                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Salesperson Management',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Create and manage salespeople and their referral QR codes.',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddSalespersonScreen(),
                    ),
                  );

                  await _loadSalespersons();
                },
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text(
                  'Add Salesperson',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),

            const SizedBox(height: 20),

            if (_isLoadingSalespersons)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_salespersons.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade100,
                ),
                child: const Column(
                  children: [
                    Icon(Icons.people_outline, size: 40, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      'No salespeople found',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ShieldColors.backgroundWhite,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ShieldColors.activeTeal),
                ),
                width: double.infinity,
                child: GestureDetector(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ManageSalePerson(),
                      ),
                    );
                    _loadSalespersons();
                  },
                  child: Text(
                    "Manage Salesperson",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ShieldColors.activeTeal),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Widget buildSalesperson() {
  //   return SingleChildScrollView(
  //     child: Container(
  //       padding: EdgeInsets.all(12),
  //       child: Column(
  //         children: _salespersons
  //             .map((salesperson) => _buildSalespersonCard(salesperson))
  //             .toList(),
  //       ),
  //     ),
  //   );
  // }

  // Widget _buildSalespersonCard(Map<String, dynamic> salesperson) {
  //   final name = salesperson['name'] ?? 'Unknown';
  //   final email = salesperson['email'] ?? '';
  //   final phone = salesperson['phone'] ?? '';
  //   final referralCode = salesperson['referral_code'] ?? '';
  //   final isActive = salesperson['is_active'] == true;
  //
  //   return Container(
  //     margin: const EdgeInsets.only(bottom: 12),
  //     padding: const EdgeInsets.all(16),
  //     decoration: BoxDecoration(
  //       border: Border.all(color: Colors.grey.shade300),
  //       borderRadius: BorderRadius.circular(14),
  //     ),
  //     child: Row(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         CircleAvatar(
  //           radius: 24,
  //           child: Text(
  //             name.isNotEmpty ? name[0].toUpperCase() : '?',
  //             style: const TextStyle(fontWeight: FontWeight.bold),
  //           ),
  //         ),
  //
  //         const SizedBox(width: 12),
  //
  //         Expanded(
  //           child: Column(
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             children: [
  //               Text(
  //                 name,
  //                 style: const TextStyle(
  //                   fontSize: 16,
  //                   fontWeight: FontWeight.bold,
  //                 ),
  //               ),
  //
  //               if (email.isNotEmpty) ...[
  //                 const SizedBox(height: 4),
  //                 Text(
  //                   email,
  //                   style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
  //                 ),
  //               ],
  //
  //               if (phone.isNotEmpty) ...[
  //                 const SizedBox(height: 3),
  //                 Text(
  //                   phone,
  //                   style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
  //                 ),
  //               ],
  //
  //               const SizedBox(height: 8),
  //
  //               Text(
  //                 'Referral: $referralCode',
  //                 style: const TextStyle(
  //                   fontSize: 13,
  //                   fontWeight: FontWeight.w600,
  //                 ),
  //               ),
  //
  //               const SizedBox(height: 6),
  //
  //               Container(
  //                 padding: const EdgeInsets.symmetric(
  //                   horizontal: 8,
  //                   vertical: 4,
  //                 ),
  //                 decoration: BoxDecoration(
  //                   borderRadius: BorderRadius.circular(20),
  //                   color: isActive
  //                       ? Colors.green.withOpacity(0.1)
  //                       : Colors.red.withOpacity(0.1),
  //                 ),
  //                 child: Text(
  //                   isActive ? 'Active' : 'Inactive',
  //                   style: TextStyle(
  //                     fontSize: 11,
  //                     fontWeight: FontWeight.w600,
  //                     color: isActive ? Colors.green : Colors.red,
  //                   ),
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ),
  //
  //         PopupMenuButton<String>(
  //           onSelected: (value) async {
  //             if (value == 'edit') {
  //               final result = await Navigator.push(
  //                 context,
  //                 MaterialPageRoute(
  //                   builder: (_) =>
  //                       EditSalespersonScreen(salesperson: salesperson),
  //                 ),
  //               );
  //
  //               if (result == true) {
  //                 await _loadSalespersons();
  //                 setState(() {});
  //               }
  //             } else if (value == 'qr') {
  //               final referralUrl = 'https://well-check.com/ref/$referralCode';
  //               showModalBottomSheet(
  //                 context: context,
  //                 useSafeArea: true,
  //                 isScrollControlled: true,
  //                 backgroundColor: Colors.transparent,
  //                 builder: (_) => SalespersonQrScreen(referralUrl: referralUrl),
  //               );
  //
  //               // Navigator.push(context, MaterialPageRoute(
  //               //     builder: (context) => SalespersonQrScreen(referralUrl: referralUrl)));
  //             } else if (value == 'status') {
  //               print("hghgh");
  //               _toggleSalespersonStatus(salesperson);
  //             }
  //           },
  //           itemBuilder: (context) => const [
  //             PopupMenuItem(value: 'edit', child: Text('Edit')),
  //             PopupMenuItem(value: 'qr', child: Text('View QR')),
  //             PopupMenuItem(
  //               value: 'status',
  //               child: Text('Activate / Deactivate'),
  //             ),
  //           ],
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Future<void> _loadSalespersons() async {
    setState(() {
      _isLoadingSalespersons = true;
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

  // =========================================================
  // SALESPERSON MANAGEMENT
  // =========================================================

  // Widget _buildSalespersonManagement() {
  //   return Card(
  //     elevation: 2,
  //     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
  //     child: Padding(
  //       padding: const EdgeInsets.all(20),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Row(
  //             children: [
  //               CircleAvatar(
  //                 radius: 24,
  //                 child: const Icon(Icons.badge_outlined, size: 26),
  //               ),
  //
  //               const SizedBox(width: 14),
  //
  //               const Expanded(
  //                 child: Column(
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: [
  //                     Text(
  //                       'Salesperson Management',
  //                       style: TextStyle(
  //                         fontSize: 18,
  //                         fontWeight: FontWeight.bold,
  //                       ),
  //                     ),
  //
  //                     SizedBox(height: 4),
  //
  //                     Text(
  //                       'Create and manage salespeople and their referral QR codes.',
  //                       style: TextStyle(fontSize: 13, color: Colors.grey),
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //             ],
  //           ),
  //
  //           const SizedBox(height: 16),
  //
  //           SizedBox(
  //             width: double.infinity,
  //             height: 48,
  //             child: ElevatedButton.icon(
  //               onPressed: () async {
  //                 final result = await Navigator.push(
  //                   context,
  //                   MaterialPageRoute(
  //                     builder: (_) => const AddSalespersonScreen(),
  //                   ),
  //                 );
  //
  //                 if (result == true) {
  //                   // Later we will reload the salesperson list here.
  //                 }
  //               },
  //               icon: const Icon(Icons.person_add_alt_1),
  //               label: const Text(
  //                 'Add Salesperson',
  //                 style: TextStyle(fontWeight: FontWeight.w600),
  //               ),
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  Future<void> _showLogoutConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Log Out',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade800),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Log Out',
              style: TextStyle(
                color: ShieldColors.urgentRed,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _logout();
    }
  }

  Future<void> _logout() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await ReferralService.instance.clearReferralCode();

    setState(() {
      _isLoggingOut = true;
    });
    final prefs = await SharedPreferences.getInstance();
    // await prefs.setBool('priv_biometric', false);
    // await prefs.setBool('is_logged_in', false);
    await PushNotificationService.saveTokenToProfile(null);
    FlutterBackgroundService().invoke('stopService');

    try {
      await PurchasesService.instance.logOut();
    } catch (e) {
      debugPrint('[RC] logOut skipped: $e');
    }
    await Supabase.instance.client.auth.signOut();

    ref.read(shieldRouterProvider).go('/');
  }

  // =========================================================
  // LOAD COMMISSIONS
  // =========================================================

  Future<void> _loadCommissions(load) async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = load;
        });
      }

      final data = await supabase
          .from('referral_commissions')
          .select('''
          id,
      referral_id,
      referrer_id,
      referred_user_id,
      plan_id,
      plan_price,
      commission_amount,
      status,
      created_at,
      paid_at,
     referrer:profiles!referral_commissions_referrer_id_fkey(
        id,
        full_name,
        phone
      ),

      referred_user:profiles!referral_commissions_referred_user_id_fkey(
        id,
        full_name,
        phone
      )
          ''')
          .order('created_at', ascending: false);

      _commissions = List<Map<String, dynamic>>.from(data);
      //  _loadSalespersons();
      _calculateEarnings();

      debugPrint('ADMIN COMMISSIONS: $_commissions');
    } catch (e, stackTrace) {
      debugPrint('ADMIN COMMISSION ERROR: $e');
      debugPrint(stackTrace.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load commissions: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          selectedCommissionId = null;
          isLoad = false;
          _isLoading = false;
        });
      }
    }
  }

  // =========================================================
  // CALCULATE TOTALS
  // =========================================================

  void _calculateEarnings() {
    double total = 0;
    double pending = 0;
    double paid = 0;

    for (final item in _commissions) {
      print('COMMISSION ITEM: $item');

      final amount =
          double.tryParse(item['commission_amount']?.toString() ?? '0') ?? 0;

      final status = item['status']?.toString().toLowerCase() ?? '';

      print('AMOUNT: $amount');
      print('STATUS: $status');

      total += amount;

      if (status == 'pending') {
        pending += amount;
      }

      if (status == 'paid') {
        paid += amount;
      }
    }

    _totalEarnings = total;
    _pendingEarnings = pending;
    _paidEarnings = paid;

    print('TOTAL: $_totalEarnings');
    print('PENDING: $_pendingEarnings');
    print('PAID: $_paidEarnings');
  }

  //

  // =========================================================
  // MARK SINGLE COMMISSION AS PAID
  // =========================================================
  String? selectedCommissionId;

  Future<void> _markAsPaid(String commissionId) async {
    setState(() {
      selectedCommissionId = commissionId;
      isLoad = true;
    });
    try {
      await supabase
          .from('referral_commissions')
          .update({
            'status': 'paid',
            'paid_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', commissionId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Commission marked as paid')),
      );

      await _loadCommissions(false);
      //_calculateEarnings();
    } catch (e, stackTrace) {
      debugPrint('MARK PAID ERROR: $e');
      debugPrint(stackTrace.toString());

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark commission as paid: $e')),
      );
    }
  }

  // =========================================================
  // CONFIRM SINGLE PAYMENT
  // =========================================================

  Future<void> _confirmMarkAsPaid(Map<String, dynamic> commission) async {
    final amount =
        double.tryParse(commission['commission_amount']?.toString() ?? '0') ??
        0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Mark as Paid?'),
          content: Text(
            'Are you sure you want to mark \$${amount.toStringAsFixed(2)} '
            'as paid?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Mark Paid'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _markAsPaid(commission['id'].toString());
    }
  }

  // =========================================================
  // MARK ALL PENDING AS PAID
  // =========================================================

  Future<void> _markAllAsPaid() async {
    if (_pendingEarnings <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no pending commissions')),
      );

      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pay All Pending?'),
          content: Text(
            'This will mark all pending commissions '
            '(\$${_pendingEarnings.toStringAsFixed(2)}) as paid.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Pay All'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      setState(() {
        _isPayingAll = true;
      });

      await supabase
          .from('referral_commissions')
          .update({
            'status': 'paid',
            'paid_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('status', 'pending');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All pending commissions marked as paid')),
      );

      await _loadCommissions(true);
    } catch (e, stackTrace) {
      debugPrint('PAY ALL ERROR: $e');
      debugPrint(stackTrace.toString());

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to mark all as paid: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isPayingAll = false;
        });
      }
    }
  }

  // =========================================================
  // FORMAT DATE
  // =========================================================

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) {
      return '-';
    }

    final date = DateTime.tryParse(value)?.toLocal();

    if (date == null) {
      return '-';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  // =========================================================
  // FORMAT PLAN
  // =========================================================

  String _formatPlan(String? plan) {
    if (plan == null || plan.isEmpty) {
      return '-';
    }

    if (plan == 'wellcheck_premium') {
      return 'Premium';
    }

    if (plan == 'wellcheck_basic' || plan == 'wellcheck_pro') {
      return 'Basic';
    }

    return plan;
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text(
          'Referral Admin',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: () => _loadCommissions(true),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _showLogoutConfirmation,
            icon: const Icon(Icons.logout, color: Colors.red),
          ),
        ],
      ),
      body: _isLoading && !isLoad
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadCommissions(true),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader(),

                  const SizedBox(height: 20),

                  _buildSalespersonManagement(),
                  const SizedBox(height: 20),

                  _buildStatistics(),

                  const SizedBox(height: 20),

                  _buildPayAllButton(),

                  const SizedBox(height: 28),

                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Commission History',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '${_commissions.length} purchases',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  _buildCommissionList(),
                ],
              ),
            ),
    );
  }

  // =========================================================
  // HEADER
  // =========================================================

  Widget _buildHeader() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              child: const Icon(Icons.admin_panel_settings, size: 32),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Referral Commission',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    'Track purchases and manage payouts',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // STATISTICS
  // =========================================================

  Widget _buildStatistics() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'Total Earnings',
                value: '\$${_totalEarnings.toStringAsFixed(2)}',
                icon: Icons.attach_money,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: _StatCard(
                title: 'Pending',
                value: '\$${_pendingEarnings.toStringAsFixed(2)}',
                icon: Icons.pending_actions,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'Paid',
                value: '\$${_paidEarnings.toStringAsFixed(2)}',
                icon: Icons.check_circle,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: _StatCard(
                title: 'Purchases',
                value: _commissions.length.toString(),
                icon: Icons.shopping_cart,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // =========================================================
  // PAY ALL BUTTON
  // =========================================================

  Widget _buildPayAllButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: (_pendingEarnings > 0 && !_isPayingAll)
            ? _markAllAsPaid
            : null,
        icon: _isPayingAll
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.done_all),
        label: Text(
          _isPayingAll
              ? 'Processing...'
              : 'Pay All Pending '
                    '\$${_pendingEarnings.toStringAsFixed(2)}',
        ),
      ),
    );
  }

  // =========================================================
  // COMMISSION LIST
  // =========================================================

  Widget _buildCommissionList() {
    if (_commissions.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 50),
          child: Column(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 55,
                color: Colors.grey.shade400,
              ),

              const SizedBox(height: 12),

              const Text(
                'No commissions yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),

              const SizedBox(height: 5),

              Text(
                'Successful referred purchases will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _commissions.map((commission) {
        return _buildCommissionCard(commission);
      }).toList(),
    );
  }

  // =========================================================
  // COMMISSION CARD
  // =========================================================

  Widget _buildCommissionCard(Map<String, dynamic> commission) {
    final commissionId = commission['id']?.toString() ?? '';

    final referrerId = commission['referrer_id']?.toString() ?? '-';

    final referredUserId = commission['referred_user_id']?.toString() ?? '-';

    final plan = _formatPlan(commission['plan_id']?.toString());

    final planPrice =
        double.tryParse(commission['plan_price']?.toString() ?? '0') ?? 0;

    final commissionAmount =
        double.tryParse(commission['commission_amount']?.toString() ?? '0') ??
        0;

    final status = commission['status']?.toString() ?? 'pending';

    final createdAt = commission['created_at']?.toString();

    final paidAt = commission['paid_at']?.toString();

    final isPaid = status.toLowerCase() == 'paid';
    final referrer = commission['referrer'] as Map<String, dynamic>?;

    final referrerName = referrer?['full_name']?.toString() ?? 'Unknown';
    final referrerPhone = referrer?['phone']?.toString() ?? 'No phone number';
    print(referrerName);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -----------------------------------------------
            // TOP
            // -----------------------------------------------
            Row(
              children: [
                CircleAvatar(
                  child: Icon(isPaid ? Icons.check : Icons.attach_money),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        'Purchase \$${planPrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                _StatusBadge(status: status),
              ],
            ),

            const SizedBox(height: 16),

            const Divider(),

            const SizedBox(height: 12),

            // -----------------------------------------------
            // REFERRER
            // -----------------------------------------------
            // _InfoRow(
            //   icon: Icons.person_outline,
            //   label: 'Referrer ID',
            //   value: referrerId,
            // ),
            //
            // const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.person_outline,
              label: 'Salesperson Name',
              value: referrerName,
            ),
            //
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.person_outline,
              label: 'Salesperson Number',
              value: referrerPhone,
            ),

            const SizedBox(height: 8),

            // -----------------------------------------------
            // REFERRED USER
            // -----------------------------------------------
            // _InfoRow(
            //   icon: Icons.person_add_outlined,
            //   label: 'Referred User ID',
            //   value: referredUserId,
            // ),
            //
            // const SizedBox(height: 8),

            // -----------------------------------------------
            // COMMISSION
            // -----------------------------------------------
            _InfoRow(
              icon: Icons.payments_outlined,
              label: 'Commission',
              value: '\$${commissionAmount.toStringAsFixed(2)}',
              valueBold: true,
            ),

            const SizedBox(height: 8),

            // -----------------------------------------------
            // DATE
            // -----------------------------------------------
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              label: 'Purchase Date',
              value: _formatDate(createdAt),
            ),

            if (isPaid && paidAt != null && paidAt.isNotEmpty) ...[
              const SizedBox(height: 8),

              _InfoRow(
                icon: Icons.check_circle_outline,
                label: 'Paid Date',
                value: _formatDate(paidAt),
              ),
            ],

            // -----------------------------------------------
            // PAY BUTTON
            // -----------------------------------------------
            // if (!isPaid) ...[
            //   const SizedBox(height: 16),
            //
            //   selectedCommissionId == commissionId && isLoad
            //       ? Center(
            //           child: SizedBox(
            //             width: 20,
            //             height: 20,
            //
            //             child: CircularProgressIndicator(),
            //           ),
            //         )
            //       : SizedBox(
            //           width: double.infinity,
            //           height: 46,
            //           child: ElevatedButton.icon(
            //             onPressed: () {
            //               _confirmMarkAsPaid(commission);
            //             },
            //             icon: const Icon(Icons.check_circle_outline),
            //             label: Text(
            //               'Mark \$${commissionAmount.toStringAsFixed(2)} as Paid',
            //             ),
            //           ),
            //         ),
            // ],
          ],
        ),
      ),
    );
  }
}

// ==========================================================
// INFO ROW
// ==========================================================

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool valueBold;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),

        const SizedBox(width: 10),

        SizedBox(
          width: 105,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: valueBold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================================
// STAT CARD
// ==========================================================

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        child: Column(
          children: [
            Icon(icon, size: 25),

            const SizedBox(height: 8),

            Text(
              value,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 4),

            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================================
// STATUS BADGE
// ==========================================================

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isPaid = status.toLowerCase() == 'paid';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isPaid
            ? Colors.green.withOpacity(0.1)
            : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isPaid ? 'Paid' : 'Pending',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isPaid ? Colors.green : Colors.orange,
        ),
      ),
    );
  }
}
