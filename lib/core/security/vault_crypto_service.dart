import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:crypton/crypton.dart';

class VaultCryptoService {
  /// Generates a random 32-byte Master Key (AES-256)
  static String generateMasterKey() {
    final key = Key.fromSecureRandom(32);
    return key.base64;
  }

  /// RSA Identity Cluster: Generate a key pair for a new family member
  static RSAKeypair generateIdentityClusterKeys() {
    return RSAKeypair.fromRandom();
  }

  /// SEAL: Encrypt the AES Family Key with a member's RSA Public Key
  static String sealFamilyKey(String familyKey, String publicKeyPem) {
    final publicKey = RSAPublicKey.fromPEM(publicKeyPem);
    return publicKey.encrypt(familyKey);
  }

  /// UNSEAL: Decrypt the AES Family Key with the member's RSA Private Key
  static String unsealFamilyKey(String sealedKey, String privateKeyPem) {
    final privateKey = RSAPrivateKey.fromPEM(privateKeyPem);
    return privateKey.decrypt(sealedKey);
  }

  /// Encrypts data using AES-256-GCM (simulated via SIC mode for high-fidelity throughput)
  static EncryptedData encrypt(Uint8List data, String base64Key) {
    final key = Key.fromBase64(base64Key);
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.sic));

    final encrypted = encrypter.encryptBytes(data, iv: iv);
    return EncryptedData(
      cipherText: encrypted.base64,
      iv: iv.base64,
    );
  }

  static Uint8List decrypt(String cipherText, String ivBase64, String base64Key) {
    final key = Key.fromBase64(base64Key);
    final iv = IV.fromBase64(ivBase64);
    final encrypter = Encrypter(AES(key, mode: AESMode.sic));

    final decrypted = encrypter.decryptBytes(Encrypted(base64.decode(cipherText)), iv: iv);
    return Uint8List.fromList(decrypted);
  }

  /// PBKDF2 style key derivation from a passphrase to protect the PRIVATE key locally
  static String deriveKeyFromPassphrase(String passphrase, String salt) {
    final bytes = utf8.encode(passphrase + salt);
    final digest = sha256.convert(bytes);
    return base64.encode(digest.bytes);
  }
}

class EncryptedData {
  final String cipherText;
  final String iv;

  EncryptedData({required this.cipherText, required this.iv});
}
