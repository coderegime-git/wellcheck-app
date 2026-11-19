import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditSalespersonScreen extends StatefulWidget {
  final Map<String, dynamic> salesperson;

  const EditSalespersonScreen({super.key, required this.salesperson});

  @override
  State<EditSalespersonScreen> createState() => _EditSalespersonScreenState();
}

class _EditSalespersonScreenState extends State<EditSalespersonScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  final ImagePicker _picker = ImagePicker();

  late final TextEditingController nameController;
  late final TextEditingController emailController;
  late final TextEditingController phoneController;

  bool isLoading = false;
  bool _isUploadingCard = false;

  // Newly selected image from camera/gallery
  File? _businessCardImage;

  // Existing/saved business card URL
  String? _businessCardUrl;

  // Signed URL used only for displaying private bucket image
  String? _businessCardDisplayUrl;

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(
      text: widget.salesperson['name']?.toString() ?? '',
    );

    emailController = TextEditingController(
      text: widget.salesperson['email']?.toString() ?? '',
    );

    phoneController = TextEditingController(
      text: widget.salesperson['phone']?.toString() ?? '',
    );

    _businessCardUrl = widget.salesperson['business_card_url']?.toString();

    debugPrint('Existing business card URL: $_businessCardUrl');

    _loadBusinessCard();
  }

  // ------------------------------------------------------------
  // LOAD EXISTING BUSINESS CARD
  // ------------------------------------------------------------

  Future<void> _loadBusinessCard() async {
    final filePath = widget.salesperson['business_card_url']?.toString();

    debugPrint('Existing business card path: $filePath');

    if (filePath == null || filePath.isEmpty) {
      return;
    }

    try {
      final signedUrl = await supabase.storage
          .from('business-cards')
          .createSignedUrl(filePath, 60 * 60);

      debugPrint('Signed business card URL: $signedUrl');

      if (!mounted) return;

      setState(() {
        _businessCardUrl = filePath;
        _businessCardDisplayUrl = signedUrl;
      });
    } catch (e) {
      debugPrint('BUSINESS CARD LOAD ERROR: $e');
    }
  }

  //
  // ------------------------------------------------------------
  // PICK BUSINESS CARD
  // ------------------------------------------------------------

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

      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        return;
      }

      if (!mounted) return;

      setState(() {
        _businessCardImage = File(pickedFile.path);
      });

      debugPrint('New business card selected: ${pickedFile.path}');
    } catch (e) {
      debugPrint('Pick business card error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to select business card: $e')),
      );
    }
  }

  // ------------------------------------------------------------
  // UPLOAD BUSINESS CARD
  // ------------------------------------------------------------

  Future<String?> _uploadBusinessCard() async {
    if (_businessCardImage == null) {
      return null;
    }

    setState(() {
      _isUploadingCard = true;
    });

    try {
      final file = _businessCardImage!;

      // Get file extension
      final fileExtension = file.path.split('.').last.toLowerCase();

      // Generate unique file name
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}.$fileExtension';

      // Storage path
      final filePath = 'salesperson-business-cards/$fileName';

      debugPrint('Uploading business card...');
      debugPrint('Bucket: business-cards');
      debugPrint('File path: $filePath');

      // --------------------------------------------------------
      // UPLOAD TO SUPABASE STORAGE
      // --------------------------------------------------------

      await supabase.storage
          .from('business-cards')
          .upload(
            filePath,
            file,
            fileOptions: const FileOptions(upsert: false),
          );

      debugPrint('Business card uploaded successfully: $filePath');

      // --------------------------------------------------------
      // IMPORTANT:
      // Return STORAGE PATH, NOT public URL
      // --------------------------------------------------------

      return filePath;
    } catch (e, stackTrace) {
      debugPrint('BUSINESS CARD UPLOAD ERROR: $e');

      debugPrint(stackTrace.toString());

      if (mounted) {
        _showError('Unable to upload business card: $e');
      }

      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingCard = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // ------------------------------------------------------------
  // BUSINESS CARD UI
  // ------------------------------------------------------------

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
              // ------------------------------------------------
              // NEWLY SELECTED IMAGE
              // ------------------------------------------------
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
              // ------------------------------------------------
              // EXISTING IMAGE
              // ------------------------------------------------
              else if (_businessCardDisplayUrl != null &&
                  _businessCardDisplayUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    _businessCardDisplayUrl!,
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        return child;
                      }

                      return Container(
                        height: 180,
                        width: double.infinity,
                        color: Colors.grey.shade100,
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 180,
                        width: double.infinity,
                        color: Colors.grey.shade100,
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.business_center_outlined,
                              size: 50,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Unable to load business card',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                )
              // ------------------------------------------------
              // NO IMAGE
              // ------------------------------------------------
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
                        'No business card',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 14),

              // ------------------------------------------------
              // CHANGE / ADD BUTTON
              // ------------------------------------------------
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isLoading || _isUploadingCard
                      ? null
                      : _pickBusinessCard,
                  icon: _isUploadingCard
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_outlined),
                  label: Text(
                    _businessCardImage != null ||
                            (_businessCardUrl != null &&
                                _businessCardUrl!.isNotEmpty)
                        ? 'Change Business Card'
                        : 'Add Business Card',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // UPDATE SALESPERSON
  // ------------------------------------------------------------

  Future<void> _updateSalesperson() async {
    final name = nameController.text.trim();
    final email = emailController.text.trim().toLowerCase();
    final phone = phoneController.text.trim();

    if (name.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and email are required')),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final salespersonId = widget.salesperson['id']?.toString();

      final userId = widget.salesperson['user_id']?.toString();

      debugPrint('==============================');
      debugPrint('UPDATE SALESPERSON');
      debugPrint('Salesperson ID: $salespersonId');
      debugPrint('User ID: $userId');
      debugPrint('Name: $name');
      debugPrint('Email: $email');
      debugPrint('Phone: $phone');
      debugPrint('==============================');

      if (salespersonId == null || salespersonId.isEmpty) {
        throw Exception('Salesperson ID is missing');
      }

      // --------------------------------------------------------
      // 1. UPLOAD NEW BUSINESS CARD IF SELECTED
      // --------------------------------------------------------

      String? businessCardUrl = _businessCardUrl;

      if (_businessCardImage != null) {
        businessCardUrl = await _uploadBusinessCard();

        if (businessCardUrl == null) {
          throw Exception('Business card upload failed');
        }
      }

      // --------------------------------------------------------
      // 2. UPDATE SALESPERSON
      // --------------------------------------------------------

      final salespersonUpdate = {
        'name': name,
        'email': email,
        'phone': phone.isEmpty ? null : phone,
        'business_card_url': businessCardUrl,
        'updated_at': DateTime.now().toIso8601String(),
      };

      debugPrint('Salesperson update data: $salespersonUpdate');

      final updatedSalesperson = await supabase
          .from('salespersons')
          .update(salespersonUpdate)
          .eq('id', salespersonId)
          .select()
          .single();

      debugPrint('UPDATED SALESPERSON: $updatedSalesperson');

      // --------------------------------------------------------
      // 3. UPDATE PROFILE
      // --------------------------------------------------------

      if (userId != null && userId.isNotEmpty) {
        final profileUpdate = {
          'full_name': name,
          'email': email,
          'phone': phone.isEmpty ? null : phone,
        };

        debugPrint('Profile update data: $profileUpdate');

        final updatedProfile = await supabase
            .from('profiles')
            .update(profileUpdate)
            .eq('id', userId)
            .select()
            .single();

        debugPrint('UPDATED PROFILE: $updatedProfile');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Salesperson updated successfully')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('================================');
      debugPrint('UPDATE SALESPERSON ERROR');
      debugPrint(e.toString());
      debugPrint('================================');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update salesperson: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Salesperson')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            _buildBusinessCardSection(),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: isLoading || _isUploadingCard
                    ? null
                    : _updateSalesperson,
                child: isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
