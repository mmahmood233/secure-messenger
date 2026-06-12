// Secret chat encryption service.
//
// This service contains the cryptography used by secret chats. The important
// idea is:
// - RSA-OAEP is used only to protect/share the chat key.
// - AES-GCM is used to encrypt the actual messages and media.
//
// Supabase stores public keys, encrypted chat keys, encrypted messages, and
// encrypted media. The raw private key and raw chat key stay on the phone in
// secure storage.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:secure_messenger/core/constants/app_constants.dart';
import 'package:secure_messenger/core/errors/app_exception.dart';

class EncryptionService {
  final FlutterSecureStorage _secureStorage;

  EncryptionService(this._secureStorage);

  Future<String> ensureIdentityKeyPair() async {
    // Each device has one long-term RSA identity key pair for secret chats.
    //
    // Public key: saved to Supabase profile so other users can encrypt a chat
    // key for this user.
    //
    // Private key: saved only in secure storage so this device can decrypt chat
    // keys that were encrypted for it.
    final existingPublic = await _secureStorage.read(
      key: AppConstants.identityPublicKey,
    );
    final existingPrivate = await _secureStorage.read(
      key: AppConstants.identityPrivateKey,
    );
    if (existingPublic != null && existingPrivate != null) {
      return existingPublic;
    }

    // RSA-OAEP is used later to wrap the symmetric chat key for each user. This
    // is not used to encrypt every message because RSA is slow and only supports
    // small payloads.
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          _secureRandom(),
        ),
      );
    final pair = generator.generateKeyPair();
    final publicKey = pair.publicKey as RSAPublicKey;
    final privateKey = pair.privateKey as RSAPrivateKey;

    final publicJson = jsonEncode({
      'n': _bigIntToBase64(publicKey.modulus!),
      'e': _bigIntToBase64(publicKey.exponent!),
    });
    final privateJson = jsonEncode({
      'n': _bigIntToBase64(privateKey.modulus!),
      'd': _bigIntToBase64(privateKey.privateExponent!),
      'p': _bigIntToBase64(privateKey.p!),
      'q': _bigIntToBase64(privateKey.q!),
    });

    await _secureStorage.write(
      key: AppConstants.identityPublicKey,
      value: publicJson,
    );
    await _secureStorage.write(
      key: AppConstants.identityPrivateKey,
      value: privateJson,
    );
    return publicJson;
  }

  Future<Map<String, String>> generateKeyPair(String chatId) async {
    final keyBase64 = _randomBase64(32);
    await storeChatKey(chatId, keyBase64);
    return {'key': keyBase64};
  }

  Future<String> generateAndStoreChatKey(String chatId) async {
    // A secret chat uses one random symmetric key. AES-GCM uses a 32-byte key
    // here, which is AES-256.
    final keyBase64 = _randomBase64(32);
    await storeChatKey(chatId, keyBase64);
    return keyBase64;
  }

  Future<void> storeChatKey(String chatId, String keyBase64) async {
    // Chat keys are stored per chat id. If this device loses this key, it cannot
    // read old secret messages unless the key is provided again.
    await _secureStorage.write(
      key: '${AppConstants.secretKeyPrefix}$chatId',
      value: keyBase64,
    );
  }

  Future<bool> hasKeysForChat(String chatId) async {
    final key = await _secureStorage.read(
      key: '${AppConstants.secretKeyPrefix}$chatId',
    );
    return key != null;
  }

  Future<String?> getChatKey(String chatId) {
    return _secureStorage.read(key: '${AppConstants.secretKeyPrefix}$chatId');
  }

  Future<Map<String, String>?> getKeysForChat(String chatId) async {
    final keyBase64 = await getChatKey(chatId);
    if (keyBase64 == null) return null;
    return {'key': keyBase64};
  }

  Future<String> encryptChatKeyForUser(
    String chatKeyBase64,
    String publicKeyJson,
  ) async {
    try {
      // Encrypt the AES chat key with one participant's public RSA key. The
      // result is stored in chats.encrypted_keys[userId].
      final publicKey = _decodePublicKey(publicKeyJson);
      final cipher = OAEPEncoding(RSAEngine())
        ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
      return base64Encode(cipher.process(utf8.encode(chatKeyBase64)));
    } catch (e) {
      throw EncryptionException('Failed to encrypt chat key: $e');
    }
  }

  Future<String> decryptChatKeyForCurrentDevice(String encryptedKey) async {
    try {
      // This is the reverse of encryptChatKeyForUser. The encrypted chat key
      // comes from Supabase, but only this device's private key can open it.
      final privateJson = await _secureStorage.read(
        key: AppConstants.identityPrivateKey,
      );
      if (privateJson == null) {
        throw const EncryptionException('Device identity key is missing.');
      }
      final privateKey = _decodePrivateKey(privateJson);
      final cipher = OAEPEncoding(RSAEngine())
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
      return utf8.decode(cipher.process(base64Decode(encryptedKey)));
    } catch (e) {
      if (e is EncryptionException) rethrow;
      throw EncryptionException('Failed to decrypt chat key: $e');
    }
  }

  Future<String> encrypt(String plainText, String chatId) async {
    // Convenience method for secret text messages. It loads the chat key from
    // secure storage and encrypts the string with AES-GCM.
    final keyBase64 = await _requiredChatKey(chatId);
    return encryptStringWithKey(plainText, keyBase64);
  }

  Future<String> decrypt(String encryptedText, String chatId) async {
    // Convenience method for secret text messages received from Supabase.
    final keyBase64 = await _requiredChatKey(chatId);
    return decryptStringWithKey(encryptedText, keyBase64);
  }

  String encryptStringWithKey(String plainText, String keyBase64) {
    final encrypted = encryptBytesWithKey(
      Uint8List.fromList(utf8.encode(plainText)),
      keyBase64,
    );
    return encrypted;
  }

  String decryptStringWithKey(String encryptedText, String keyBase64) {
    final decrypted = decryptBytesWithKey(encryptedText, keyBase64);
    return utf8.decode(decrypted);
  }

  Future<String> encryptBytesForChat(
      Uint8List plainBytes, String chatId) async {
    final keyBase64 = await _requiredChatKey(chatId);
    return encryptBytesWithKey(plainBytes, keyBase64);
  }

  Future<Uint8List> decryptBytesForChat(
    String encryptedPayload,
    String chatId,
  ) async {
    final keyBase64 = await _requiredChatKey(chatId);
    return decryptBytesWithKey(encryptedPayload, keyBase64);
  }

  String encryptBytesWithKey(Uint8List plainBytes, String keyBase64) {
    try {
      // AES-GCM gives confidentiality and integrity. If ciphertext is changed,
      // decryption fails instead of returning modified plaintext.
      //
      // A fresh nonce is required for every payload encrypted with the same key.
      final nonce = _randomBytes(12);
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(
            KeyParameter(base64Decode(keyBase64)),
            128,
            nonce,
            Uint8List(0),
          ),
        );
      final cipherBytes = cipher.process(plainBytes);
      // The version prefix lets the app change encryption formats later without
      // breaking old messages.
      return 'v2:${base64Encode(nonce)}:${base64Encode(cipherBytes)}';
    } catch (e) {
      throw EncryptionException('Encryption failed: $e');
    }
  }

  Uint8List decryptBytesWithKey(String encryptedPayload, String keyBase64) {
    try {
      // Payload format: version, nonce, ciphertext plus authentication tag.
      // For example: v2:<nonceBase64>:<ciphertextBase64>
      final parts = encryptedPayload.split(':');
      if (parts.length != 3 || parts.first != 'v2') {
        throw const EncryptionException(
            'Unsupported encrypted payload format.');
      }
      final nonce = base64Decode(parts[1]);
      final cipherBytes = base64Decode(parts[2]);
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(base64Decode(keyBase64)),
            128,
            nonce,
            Uint8List(0),
          ),
        );
      return cipher.process(cipherBytes);
    } catch (e) {
      if (e is EncryptionException) rethrow;
      throw EncryptionException('Decryption failed: $e');
    }
  }

  String encryptWithKey(String plainText, String keyBase64, String _) {
    return encryptStringWithKey(plainText, keyBase64);
  }

  String decryptWithKey(String encryptedText, String keyBase64, String _) {
    return decryptStringWithKey(encryptedText, keyBase64);
  }

  Future<String> _requiredChatKey(String chatId) async {
    // Secret messages cannot be encrypted or decrypted without the chat key.
    // Throwing here makes key problems visible to the provider/UI.
    final keyBase64 = await getChatKey(chatId);
    if (keyBase64 == null) {
      throw EncryptionException('Encryption key not found for chat $chatId');
    }
    return keyBase64;
  }

  SecureRandom _secureRandom() {
    // PointyCastle RSA generation needs a SecureRandom. It is seeded with bytes
    // from Dart's Random.secure().
    final secureRandom = FortunaRandom();
    secureRandom.seed(KeyParameter(_randomBytes(32)));
    return secureRandom;
  }

  Uint8List _randomBytes(int length) {
    // Used for AES keys, nonces, and RSA random seeding.
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  String _randomBase64(int length) => base64Encode(_randomBytes(length));

  RSAPublicKey _decodePublicKey(String publicKeyJson) {
    final json = jsonDecode(publicKeyJson) as Map<String, dynamic>;
    return RSAPublicKey(
      _base64ToBigInt(json['n'] as String),
      _base64ToBigInt(json['e'] as String),
    );
  }

  RSAPrivateKey _decodePrivateKey(String privateKeyJson) {
    final json = jsonDecode(privateKeyJson) as Map<String, dynamic>;
    return RSAPrivateKey(
      _base64ToBigInt(json['n'] as String),
      _base64ToBigInt(json['d'] as String),
      _base64ToBigInt(json['p'] as String),
      _base64ToBigInt(json['q'] as String),
    );
  }

  String _bigIntToBase64(BigInt value) => base64Encode(_bigIntToBytes(value));

  BigInt _base64ToBigInt(String value) => _bytesToBigInt(base64Decode(value));

  Uint8List _bigIntToBytes(BigInt value) {
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }
}
