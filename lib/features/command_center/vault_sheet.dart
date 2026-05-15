import 'dart:io';
import 'dart:typed_data';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/security/vault_crypto_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

class VaultSheet extends ConsumerStatefulWidget {
  final bool isMedical;
  final bool fromLeader;

  const VaultSheet({
    super.key,
    this.isMedical = false,
    this.fromLeader = false,
  });

  @override
  ConsumerState<VaultSheet> createState() => _VaultSheetState();
}

class _VaultSheetState extends ConsumerState<VaultSheet> {
  bool _isLoading = false;
  List<FileObject> _vaultFiles = [];
  String? _familyKey;

  @override
  void initState() {
    super.initState();
    _logVaultAccess();
    _loadVaultFiles();
    _loadOrGenerateKey();
  }

  String get _bucketName => widget.isMedical ? 'medical_vault' : 'family_vault';

  Future<void> _loadOrGenerateKey() async {
    // In production: retrieve from secure storage / RSA-sealed key exchange
    // For now: generate a deterministic key per session
    _familyKey = VaultCryptoService.generateMasterKey();
  }

  Future<void> _logVaultAccess() async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;
      int batteryLevel =
          100; // Safe default for simulators and aggressive background iOS policies
      try {
        final battery = Battery();
        batteryLevel = await battery.batteryLevel;
      } catch (e) {
        debugPrint(
          'Battery info not available over isolate, using default: $e',
        );
      }
      await Supabase.instance.client.from('well_events').insert({
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'event_type': 'status_update',
        'title': 'Secure Vault Accessed',
        'battery_level': batteryLevel,

        'description':
            '${profile.fullName ?? 'User'} opened the ${widget.isMedical ? 'Medical' : 'Family'} Vault.',
      });
    } catch (_) {}
  }

  Future<void> _loadVaultFiles() async {
    setState(() => _isLoading = true);
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;

      final files = await Supabase.instance.client.storage
          .from(_bucketName)
          .list(path: profile.familyId);

      if (mounted) {
        setState(() {
          _vaultFiles = files
              .where((f) => f.name != '.emptyFolderPlaceholder')
              .toList();
        });
      }
    } on StorageException catch (e) {
      debugPrint('Vault listing error (bucket may not exist): ${e.message}');
    } catch (e) {
      debugPrint('Vault listing error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadDocument() async {
    if (_familyKey == null) return;
    setState(() => _isLoading = true);

    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile found');

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'png', 'txt', 'doc', 'docx'],
      );

      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;
      final rawBytes = await file.readAsBytes();

      // E2E Encrypt the file before uploading
      final encrypted = VaultCryptoService.encrypt(rawBytes, _familyKey!);

      // Store encrypted blob with IV prepended in metadata
      final encryptedFileName = '$fileName.enc';
      final path = '${profile.familyId}/$encryptedFileName';

      // Upload encrypted bytes
      final encryptedBytes = Uint8List.fromList([
        ...encrypted.iv.codeUnits,
        ...encrypted.cipherText.codeUnits,
      ]);

      await Supabase.instance.client.storage
          .from(_bucketName)
          .uploadBinary(
            path,
            encryptedBytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.lock, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Document encrypted & uploaded securely.'),
              ],
            ),
            backgroundColor: ShieldColors.safeZoneGreen,
          ),
        );
        await _loadVaultFiles();
      }
    } on StorageException catch (se) {
      print(se.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Storage error: ${se.message} (Is bucket "$_bucketName" configured?)',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadAndDecrypt(String fileName) async {
    if (_familyKey == null) return;
    setState(() => _isLoading = true);

    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;

      final path = '${profile.familyId}/$fileName';
      final encryptedBytes = await Supabase.instance.client.storage
          .from(_bucketName)
          .download(path);

      // For .enc files, decrypt; otherwise serve raw
      if (fileName.endsWith('.enc')) {
        // In production: parse IV from stored metadata
        // For now: inform the user the file is encrypted
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Downloaded encrypted file: $fileName (${encryptedBytes.length} bytes)',
              ),
              backgroundColor: ShieldColors.activeTeal,
            ),
          );
        }
      } else {
        // Unencrypted file
        final dir = await getTemporaryDirectory();
        final outputFile = File('${dir.path}/$fileName');
        await outputFile.writeAsBytes(encryptedBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved to: ${outputFile.path}'),
              backgroundColor: ShieldColors.activeTeal,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ShieldColors.backgroundWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lock,
                          size: 16,
                          color: widget.isMedical
                              ? ShieldColors.alertRed
                              : ShieldColors.activeTeal,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.isMedical ? 'Medical Vault' : 'Family Vault',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'AES-256 End-to-End Encrypted',
                      style: TextStyle(
                        color: ShieldColors.activeTeal,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.fromLeader == true)
                _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: Icon(
                          Icons.upload_file,
                          color: widget.isMedical
                              ? ShieldColors.alertRed
                              : ShieldColors.activeTeal,
                          size: 28,
                        ),
                        onPressed: _uploadDocument,
                      ),
              GestureDetector(
                onTap: () async {
                  Navigator.of(context).pop();
                },
                child: Container(
                  padding: EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade400,
                        offset: Offset(0, 0),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.close, color: Colors.black, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _vaultFiles.isEmpty && !_isLoading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.folder_open_outlined,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No documents yet',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (widget.fromLeader == true)
                          Text(
                            'Tap the upload icon to add encrypted files',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _vaultFiles.length,
                    itemBuilder: (context, index) {
                      final file = _vaultFiles[index];
                      final isEncrypted = file.name.endsWith('.enc');
                      final displayName = isEncrypted
                          ? file.name.replaceAll('.enc', '')
                          : file.name;

                      IconData fileIcon = Icons.description;
                      if (displayName.endsWith('.pdf')) {
                        fileIcon = Icons.picture_as_pdf;
                      } else if (displayName.endsWith('.jpg') ||
                          displayName.endsWith('.png')) {
                        fileIcon = Icons.image;
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: ShieldDesign.roundedTwelve,
                        ),
                        child: ListTile(
                          leading: Icon(fileIcon, color: Colors.grey.shade700),
                          title: Text(
                            displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              if (isEncrypted)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ShieldColors.activeTeal.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.lock,
                                        size: 10,
                                        color: ShieldColors.activeTeal,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'E2E Encrypted',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: ShieldColors.activeTeal,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Text(
                                  'Unencrypted',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.download_rounded,
                              color: ShieldColors.activeTeal,
                            ),
                            onPressed: () => _downloadAndDecrypt(file.name),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
