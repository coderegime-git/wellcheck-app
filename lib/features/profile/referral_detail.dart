import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/features/profile/sales_person_qr_code.dart';

import '../../core/design/shield_theme.dart';
import '../../core/navigation/shield_router.dart';
import '../../core/notifications/push_notification_service.dart';
import '../../services/referral_service.dart';
import '../safety/services/purchase_services.dart';

class ReferralDetailsScreen extends ConsumerStatefulWidget {
  const ReferralDetailsScreen({super.key});

  @override
  ConsumerState<ReferralDetailsScreen> createState() =>
      _ReferralDetailsScreenState();
}

class _ReferralDetailsScreenState extends ConsumerState<ReferralDetailsScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool isLoad = false;
  final GlobalKey _qrKey = GlobalKey();
  List<Map<String, dynamic>> _commissions = [];

  // --------------------------------------------------
  // Current user's referral information
  // --------------------------------------------------

  String? _referralCode;
  String? userName;
  String? referralUrl;

  // --------------------------------------------------
  // Person who referred current user
  // --------------------------------------------------

  String? _referredByName;
  String? _referredById;
  String? _referredByStatus;
  String? _referredByReferralCode;
  String? _referredByDate;

  // --------------------------------------------------
  // Statistics
  // --------------------------------------------------

  int _totalReferrals = 0;
  int _convertedReferrals = 0;
  int _pendingReferrals = 0;

  // --------------------------------------------------
  // People referred by current user
  // --------------------------------------------------

  List<Map<String, dynamic>> _referrals = [];
  double _totalEarnings = 0.0;
  double _pendingEarnings = 0.0;
  double _paidEarnings = 0.0;
  bool _isLoggingOut = false;
  int _paidReferrals = 0;

  @override
  void initState() {
    super.initState();
    _loadReferralDetails();
  }

  // Future<void> _loadCommissionEarnings(String userId) async {
  //   try {
  //     final data = await supabase
  //         .from('referral_commissions')
  //         .select('commission_amount, status')
  //         .eq('referrer_id', userId);
  //     final currentUser = supabase.auth.currentUser;
  //
  //     debugPrint('COMMISSION DATA: $data');
  //     debugPrint('COMMISSION DATA: $userId');
  //     debugPrint('AUTH USER ID: ${currentUser?.id}');
  //     debugPrint('PASSED USER ID: $userId');
  //     debugPrint('SESSION: ${supabase.auth.currentSession != null}');
  //     double total = 0;
  //     double pending = 0;
  //     double paid = 0;
  //
  //     for (final item in data) {
  //       final amount =
  //           double.tryParse(item['commission_amount'].toString()) ?? 0;
  //
  //       total += amount;
  //
  //       final status = item['status']?.toString().toLowerCase();
  //
  //       if (status == 'pending') {
  //         pending += amount;
  //       } else if (status == 'paid') {
  //         paid += amount;
  //       }
  //     }
  //
  //     _totalEarnings = total;
  //     _pendingEarnings = pending;
  //     _paidEarnings = paid;
  //
  //     debugPrint('Total earnings: $_totalEarnings');
  //     debugPrint('Pending earnings: $_pendingEarnings');
  //     debugPrint('Paid earnings: $_paidEarnings');
  //   } catch (e, stackTrace) {
  //     debugPrint('Commission loading error: $e');
  //     debugPrint(stackTrace.toString());
  //   }
  // }
  Future<void> _loadCommissionEarnings(String userId) async {
    try {
      final data = await supabase
          .from('referral_commissions')
          .select(
            'referral_id, plan_id, commission_amount, status, created_at, paid_at',
          )
          .eq('referrer_id', userId);

      _commissions = List<Map<String, dynamic>>.from(data);

      double total = 0.0;
      double pending = 0.0;
      double paid = 0.0;

      int paidCount = 0;
      int pendingCount = 0;

      for (final commission in _commissions) {
        final amount =
            double.tryParse(
              commission['commission_amount']?.toString() ?? '0',
            ) ??
            0.0;

        final status = commission['status']?.toString().toLowerCase() ?? '';

        total += amount;
        print(status);
        if (status == 'paid') {
          paid += amount;
          paidCount++;
        } else if (status == 'pending') {
          pending += amount;
          pendingCount++;
          print("pendingCount");
          print(pendingCount);
        }
      }

      if (!mounted) return;

      setState(() {
        _totalEarnings = total;
        _pendingEarnings = pending;
        _paidEarnings = paid;

        _paidReferrals = paidCount;
        _pendingReferrals = pendingCount;
      });
    } catch (e) {
      debugPrint('LOAD COMMISSION ERROR: $e');
    }
  }

  // ==================================================
  // LOAD REFERRAL DETAILS
  // ==================================================

  Future<void> _loadReferralDetails() async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }

      final session = supabase.auth.currentSession;

      if (session == null) {
        debugPrint('No active session');
        return;
      }

      final userId = session.user.id;

      debugPrint('Current user: $userId');

      // ==================================================
      // CURRENT USER'S REFERRAL CODE
      // ==================================================
      _loadCommissionEarnings(userId);

      final profile = await supabase
          .from('profiles')
          .select('referral_code,full_name')
          .eq('id', userId)
          .maybeSingle();

      //_referralCode = profile?['referral_code'];
      userName = profile?['full_name'];
      final salesperson = await supabase
          .from('salespersons')
          .select('referral_code, referral_url')
          .eq('user_id', userId)
          .maybeSingle();
      print("salesperson");
      print(salesperson);
      if (salesperson != null) {
        // Prefer the URL stored when the salesperson was created
        referralUrl = salesperson['referral_url']?.toString();

        // If needed, use the salesperson's referral code
        _referralCode = salesperson['referral_code']?.toString();
      }

      debugPrint('Referral code: $_referralCode');
      debugPrint('Branch referral URL: $referralUrl');
      //referralUrl = 'https://well-check.com/ref/$_referralCode';
      debugPrint('Current referral code: $_referralCode');

      // ==================================================
      // PEOPLE REFERRED BY CURRENT USER
      // ==================================================

      // final data = await supabase
      //     .from('referrals')
      //     .select('''
      //       id,
      //       referral_code,
      //       status,
      //       created_at,
      //       converted_at,
      //       user_id,
      //       profiles:user_id (
      //         id,
      //         full_name,
      //         age
      //       )
      //     ''')
      //     .eq('referrer_id', userId)
      //     .order('created_at', ascending: false);
      //
      // _referrals = List<Map<String, dynamic>>.from(data);
      final data = await supabase
          .from('referrals')
          .select('''
      id,
      referral_code,
      status,
      created_at,
      converted_at,
      user_id,
      referred_name,
      referred_email
    ''')
          .eq('referrer_id', userId)
          .order('created_at', ascending: false);

      // final referrals = List<Map<String, dynamic>>.from(data);
      _referrals = List<Map<String, dynamic>>.from(data);

      // _referrals = [];
      //
      // for (final referral in referrals) {
      //   final referredUserId = referral['user_id'];
      //
      //   final profile = await supabase
      //       .from('profiles')
      //       .select('id, full_name, age')
      //       .eq('id', referredUserId)
      //       .maybeSingle();
      //
      //   _referrals.add({...referral, 'profile': profile});
      // }
      debugPrint('People referred: ${_referrals.length}');

      // ==================================================
      // WHO REFERRED CURRENT USER
      // ==================================================

      final referredByData = await supabase
          .from('referrals')
          .select('''
            id,
            referrer_id,
            user_id,
            referral_code,
            status,
            created_at,
            converted_at
          ''')
          .eq('user_id', userId)
          .limit(1);

      debugPrint('REFERRAL RAW DATA: $referredByData');

      if (referredByData.isNotEmpty) {
        final referral = referredByData.first;

        final referrerId = referral['referrer_id'];

        debugPrint('REFERRER ID: $referrerId');

        // --------------------------------------------------
        // Get referrer's profile
        // --------------------------------------------------

        final referrerProfile = await supabase
            .from('profiles')
            .select('id, full_name')
            .eq('id', referrerId)
            .maybeSingle();

        debugPrint('REFERRER PROFILE: $referrerProfile');

        if (referrerProfile != null) {
          _referredById = referrerId;

          _referredByName = referrerProfile['full_name']?.toString();

          _referredByStatus = referral['status']?.toString();

          _referredByReferralCode = referral['referral_code']?.toString();

          _referredByDate = referral['created_at']?.toString();

          debugPrint('REFERRED BY NAME: $_referredByName');
        } else {
          _clearReferredBy();
        }
      } else {
        debugPrint('No referral found for current user');

        _clearReferredBy();
      }

      // ==================================================
      // STATISTICS
      // ==================================================

      _totalReferrals = _referrals.length;

      _convertedReferrals = _referrals
          .where((item) => item['status'] == 'converted')
          .length;

      // _pendingReferrals = _referrals
      //     .where((item) => item['status'] == 'pending')
      //     .length;
      if (mounted) {
        setState(() {});
      }
    } catch (e, stackTrace) {
      debugPrint('Referral loading error: $e');

      debugPrint(stackTrace.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to load referral details')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ==================================================
  // CLEAR REFERRED BY
  // ==================================================

  void _clearReferredBy() {
    _referredByName = null;
    _referredById = null;
    _referredByStatus = null;
    _referredByReferralCode = null;
    _referredByDate = null;
  }

  // ==================================================
  // FORMAT DATE
  // ==================================================

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

  // ==================================================
  // BUILD
  // ==================================================
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

  Future<void> _shareQrImage(BuildContext context) async {
    print("object");
    try {
      setState(() {
        isLoad = true;
      });
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/referral_qr.png').create();
      await file.writeAsBytes(pngBytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Scan or use this link to sign up: ${referralUrl}',
        subject: 'Referral QR Code',
      );
      setState(() {
        isLoad = false;
      });
    } catch (e) {
      setState(() {
        isLoad = false;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not share QR: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLoading ? "Referral Detail" : 'Welcome! $userName'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            onSelected: (value) async {
              switch (value) {
                case 'qr':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          SalespersonQrScreen(referralUrl: referralUrl ?? ""),
                    ),
                  );
                  break;

                case 'logout':
                  _showLogoutConfirmation();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'qr',
                child: Row(
                  children: [
                    Icon(Icons.qr_code),
                    SizedBox(width: 12),
                    Text('Referral QR'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 12),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReferralDetails,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ==================================================
                  // YOUR REFERRAL CODE
                  // ==================================================
                  _buildReferralCodeCard(),

                  const SizedBox(height: 20),

                  // ==================================================
                  // REFERRED BY
                  // ==================================================
                  // _buildReferredByCard(),
                  //
                  // const SizedBox(height: 20),

                  // ==================================================
                  // STATISTICS
                  // ==================================================
                  _buildStatistics(),

                  const SizedBox(height: 28),

                  // ==================================================
                  // PEOPLE YOU REFERRED
                  // ==================================================
                  const Text(
                    'People You Referred',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'Users who joined using your referral code',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),

                  const SizedBox(height: 16),

                  _buildReferralList(),
                ],
              ),
            ),
    );
  }

  // ==================================================
  // REFERRAL CODE CARD
  // ==================================================

  Widget _buildReferralCodeCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            RepaintBoundary(
              key: _qrKey,
              child: QrImageView(
                data: referralUrl ?? "",
                size: 80,
                backgroundColor: Colors.white,
              ),
            ),

            const SizedBox(height: 5),

            const Text(
              'Your Referral Code',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),

            const SizedBox(height: 8),

            Text(
              _referralCode ?? '-',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: referralUrl == null
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SalespersonQrScreen(
                                    referralUrl: referralUrl ?? "",
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.qr_code),
                      label: const Text('View QR'),
                    ),
                  ),
                ),
                SizedBox(width: 15),

                Expanded(
                  child: Container(
                    // clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: ShieldColors.backgroundWhite,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ShieldColors.activeTeal),
                    ),
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ButtonStyle(
                        backgroundColor: WidgetStatePropertyAll(Colors.white),
                      ),
                      onPressed: isLoad ? null : () => _shareQrImage(context),

                      icon: const Icon(
                        Icons.share,
                        color: ShieldColors.activeTeal,
                      ),
                      label: const Text(
                        'Share QR',
                        style: TextStyle(color: ShieldColors.activeTeal),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================================================
  // REFERRED BY CARD
  // ==================================================

  Widget _buildReferredByCard() {
    if (_referredByName == null || _referredByName!.isEmpty) {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(child: Icon(Icons.person_outline)),

              SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Referred By',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),

                    SizedBox(height: 4),

                    Text(
                      'Not referred by anyone',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final firstLetter = _referredByName!.trim().isNotEmpty
        ? _referredByName!.trim().substring(0, 1).toUpperCase()
        : '?';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Referred By',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Text(
                    firstLetter,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _referredByName!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      if (_referredByReferralCode != null) ...[
                        const SizedBox(height: 4),

                        Text(
                          _referredByReferralCode!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],

                      if (_referredByDate != null) ...[
                        const SizedBox(height: 4),

                        Text(
                          'Referred on ${_formatDate(_referredByDate)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                if (_referredByStatus != null)
                  _StatusBadge(status: _referredByStatus!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================================================
  // STATISTICS
  // ==================================================

  Widget _buildStatistics() {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            title: 'Total',
            value: _totalReferrals.toString(),
            icon: Icons.people,
          ),
        ),

        //  const SizedBox(width: 10),

        // Expanded(
        //   child: _StatCard(
        //     title: 'Converted',
        //     value: _convertedReferrals.toString(),
        //     icon: Icons.check_circle,
        //   ),
        // ),
        //
        // const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            title: 'Paid',
            value: _paidReferrals.toString(),
            icon: Icons.check_circle,
          ),
        ),

        Expanded(
          child: _StatCard(
            title: 'Pending',
            value: _pendingReferrals.toString(),
            icon: Icons.pending,
          ),
        ),

        Expanded(
          child: _StatCard(
            title: 'Earnings',
            value: _totalEarnings.toString(),
            icon: Icons.attach_money_outlined,
          ),
        ),
      ],
    );
  }

  // ==================================================
  // REFERRAL LIST
  // ==================================================
  Map<String, dynamic>? _getCommissionForReferral(
    Map<String, dynamic> referral,
  ) {
    final referralId = referral['id']?.toString();

    if (referralId == null || referralId.isEmpty) {
      return null;
    }

    for (final commission in _commissions) {
      if (commission['referral_id']?.toString() == referralId) {
        return commission;
      }
    }

    return null;
  }

  Widget _buildReferralList() {
    if (_referrals.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
          child: Column(
            children: [
              Icon(Icons.people_outline, size: 50, color: Colors.grey.shade400),

              const SizedBox(height: 12),

              const Text(
                'No referrals yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),

              const SizedBox(height: 4),

              Text(
                'Share your referral QR code to invite people.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _referrals.map((referral) {
        final profile = referral['profile'] as Map<String, dynamic>?;
        print("profileprofile");
        print(profile);
        // Your query returns full_name, NOT name.
        final name =
            referral['referred_name']?.toString().trim().isNotEmpty == true
            ? referral['referred_name'].toString()
            : 'Unknown User';
        print(referral);
        print("referralreferral");
        final email = referral['referred_email']?.toString();

        final status = referral['status']?.toString() ?? 'pending';

        //final status = referral['status']?.toString() ?? 'pending';

        final referralCode = referral['referral_code']?.toString();

        final createdAt = referral['created_at']?.toString();

        final convertedAt = referral['converted_at']?.toString();

        final firstLetter = name.trim().isNotEmpty
            ? name.trim().substring(0, 1).toUpperCase()
            : '?';
        final commission = _getCommissionForReferral(referral);

        final planId = commission?['plan_id']?.toString() == "wellcheck_pro"
            ? "Basic"
            : commission?['plan_id']?.toString() == "wellcheck_premium"
            ? "Premium"
            : "";

        final paymentStatus = commission?['status']?.toString().toLowerCase();
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      child: Text(
                        firstLetter,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
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

                          // if (age != null && age.isNotEmpty) ...[
                          //   const SizedBox(height: 3),
                          //
                          //   Text(
                          //     'Age: $age',
                          //     style: TextStyle(
                          //       fontSize: 13,
                          //       color: Colors.grey.shade600,
                          //     ),
                          //   ),
                          // ],
                        ],
                      ),
                    ),

                    //  _StatusBadge(status: status),
                  ],
                ),

                //  const SizedBox(height: 12),

                //   const Divider(height: 1),
                //   const SizedBox(height: 10),
                if (commission != null) ...[
                  const SizedBox(height: 15),

                  const Divider(height: 1),

                  const SizedBox(height: 15),

                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Payment Details',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Plan ID
                  if (planId != null && planId.isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.card_membership_outlined,
                          size: 15,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Plan ID: $planId',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),

                  if (planId != null && planId.isNotEmpty)
                    const SizedBox(height: 6),

                  // Payment Status
                  Row(
                    children: [
                      Icon(
                        paymentStatus == 'paid'
                            ? Icons.check_circle_outline
                            : Icons.pending_outlined,
                        size: 15,
                        color: paymentStatus == 'paid'
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Payment: ',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        paymentStatus == 'paid' ? 'Paid' : 'Pending',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: paymentStatus == 'paid'
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 15,
                      color: Colors.grey.shade600,
                    ),

                    const SizedBox(width: 6),

                    Text(
                      'Referred: ${_formatDate(createdAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),

                // if (convertedAt != null && convertedAt.isNotEmpty) ...[
                //   const SizedBox(height: 6),
                //
                //   Row(
                //     children: [
                //       Icon(
                //         Icons.check_circle_outline,
                //         size: 15,
                //         color: Colors.green.shade600,
                //       ),
                //
                //       const SizedBox(width: 6),
                //
                //       Text(
                //         'Converted: ${_formatDate(convertedAt)}',
                //         style: TextStyle(
                //           fontSize: 12,
                //           color: Colors.green.shade700,
                //         ),
                //       ),
                //     ],
                //   ),
                // ],
                if (referralCode != null && referralCode.isNotEmpty) ...[
                  const SizedBox(height: 6),

                  Row(
                    children: [
                      Icon(
                        Icons.qr_code_2,
                        size: 15,
                        color: Colors.grey.shade600,
                      ),

                      const SizedBox(width: 6),

                      Text(
                        referralCode,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ======================================================
// STAT CARD
// ======================================================

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
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, size: 24),

            const SizedBox(height: 8),

            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 4),

            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================
// STATUS BADGE
// ======================================================

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isConverted = status.toLowerCase() == 'converted';

    final isPending = status.toLowerCase() == 'pending';

    String label;

    if (isConverted) {
      label = 'Converted';
    } else if (isPending) {
      label = 'Pending';
    } else {
      label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isConverted
            ? Colors.green.withOpacity(0.1)
            : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isConverted ? Colors.green : Colors.orange,
        ),
      ),
    );
  }
}
