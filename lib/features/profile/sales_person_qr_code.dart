import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';

class SalespersonQrScreen extends StatefulWidget {
  final String referralUrl;
  final String? salespersonName;

  SalespersonQrScreen({
    // remove `const` since we now have a non-const field
    super.key,
    required this.referralUrl,
    this.salespersonName,
  });

  @override
  State<SalespersonQrScreen> createState() => _SalespersonQrScreenState();
}

class _SalespersonQrScreenState extends State<SalespersonQrScreen> {
  final GlobalKey _qrKey = GlobalKey();
  bool isLoad = false;

  Future<void> _shareQrImage(BuildContext context) async {
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
        text: 'Scan or use this link to sign up: ${widget.referralUrl}',
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

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.referralUrl));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link copied to clipboard'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _shareLink() async {
    await Share.share(widget.referralUrl, subject: 'Join via my referral link');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Referral QR Code'),
        backgroundColor: const Color(0xFFF5F6FA),
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              // QR Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 32,
                  horizontal: 24,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    if (widget.salespersonName != null) ...[
                      Text(
                        widget.salespersonName!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEDEDF2)),
                      ),
                      child: RepaintBoundary(
                        key: _qrKey,
                        child: QrImageView(
                          data: widget.referralUrl,
                          size: 220,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Scan this code to sign up with\nyour referral automatically applied',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Link row (copy)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEDEDF2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 20, color: Colors.black45),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.referralUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _copyLink(context),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF1A73E8),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text(
                        'COPY',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Share button (GPay-style pill)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: isLoad
                    ? Center(child: CircularProgressIndicator())
                    : ElevatedButton.icon(
                        onPressed: isLoad ? null : () => _shareQrImage(context),
                        icon: const Icon(Icons.share_outlined, size: 20),
                        label: const Text(
                          'Share',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ShieldColors.activeTeal,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
