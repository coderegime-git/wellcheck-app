import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddSalespersonScreen extends StatefulWidget {
  const AddSalespersonScreen({super.key});

  @override
  State<AddSalespersonScreen> createState() => _AddSalespersonScreenState();
}

class _AddSalespersonScreenState extends State<AddSalespersonScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  final SupabaseClient supabase = Supabase.instance.client;

  final ImagePicker _imagePicker = ImagePicker();

  final ScreenshotController _qrScreenshotController = ScreenshotController();

  File? _businessCardImage;

  String? _businessCardUrl;
  String? _referralCode;
  String? _referralUrl;

  bool _isLoading = false;
  bool _isUploadingCard = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickBusinessCard() async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) {
          return SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Take Photo'),
                  onTap: () {
                    Navigator.pop(context, ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from Gallery'),
                  onTap: () {
                    Navigator.pop(context, ImageSource.gallery);
                  },
                ),
              ],
            ),
          );
        },
      );

      if (source == null) {
        return;
      }

      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        return;
      }

      setState(() {
        _businessCardImage = File(pickedFile.path);
      });
    } catch (e) {
      if (!mounted) return;

      _showError('Unable to select business card: $e');
    }
  }

  Future<String?> _uploadBusinessCard() async {
    if (_businessCardImage == null) {
      return null;
    }

    setState(() {
      _isUploadingCard = true;
    });

    try {
      final file = _businessCardImage!;

      final fileExtension = file.path.split('.').last.toLowerCase();

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}.$fileExtension';

      final filePath = 'salesperson-business-cards/$fileName';

      await supabase.storage
          .from('business-cards')
          .upload(
            filePath,
            file,
            fileOptions: const FileOptions(upsert: false),
          );

      debugPrint('Business card uploaded: $filePath');

      // Store the actual Storage path, not a public URL.
      return filePath;
    } catch (e) {
      if (!mounted) return null;

      debugPrint('BUSINESS CARD UPLOAD ERROR: $e');

      _showError('Unable to upload business card: $e');

      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingCard = false;
        });
      }
    }
  }

  Future<void> _addSalesperson() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_businessCardImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please upload Business card")),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
    });

    try {
      final phone = _phoneController.text.trim();
      final email = _emailController.text.trim().toLowerCase();

      // --------------------------------------------------------
      // Check if phone number already exists
      // --------------------------------------------------------

      final existingPhone = await supabase
          .from('salespersons')
          .select('id')
          .eq('phone', phone)
          .limit(1);

      if (existingPhone.isNotEmpty) {
        _showError('A salesperson with this phone number already exists');
        return;
      }

      // --------------------------------------------------------
      // Check if email already exists
      // --------------------------------------------------------

      final existingEmail = await supabase
          .from('salespersons')
          .select('id')
          .eq('email', email)
          .maybeSingle();

      if (existingEmail != null) {
        _showError('A salesperson with this email already exists');
        return;
      }

      // --------------------------------------------------------
      // Upload business card
      // --------------------------------------------------------

      String? businessCardUrl;

      if (_businessCardImage != null) {
        businessCardUrl = await _uploadBusinessCard();

        if (businessCardUrl == null) {
          return;
        }
      }

      // --------------------------------------------------------
      // Create salesperson
      // --------------------------------------------------------

      final response = await supabase.functions.invoke(
        'create-salesperson',
        body: {
          'name': _nameController.text.trim(),
          'email': email,
          'phone': phone,
          'business_card_url': businessCardUrl,
        },
      );

      final data = response.data;

      if (data == null) {
        throw Exception('Empty response from server');
      }

      if (data['success'] != true) {
        print(data);
        print("datadata");
        throw Exception(data['error'] ?? 'Unable to create salesperson');
      }

      final salesperson = data['salesperson'];

      if (salesperson == null) {
        throw Exception('Salesperson data was not returned');
      }

      setState(() {
        _businessCardUrl = salesperson['business_card_url']?.toString();

        _referralCode = salesperson['referral_code']?.toString();

        _referralUrl = salesperson['referral_url']?.toString();
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Salesperson created successfully')),
      );
    } catch (e) {
      print(e.toString());

      String message = 'Unable to create salesperson';

      if (e is FunctionException && e.details is Map) {
        message = e.details['error']?.toString() ?? message;
      }

      _showError(message);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // COPY REFERRAL URL
  // ============================================================

  Future<void> _copyReferralUrl() async {
    if (_referralUrl == null) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: _referralUrl!));

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Referral link copied')));
  }

  // ============================================================
  // SAVE / SHARE QR
  // ============================================================

  Future<void> _shareQrCode() async {
    if (_referralUrl == null) {
      return;
    }

    try {
      final Uint8List? imageBytes = await _qrScreenshotController.capture(
        pixelRatio: 3,
      );

      if (imageBytes == null) {
        throw Exception('Unable to generate QR image');
      }

      final directory = await getTemporaryDirectory();

      final file = File(
        '${directory.path}/'
        'salesperson_qr_${_referralCode ?? 'code'}.png',
      );

      await file.writeAsBytes(imageBytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            'WellCheck Referral QR Code\n'
            '${_referralUrl!}',
      );
    } catch (e) {
      if (!mounted) return;

      _showError('Unable to share QR code: $e');
    }
  }

  // ============================================================
  // CLEAR FORM
  // ============================================================

  void _clearForm() {
    setState(() {
      _nameController.clear();
      _emailController.clear();
      _phoneController.clear();

      _businessCardImage = null;
      _businessCardUrl = null;
      _referralCode = null;
      _referralUrl = null;
    });
  }

  // ============================================================
  // ERROR
  // ============================================================

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // ============================================================
  // INPUT DECORATION
  // ============================================================

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(width: 2),
      ),
    );
  }

  // ============================================================
  // BUSINESS CARD SECTION
  // ============================================================

  Widget _buildBusinessCardSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Business Card',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),

        const SizedBox(height: 10),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              if (_businessCardImage != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    _businessCardImage!,
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.business_center_outlined,
                        size: 45,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'No business card selected',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoading || _isUploadingCard
                      ? null
                      : _pickBusinessCard,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(
                    _businessCardImage == null
                        ? 'Choose Business Card'
                        : 'Change Business Card',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // QR SECTION
  // ============================================================

  Widget _buildQrSection() {
    if (_referralUrl == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),

        const Text(
          'Referral QR Code',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 6),

        const Text(
          'Customers can scan this QR code to use this salesperson referral.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),

        const SizedBox(height: 16),

        Center(
          child: Screenshot(
            controller: _qrScreenshotController,
            child: Container(
              padding: const EdgeInsets.all(24),
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'WellCheck',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 14),

                  QrImageView(
                    data: _referralUrl!,
                    version: QrVersions.auto,
                    size: 230,
                    backgroundColor: Colors.white,
                  ),

                  const SizedBox(height: 12),

                  if (_referralCode != null)
                    Text(
                      _referralCode!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                  const SizedBox(height: 5),

                  const Text(
                    'Scan to sign up',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        if (_referralCode != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Referral Code',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  _referralCode!,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

        const SizedBox(height: 10),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _referralUrl!,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              IconButton(
                onPressed: _copyReferralUrl,
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _shareQrCode,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share QR Code'),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SUCCESS SECTION
  // ============================================================

  Widget _buildSuccessSection() {
    if (_referralUrl == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade600),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Salesperson Created',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            '${_nameController.text} has been added successfully.',
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final salespersonCreated = _referralUrl != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Salesperson')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Salesperson Details',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 6),

                const Text(
                  'Add a salesperson and generate their unique referral QR code.',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),

                const SizedBox(height: 25),

                // NAME
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                    label: 'Salesperson Name',
                    icon: Icons.person_outline,
                    hint: 'Enter salesperson name',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter salesperson name';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // EMAIL
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                    label: 'Email',
                    icon: Icons.email_outlined,
                    hint: 'Enter salesperson email',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter email';
                    }

                    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

                    if (!emailRegex.hasMatch(value.trim())) {
                      return 'Please enter a valid email';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // PHONE
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  decoration: _inputDecoration(
                    label: 'Phone Number',
                    icon: Icons.phone_outlined,
                    hint: 'Enter phone number',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter phone number';
                    }
                    if (RegExp(r'^(\d)\1+$').hasMatch(value)) {
                      return 'Please enter a valid phone number';
                    }
                    if (value.length < 7) {
                      return 'Phone number must be at least 7 digits';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // BUSINESS CARD
                _buildBusinessCardSection(),

                const SizedBox(height: 28),

                // ADD BUTTON
                if (!salespersonCreated)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _addSalesperson,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.person_add_alt_1),
                      label: Text(
                        _isLoading
                            ? _isUploadingCard
                                  ? 'Uploading Business Card...'
                                  : 'Creating Salesperson...'
                            : 'Add Salesperson',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                // SUCCESS
                _buildSuccessSection(),

                // QR
                _buildQrSection(),

                if (salespersonCreated)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton(
                        onPressed: _clearForm,
                        child: const Text('Add Another Salesperson'),
                      ),
                    ),
                  ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
