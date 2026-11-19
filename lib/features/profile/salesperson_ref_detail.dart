import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SalespersonReferralDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> salesperson;

  const SalespersonReferralDetailsScreen({
    super.key,
    required this.salesperson,
  });

  @override
  State<SalespersonReferralDetailsScreen> createState() =>
      _SalespersonReferralDetailsScreenState();
}

class _SalespersonReferralDetailsScreenState
    extends State<SalespersonReferralDetailsScreen> {
  final supabase = Supabase.instance.client;

  bool isLoading = true;

  List<Map<String, dynamic>> referrals = [];
  List<Map<String, dynamic>> _commissions = [];
  bool _isLoadingCommissions = true;
  bool _isPayingOut = false;

  @override
  void initState() {
    super.initState();
    _loadCommissions();

    _loadReferrals();
  }

  List<Map<String, dynamic>> get _currentMonthCommissions {
    final now = DateTime.now();
    return _commissions.where((c) {
      final createdAt = DateTime.tryParse(c['created_at']?.toString() ?? '');
      if (createdAt == null) return false;
      return createdAt.year == now.year && createdAt.month == now.month;
    }).toList();
  }

  double get _currentMonthEarnings {
    return _currentMonthCommissions.fold<double>(
      0,
      (sum, c) =>
          sum +
          (double.tryParse(c['commission_amount']?.toString() ?? '0') ?? 0),
    );
  }

  double get _currentMonthPendingPayout {
    return _currentMonthCommissions
        .where((c) => c['status']?.toString().toLowerCase() == 'pending')
        .fold<double>(
          0,
          (sum, c) =>
              sum +
              (double.tryParse(c['commission_amount']?.toString() ?? '0') ?? 0),
        );
  }

  bool get _hasPendingPayoutThisMonth => _currentMonthPendingPayout > 0;

  Future<void> _handlePayout() async {
    final pendingIds = _currentMonthCommissions
        .where((c) => c['status']?.toString().toLowerCase() == 'pending')
        .map((c) => c['id'])
        .toList();

    if (pendingIds.isEmpty) return;

    setState(() {
      _isPayingOut = true;
    });

    try {
      await supabase
          .from('referral_commissions')
          .update({
            'status': 'paid',
            'paid_at': DateTime.now().toIso8601String(),
          })
          .inFilter('id', pendingIds);

      await _loadCommissions();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Payout marked as paid')));
    } catch (e) {
      debugPrint('Payout error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Payout failed: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isPayingOut = false;
        });
      }
    }
  }

  Future<void> _confirmPayout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Payout'),
          content: const Text('Are you sure you want to process this payout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      _handlePayout();
    }
  }

  Widget _buildEarningsSummaryCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "This Month's Earnings",
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            '\$${_currentMonthEarnings.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pending payout: \$${_currentMonthPendingPayout.toStringAsFixed(2)}',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              ElevatedButton(
                onPressed: (_hasPendingPayoutThisMonth && !_isPayingOut)
                    ? _confirmPayout
                    : null,
                child: _isPayingOut
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Payout'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _loadCommissions() async {
    try {
      setState(() {
        _isLoadingCommissions = true;
      });

      final salespersonUserId = widget.salesperson['user_id']?.toString();

      if (salespersonUserId == null || salespersonUserId.isEmpty) {
        return;
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

          referred_user:profiles!referral_commissions_referred_user_id_fkey(
            id,
            full_name,
            phone
          )
        ''')
          .eq('referrer_id', salespersonUserId)
          .order('created_at', ascending: false);

      _commissions = List<Map<String, dynamic>>.from(data);

      debugPrint('SALESPERSON COMMISSIONS: $_commissions');
    } catch (e, stackTrace) {
      debugPrint('SALESPERSON COMMISSION ERROR: $e');
      debugPrint(stackTrace.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCommissions = false;
        });
      }
    }
  }

  Future<void> _loadReferrals() async {
    final salespersonUserId = widget.salesperson['user_id']?.toString();

    if (salespersonUserId == null || salespersonUserId.isEmpty) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    try {
      debugPrint(
        'Loading referrals for salesperson: '
        '$salespersonUserId',
      );

      final data = await supabase
          .from('referrals')
          .select(
            'id, '
            'referrer_id, '
            'user_id, '
            'referral_code, '
            'status, '
            'referred_name, '
            'referred_email, '
            'created_at, '
            'converted_at',
          )
          .eq('referrer_id', salespersonUserId)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        referrals = List<Map<String, dynamic>>.from(data);

        isLoading = false;
      });
    } catch (e) {
      debugPrint('Load salesperson referrals error: $e');

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to load referrals: $e')));
    }
  }

  Widget _buildCommissionCard(Map<String, dynamic> commission) {
    final referredUser = commission['referred_user'] as Map<String, dynamic>?;

    final planPrice =
        double.tryParse(commission['plan_price']?.toString() ?? '0') ?? 0;

    final commissionAmount =
        double.tryParse(commission['commission_amount']?.toString() ?? '0') ??
        0;

    final status = commission['status']?.toString().toLowerCase() ?? 'pending';

    final createdAt = commission['created_at']?.toString();

    final paidAt = commission['paid_at']?.toString();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan Price
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Plan Price', style: TextStyle(color: Colors.grey)),
              Text(
                '\$${planPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Commission
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Commission', style: TextStyle(color: Colors.grey)),
              Text(
                '\$${commissionAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Payment Status',
                style: TextStyle(color: Colors.grey),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: status == 'paid'
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: status == 'paid' ? Colors.green : Colors.orange,
                  ),
                ),
              ),
            ],
          ),

          // if (createdAt != null) ...[
          //   const SizedBox(height: 8),
          //   Text(
          //     'Created: ${_formatDate(createdAt)}',
          //     style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          //   ),
          // ],
          if (paidAt != null && paidAt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Paid: ${_formatDate(paidAt)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final salespersonName =
        widget.salesperson['name']?.toString() ?? 'Salesperson';

    return Scaffold(
      appBar: AppBar(title: Text('$salespersonName Referrals')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : referrals.isEmpty
          ? const Center(
              child: Text(
                'No referrals found',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                await Future.wait([_loadReferrals(), _loadCommissions()]);
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Referral Details',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  _buildEarningsSummaryCard(),
                  const SizedBox(height: 12),

                  ...referrals.map((referral) => _buildReferralCard(referral)),
                ],
              ),
            ),
    );
  }

  String _formatDate(String? date) {
    if (date == null || date.isEmpty) {
      return '-';
    }

    try {
      final parsed = DateTime.parse(date).toLocal();

      return '${parsed.day.toString().padLeft(2, '0')}/'
          '${parsed.month.toString().padLeft(2, '0')}/'
          '${parsed.year}';
    } catch (_) {
      return date;
    }
  }

  Widget _buildReferralCard(Map<String, dynamic> referral) {
    final referredName =
        referral['referred_name']?.toString().trim().isNotEmpty == true
        ? referral['referred_name'].toString()
        : 'Unknown User';

    final referredEmail = referral['referred_email']?.toString() ?? '';

    final status = referral['status']?.toString() ?? 'unknown';

    final referralCode = referral['referral_code']?.toString() ?? '';

    final createdAt = referral['created_at']?.toString() ?? '';

    final referralId = referral['id'];
    print(referralId);
    print("referralId");
    for (final commission in _commissions) {
      print('Commission referral_id: ${commission['referral_id']}');
    }
    final matchedCommissions = _commissions
        .where((c) => c['referral_id'] == referralId)
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(
                    referredName.isNotEmpty
                        ? referredName[0].toUpperCase()
                        : '?',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    referredName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            if (referredEmail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                referredEmail,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],

            const SizedBox(height: 8),

            Text(
              'Referral Code: $referralCode',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),

            //   const SizedBox(height: 8),

            // Row(
            //   children: [
            //     const Text(
            //       'Status: ',
            //       style: TextStyle(fontWeight: FontWeight.w600),
            //     ),
            //     Text(
            //       status,
            //       style: TextStyle(
            //         fontWeight: FontWeight.w600,
            //         color: status == 'converted' ? Colors.green : Colors.orange,
            //       ),
            //     ),
            //   ],
            // ),
            if (createdAt.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Created: ${_formatDate(createdAt)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],

            // Commission section - scoped to this referral only
            if (_isLoadingCommissions) ...[
              const SizedBox(height: 12),
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              ),
            ] else if (matchedCommissions.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Commission',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...matchedCommissions.map(
                (commission) => _buildCommissionCard(commission),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
