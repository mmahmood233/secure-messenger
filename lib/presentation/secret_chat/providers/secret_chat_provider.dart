// Secret chat provider.
//
// This is the state manager for one open encrypted conversation. The screen
// talks to this provider, and the provider coordinates:
// - Preparing the secret chat key.
// - Watching Supabase realtime message/typing streams.
// - Decrypting messages before the UI sees them.
// - Encrypting text/media before saving to Supabase.
// - Updating read receipts and typing indicators.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:secure_messenger/core/constants/app_constants.dart';
import 'package:secure_messenger/core/errors/app_exception.dart';
import 'package:secure_messenger/core/services/encryption_service.dart';
import 'package:secure_messenger/data/models/message_model.dart';
import 'package:secure_messenger/data/models/pending_media_upload.dart';
import 'package:secure_messenger/data/repositories/chat_repository.dart';

class SecretMessageProvider extends ChangeNotifier {
  static const _uuid = Uuid();

  final ChatRepository _chatRepository;
  final EncryptionService _encryptionService;

  List<MessageModel> _messages = [];
  final Map<String, MessageModel> _pendingMessages = {};
  final List<PendingMediaUpload> _pendingMediaUploads = [];
  bool _isSending = false;
  String? _errorMessage;
  Map<String, bool> _typingUsers = {};
  Timer? _typingTimer;
  Timer? _readSyncTimer;
  Timer? _readFollowUpTimer;
  Timer? _reconnectTimer;
  bool _keysReady = false;
  bool _markingRead = false;
  bool _lastTypingState = false;
  bool _isListening = false;
  String? _activeChatId;
  String? _activeUid;

  List<MessageModel> get messages => _messages;
  List<PendingMediaUpload> get pendingMediaUploads =>
      List.unmodifiable(_pendingMediaUploads);
  bool get isSending => _isSending;
  String? get errorMessage => _errorMessage;
  Map<String, bool> get typingUsers => _typingUsers;
  bool get keysReady => _keysReady;

  StreamSubscription? _messagesSub;
  StreamSubscription? _typingSub;

  SecretMessageProvider(this._chatRepository, this._encryptionService);

  Future<void> initChat(String chatId, String currentUid) async {
    try {
      // Secret chats cannot show or send readable content until this device has
      // the AES chat key. This may come from local secure storage, or it may be
      // unwrapped from the encrypted_keys map stored in Supabase.
      await _prepareSecretChatKey(chatId, currentUid);
    } on AppException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return;
    }
    notifyListeners();

    _isListening = true;
    _activeChatId = chatId;
    _activeUid = currentUid;
    _reconnectTimer?.cancel();
    _messagesSub?.cancel();
    _typingSub?.cancel();

    // After the key is ready, start realtime streams and do an initial fetch.
    _subscribeToMessages(chatId, currentUid);
    _subscribeToTyping(chatId, currentUid);

