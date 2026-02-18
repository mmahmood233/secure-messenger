import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:secure_messenger/core/constants/app_constants.dart';
import 'package:secure_messenger/core/errors/app_exception.dart';

class EncryptionService {
  final FlutterSecureStorage _secureStorage;

  EncryptionService(this._secureStorage);

  Future<Map<String, String>> generateKeyPair(String chatId) async {
    try {
      final key = Key.fromSecureRandom(32);
      final iv = IV.fromSecureRandom(16);

      final keyBase64 = base64Encode(key.bytes);
      final ivBase64 = base64Encode(iv.bytes);

      await _secureStorage.write(
        key: '${AppConstants.secretKeyPrefix}$chatId',
        value: keyBase64,
      );
      await _secureStorage.write(
        key: '${AppConstants.ivPrefix}$chatId',
        value: ivBase64,
      );

      return {'key': keyBase64, 'iv': ivBase64};
    } catch (e) {
      throw EncryptionException('Failed to generate encryption keys: $e');
    }
  }

  Future<void> storeSharedKey(
      String chatId, String keyBase64, String ivBase64) async {
    await _secureStorage.write(
      key: '${AppConstants.secretKeyPrefix}$chatId',
      value: keyBase64,
    );
    await _secureStorage.write(
      key: '${AppConstants.ivPrefix}$chatId',
      value: ivBase64,
    );
  }

  Future<String> encrypt(String plainText, String chatId) async {
    try {
      final keyBase64 = await _secureStorage.read(
        key: '${AppConstants.secretKeyPrefix}$chatId',
      );
      final ivBase64 = await _secureStorage.read(
        key: '${AppConstants.ivPrefix}$chatId',
      );

      if (keyBase64 == null || ivBase64 == null) {
        throw EncryptionException('Encryption keys not found for chat $chatId');
      }

      final key = Key(base64Decode(keyBase64));
      final iv = IV(base64Decode(ivBase64));
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));

      final encrypted = encrypter.encrypt(plainText, iv: iv);
      return encrypted.base64;
    } catch (e) {
      if (e is EncryptionException) rethrow;
      throw EncryptionException('Encryption failed: $e');
    }
  }

  Future<String> decrypt(String encryptedText, String chatId) async {
    try {
      final keyBase64 = await _secureStorage.read(
        key: '${AppConstants.secretKeyPrefix}$chatId',
      );
      final ivBase64 = await _secureStorage.read(
        key: '${AppConstants.ivPrefix}$chatId',
      );

      if (keyBase64 == null || ivBase64 == null) {
        throw EncryptionException('Decryption keys not found for chat $chatId');
      }

      final key = Key(base64Decode(keyBase64));
      final iv = IV(base64Decode(ivBase64));
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));

      final decrypted = encrypter.decrypt64(encryptedText, iv: iv);
      return decrypted;
    } catch (e) {
      if (e is EncryptionException) rethrow;
      throw EncryptionException('Decryption failed: $e');
    }
  }

  Future<bool> hasKeysForChat(String chatId) async {
    final key = await _secureStorage.read(
      key: '${AppConstants.secretKeyPrefix}$chatId',
    );
    return key != null;
  }

  Future<Map<String, String>?> getKeysForChat(String chatId) async {
    final keyBase64 = await _secureStorage.read(
      key: '${AppConstants.secretKeyPrefix}$chatId',
    );
    final ivBase64 = await _secureStorage.read(
      key: '${AppConstants.ivPrefix}$chatId',
    );
    if (keyBase64 == null || ivBase64 == null) return null;
    return {'key': keyBase64, 'iv': ivBase64};
  }

  String encryptWithKey(String plainText, String keyBase64, String ivBase64) {
    try {
      final keyBytes = base64Decode(keyBase64);
      final ivBytes = base64Decode(ivBase64);
      final key = Key(Uint8List.fromList(keyBytes));
      final iv = IV(Uint8List.fromList(ivBytes));
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      return encrypter.encrypt(plainText, iv: iv).base64;
    } catch (e) {
      throw EncryptionException('Encryption failed: $e');
    }
  }

  String decryptWithKey(
      String encryptedText, String keyBase64, String ivBase64) {
    try {
      final keyBytes = base64Decode(keyBase64);
      final ivBytes = base64Decode(ivBase64);
      final key = Key(Uint8List.fromList(keyBytes));
      final iv = IV(Uint8List.fromList(ivBytes));
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      return encrypter.decrypt64(encryptedText, iv: iv);
    } catch (e) {
      throw EncryptionException('Decryption failed: $e');
    }
  }
}
