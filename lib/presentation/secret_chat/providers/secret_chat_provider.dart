import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:secure_messenger/core/constants/app_constants.dart';
import 'package:secure_messenger/core/errors/app_exception.dart';
import 'package:secure_messenger/core/services/encryption_service.dart';
import 'package:secure_messenger/data/models/message_model.dart';
import 'package:secure_messenger/data/repositories/chat_repository.dart';

class SecretMessageProvider extends ChangeNotifier {
  final ChatRepository _chatRepository;
  final EncryptionService _encryptionService;

  List<MessageModel> _messages = [];
  bool _isSending = false;
  String? _errorMessage;
  Map<String, bool> _typingUsers = {};
  Timer? _typingTimer;
  bool _keysReady = false;

  List<MessageModel> get messages => _messages;
  bool get isSending => _isSending;
  String? get errorMessage => _errorMessage;
  Map<String, bool> get typingUsers => _typingUsers;
  bool get keysReady => _keysReady;

  StreamSubscription? _messagesSub;
  StreamSubscription? _typingSub;

  SecretMessageProvider(this._chatRepository, this._encryptionService);

  Future<void> initChat(String chatId, String currentUid) async {
    try {
      await _prepareSecretChatKey(chatId, currentUid);
    } on AppException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return;
    }
    notifyListeners();

    _messagesSub?.cancel();
    _typingSub?.cancel();

    _messagesSub = _chatRepository.watchMessages(chatId).listen(
      (rawMessages) async {
        final decrypted = <MessageModel>[];
        for (final msg in rawMessages) {
          if (msg.isDeleted) {
            decrypted.add(msg);
            continue;
          }
          if (msg.type == AppConstants.textMessage) {
            try {
              final plain =
                  await _encryptionService.decrypt(msg.content, chatId);
              decrypted.add(msg.copyWith(content: plain));
            } catch (_) {
              decrypted.add(msg.copyWith(content: '🔒 [Encrypted message]'));
            }
          } else {
            decrypted.add(msg);
          }
        }
        _messages = decrypted;
        notifyListeners();
      },
      onError: (e) {
        _errorMessage = 'Failed to load messages: $e';
        notifyListeners();
      },
    );

    _typingSub = _chatRepository.watchTyping(chatId).listen(
      (typing) {
        _typingUsers = Map.from(typing)..remove(currentUid);
        notifyListeners();
      },
    );

    _chatRepository
        .markMessagesDelivered(chatId, currentUid)
        .catchError((_) {});
    _chatRepository.markMessagesAsRead(chatId, currentUid).catchError((_) {});
  }

  void stopListening(String chatId, String currentUid) {
    _messagesSub?.cancel();
    _typingSub?.cancel();
    _chatRepository.setTyping(chatId, currentUid, false).catchError((_) {});
  }

  Future<void> sendTextMessage({
    required String chatId,
    required String senderId,
    required String content,
  }) async {
    if (content.trim().isEmpty) return;
    _isSending = true;
    notifyListeners();
    try {
      final encrypted =
          await _encryptionService.encrypt(content.trim(), chatId);
      await _chatRepository.sendMessage(
        chatId: chatId,
        senderId: senderId,
        content: encrypted,
        type: AppConstants.textMessage,
      );
    } on AppException catch (e) {
      _errorMessage = e.message;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  Future<void> sendMediaMessage({
    required String chatId,
    required String senderId,
    required File file,
    required String type,
  }) async {
    _isSending = true;
    notifyListeners();
    try {
      final encryptedPayload = await _encryptionService.encryptBytesForChat(
        await file.readAsBytes(),
        chatId,
      );
      final encryptedUrl = await _chatRepository.uploadEncryptedMediaBytes(
        chatId: chatId,
        encryptedBytes: utf8.encode(encryptedPayload),
        type: type,
      );
      final label = type == AppConstants.imageMessage
          ? 'Photo'
          : type == AppConstants.videoMessage
              ? 'Video'
              : 'Audio';
      final encrypted = await _encryptionService.encrypt(label, chatId);
      await _chatRepository.sendMessage(
        chatId: chatId,
        senderId: senderId,
        content: encrypted,
        type: type,
        mediaUrl: encryptedUrl,
      );
    } on AppException catch (e) {
      _errorMessage = e.message;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  Future<void> editMessage({
    required String chatId,
    required String messageId,
    required String newContent,
  }) async {
    try {
      final encrypted = await _encryptionService.encrypt(newContent, chatId);
      await _chatRepository.editMessage(
        chatId: chatId,
        messageId: messageId,
        newContent: encrypted,
      );
    } on AppException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
    }
  }

  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) async {
    try {
      await _chatRepository.deleteMessage(
        chatId: chatId,
        messageId: messageId,
      );
    } on AppException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
    }
  }

  void onTyping(String chatId, String uid, bool isTyping) {
    _typingTimer?.cancel();
    _chatRepository.setTyping(chatId, uid, isTyping).catchError((_) {});
    if (isTyping) {
      _typingTimer = Timer(AppConstants.typingTimeout, () {
        _chatRepository.setTyping(chatId, uid, false).catchError((_) {});
      });
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _prepareSecretChatKey(String chatId, String currentUid) async {
    _keysReady = await _encryptionService.hasKeysForChat(chatId);
    if (_keysReady) return;

    final chat = await _chatRepository.getChat(chatId);
    final encryptedForCurrentUser = chat.encryptedKeys[currentUid];
    if (encryptedForCurrentUser != null) {
      final chatKey = await _encryptionService.decryptChatKeyForCurrentDevice(
        encryptedForCurrentUser,
      );
      await _encryptionService.storeChatKey(chatId, chatKey);
      _keysReady = true;
      return;
    }

    if (chat.encryptedKeys.isNotEmpty) {
      throw const EncryptionException(
        'This device does not have access to the secret chat key.',
      );
    }

    final chatKey = await _encryptionService.generateAndStoreChatKey(chatId);
    final publicKeys = await _chatRepository.getParticipantPublicKeys(
      chat.participantIds,
    );
    final encryptedKeys = <String, String>{};
    for (final entry in publicKeys.entries) {
      encryptedKeys[entry.key] = await _encryptionService.encryptChatKeyForUser(
        chatKey,
        entry.value,
      );
    }
    await _chatRepository.saveEncryptedChatKeys(
      chatId: chatId,
      encryptedKeys: encryptedKeys,
    );
    _keysReady = true;
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _typingSub?.cancel();
    _typingTimer?.cancel();
    super.dispose();
  }
}