    _refreshMessages(chatId, currentUid);
    _chatRepository
        .markMessagesDelivered(chatId, currentUid)
        .catchError((_) {});
    _syncReadState(chatId, currentUid);
  }

  void _subscribeToMessages(String chatId, String currentUid) {
    _messagesSub?.cancel();
    _messagesSub = _chatRepository.watchMessages(chatId).listen(
      (rawMessages) async {
        // rawMessages still contain ciphertext. _applyRawMessages decrypts
        // text messages and merges any local pending messages.
        await _applyRawMessages(rawMessages, chatId, currentUid);
      },
      onError: (e) {
        _refreshMessages(chatId, currentUid);
        _scheduleReconnect();
      },
    );
  }

  void _subscribeToTyping(String chatId, String currentUid) {
    _typingSub?.cancel();
    _typingSub = _chatRepository.watchTyping(chatId).listen(
      (typing) {
        // Remove the current user from the typing map because the UI should only
        // show when the other participant is typing.
        _typingUsers = Map.from(typing)..remove(currentUid);
        notifyListeners();
      },
      onError: (_) => _scheduleReconnect(),
    );
  }

  Future<void> _refreshMessages(String chatId, String currentUid) async {
    try {
      // Used at startup and as a fallback if the realtime stream has a problem.
      final messages = await _chatRepository.getMessages(chatId);
      await _applyRawMessages(messages, chatId, currentUid);
    } catch (_) {}
  }

  Future<void> _applyRawMessages(
    List<MessageModel> rawMessages,
    String chatId,
    String currentUid,
  ) async {
    // Convert database rows into UI-ready messages. The database content for
    // secret text is encrypted, but the screen should receive plaintext.
    final decrypted = <MessageModel>[];
    for (final msg in rawMessages) {
      if (msg.isDeleted) {
        decrypted.add(msg);
        continue;
      }
      if (msg.type == AppConstants.textMessage) {
        try {
          // Supabase stores ciphertext; decrypt it locally before showing it.
          // If the key is wrong or missing, AES-GCM authentication fails.
          final plain = await _encryptionService.decrypt(msg.content, chatId);
          decrypted.add(msg.copyWith(content: plain));
        } catch (_) {
          decrypted.add(msg.copyWith(content: '🔒 [Encrypted message]'));
        }
      } else {
        decrypted.add(msg);
      }
    }
    final remoteIds = rawMessages.map((message) => message.id).toSet();
    // Once Supabase confirms a pending local message, remove the local pending
    // copy to avoid showing duplicates.
    _pendingMessages.removeWhere((id, _) => remoteIds.contains(id));
    _pendingMediaUploads.removeWhere((upload) => remoteIds.contains(upload.id));
    _messages = [
      ...decrypted,
      ..._pendingMessages.values,
    ]..sort(_compareMessages);
    _markIncomingMessagesAsRead(chatId, currentUid, rawMessages);
    notifyListeners();
  }

  int _compareMessages(MessageModel a, MessageModel b) {
    final aPending = _pendingMessages.containsKey(a.id);
    final bPending = _pendingMessages.containsKey(b.id);
    if (aPending != bPending) return aPending ? 1 : -1;
    return a.timestamp.compareTo(b.timestamp);
  }

  void _scheduleReconnect() {
    if (!_isListening || _reconnectTimer?.isActive == true) return;
    // If realtime fails, retry once after a short delay and refresh from the
    // database so the chat can recover without closing the screen.
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      final chatId = _activeChatId;
      final uid = _activeUid;
      if (!_isListening || chatId == null || uid == null) return;
      _subscribeToMessages(chatId, uid);
      _subscribeToTyping(chatId, uid);
      _refreshMessages(chatId, uid);
    });
  }

  void stopListening(String chatId, String currentUid) {
    // Called when leaving the screen. It stops streams, clears typing state, and
    // does one last read sync for incoming messages.
    _isListening = false;
    _activeChatId = null;
    _activeUid = null;
    _messagesSub?.cancel();
    _typingSub?.cancel();
    _typingTimer?.cancel();
    _readSyncTimer?.cancel();
    _readFollowUpTimer?.cancel();
    _reconnectTimer?.cancel();
    _lastTypingState = false;
    _chatRepository.setTyping(chatId, currentUid, false).catchError((_) {});
    _chatRepository.markMessagesAsRead(chatId, currentUid).catchError((_) {});
  }

  Future<void> sendTextMessage({
    required String chatId,
    required String senderId,
    required String content,
  }) async {
    if (content.trim().isEmpty) return;
    final trimmed = content.trim();
    // Keep plaintext only in local UI state so the sender immediately sees what
    // they typed. The database receives encrypted content below.
    final message = MessageModel(
      id: _uuid.v4(),
      senderId: senderId,
      content: trimmed,
      type: AppConstants.textMessage,
      status: AppConstants.statusSent,
      timestamp: DateTime.now(),
    );
    _pendingMessages[message.id] = message;
    _messages = [..._messages, message]..sort(_compareMessages);
    _isSending = true;
    notifyListeners();
    try {
      // Encrypt before sending so the backend never sees the secret text.
      // ChatRepository only receives ciphertext for this message.
      final encrypted = await _encryptionService.encrypt(trimmed, chatId);
      await _chatRepository.sendMessage(
        chatId: chatId,
        senderId: senderId,
        messageId: message.id,
        timestamp: message.timestamp,
        content: encrypted,
        type: AppConstants.textMessage,
      );
    } on AppException catch (e) {
      _pendingMessages.remove(message.id);
      _messages = _messages.where((msg) => msg.id != message.id).toList();
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
    // Secret media is encrypted locally first, then uploaded as encrypted bytes.
    // The original file bytes are never uploaded to Supabase in secret chats.
    final upload = PendingMediaUpload(
      id: _uuid.v4(),
      file: file,
      type: type,
      createdAt: DateTime.now(),
    );
    _pendingMediaUploads.add(upload);
    _isSending = true;
    notifyListeners();
    try {
      final encryptedPayload = await _encryptionService.encryptBytesForChat(
        await file.readAsBytes(),
        chatId,
      );
      // Upload the encrypted payload. The saved storage object is opaque bytes,
      // not a readable image/video/audio file.
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
      // Even the media label stored in messages.content is encrypted so the
      // backend cannot read message previews for secret chats.
      final encrypted = await _encryptionService.encrypt(label, chatId);
      final sentMessage = await _chatRepository.sendMessage(
        chatId: chatId,
        senderId: senderId,
        messageId: upload.id,
        timestamp: upload.createdAt,
        content: encrypted,
        type: type,
        mediaUrl: encryptedUrl,
      );
      _pendingMediaUploads.removeWhere((item) => item.id == upload.id);
      if (!_messages.any((message) => message.id == sentMessage.id)) {
        _messages = [..._messages, sentMessage]..sort(_compareMessages);
      }
      await _refreshMessages(chatId, senderId);
    } on AppException catch (e) {
      _pendingMediaUploads.removeWhere((item) => item.id == upload.id);
      _errorMessage = e.message;
    } catch (_) {
      _pendingMediaUploads.removeWhere((item) => item.id == upload.id);
      _errorMessage = 'Failed to send media. Please try again.';
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
      // Editing replaces the stored ciphertext with new ciphertext for the new
      // plaintext message.
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
    // Typing state is not encrypted; it is only a small presence signal.
    // The timer turns it off automatically if the user stops typing.
    if (_lastTypingState != isTyping) {
      _lastTypingState = isTyping;
      _chatRepository.setTyping(chatId, uid, isTyping).catchError((_) {});
    }
    if (isTyping) {
      _typingTimer = Timer(AppConstants.typingTimeout, () {
        _lastTypingState = false;
        _chatRepository.setTyping(chatId, uid, false).catchError((_) {});
      });
    }
  }

  void _markIncomingMessagesAsRead(
    String chatId,
    String currentUid,
    List<MessageModel> messages,
  ) {
    // Read receipts are based on metadata, not message plaintext. Only incoming
    // messages should be marked read by this user.
    final hasUnreadIncoming = messages.any(
      (message) =>
          message.senderId != currentUid &&
          message.status != AppConstants.statusRead,
    );
    if (!hasUnreadIncoming) return;

    _scheduleReadSync(chatId, currentUid);
  }

  void _scheduleReadSync(String chatId, String currentUid) {
    _readSyncTimer?.cancel();
    _readFollowUpTimer?.cancel();
    _readSyncTimer = Timer(const Duration(milliseconds: 80), () {
      _syncReadState(chatId, currentUid);
    });
    _readFollowUpTimer = Timer(const Duration(milliseconds: 900), () {
      _syncReadState(chatId, currentUid);
    });
  }

  void _syncReadState(String chatId, String currentUid) {
    if (_markingRead) return;
    // Prevent overlapping read-receipt writes while realtime updates are coming
    // in quickly.
    _markingRead = true;
    _chatRepository.markMessagesAsRead(chatId, currentUid).catchError((_) {
      return;
    }).whenComplete(() {
      _markingRead = false;
    });
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _prepareSecretChatKey(String chatId, String currentUid) async {
    // Step 1: try local secure storage. If the key is there, this device has
    // already joined the secret chat and can decrypt immediately.
    _keysReady = await _encryptionService.hasKeysForChat(chatId);
    if (_keysReady) return;

    final chat = await _chatRepository.getChat(chatId);
    final encryptedForCurrentUser = chat.encryptedKeys[currentUid];
    if (encryptedForCurrentUser != null) {
      // Step 2: the chat already has encrypted keys. Use the copy encrypted for
      // this user, unwrap it with this device's RSA private key, then cache the
      // raw AES chat key locally.
      final chatKey = await _encryptionService.decryptChatKeyForCurrentDevice(
        encryptedForCurrentUser,
      );
      await _encryptionService.storeChatKey(chatId, chatKey);
      _keysReady = true;
      return;
    }

    if (chat.encryptedKeys.isNotEmpty) {
      // The chat has keys, but not for this user/device. Without a matching
      // encrypted key, this device cannot decrypt the conversation.
      throw const EncryptionException(
        'This device does not have access to the secret chat key.',
      );
    }

    // Step 3: no one has initialized keys yet. Create a new AES chat key, then
    // wrap the same key once per participant using each public RSA key.
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
    _readSyncTimer?.cancel();
    _readFollowUpTimer?.cancel();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
