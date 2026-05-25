import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_messenger/core/services/encryption_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('encrypts and decrypts chat text with AES-GCM payloads', () async {
    const storage = FlutterSecureStorage();
    final service = EncryptionService(storage);
    await service.generateAndStoreChatKey('chat-1');

    final encrypted = await service.encrypt('secret hello', 'chat-1');
    final decrypted = await service.decrypt(encrypted, 'chat-1');

    expect(encrypted, isNot('secret hello'));
    expect(encrypted.startsWith('v2:'), isTrue);
    expect(decrypted, 'secret hello');
  });

  test('wraps a chat key to the local identity public key', () async {
    const storage = FlutterSecureStorage();
    final service = EncryptionService(storage);
    final publicKey = await service.ensureIdentityKeyPair();
    final chatKey = await service.generateAndStoreChatKey('chat-2');

    final wrapped = await service.encryptChatKeyForUser(chatKey, publicKey);
    final unwrapped = await service.decryptChatKeyForCurrentDevice(wrapped);

    expect(wrapped, isNot(chatKey));
    expect(unwrapped, chatKey);
  });
}
