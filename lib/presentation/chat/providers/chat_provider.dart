// Normal chat providers.
//
// There are two state managers in this file:
// - ChatProvider watches the chat lists shown on the Home screen.
// - MessageProvider manages one currently open normal chat.
//
// Normal chat messages are not end-to-end encrypted. They are protected by
// Supabase authentication/RLS, but the message content is stored as plaintext.
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:secure_messenger/core/constants/app_constants.dart';
import 'package:secure_messenger/core/errors/app_exception.dart';
import 'package:secure_messenger/data/models/chat_model.dart';
import 'package:secure_messenger/data/models/message_model.dart';
import 'package:secure_messenger/data/models/pending_media_upload.dart';
import 'package:secure_messenger/data/repositories/chat_repository.dart';

enum ChatListStatus { idle, loading, success, error }

class ChatProvider extends ChangeNotifier {
  final ChatRepository _chatRepository;

  ChatListStatus _status = ChatListStatus.idle;
  String? _errorMessage;
  List<ChatModel> _chats = [];
  List<ChatModel> _secretChats = [];

  ChatListStatus get status => _status;
  String? get errorMessage => _errorMessage;
  List<ChatModel> get chats => _chats;
  List<ChatModel> get secretChats => _secretChats;

  StreamSubscription? _chatsSub;
  StreamSubscription? _secretChatsSub;

  ChatProvider(this._chatRepository);

  void startListening(String uid) {
    // Watch normal and secret chat lists separately so the Home tabs can render
    // each list independently and show different empty states/icons.
    _chatsSub?.cancel();
    _secretChatsSub?.cancel();

    _chatsSub = _chatRepository.watchChats(uid).listen(
      (chats) {
        _chats = chats;
        _status = ChatListStatus.success;
        notifyListeners();
      },
      onError: (e) => _setError('Failed to load chats: $e'),
    );

    _secretChatsSub = _chatRepository.watchSecretChats(uid).listen(
      (chats) {
        _secretChats = chats;
        notifyListeners();
      },
      onError: (e) => _setError('Failed to load secret chats: $e'),
    );
  }

  void stopListening() {
    _chatsSub?.cancel();
    _secretChatsSub?.cancel();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setError(String message) {
    _status = ChatListStatus.error;
    _errorMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}

class MessageProvider extends ChangeNotifier {
  static const _uuid = Uuid();

  final ChatRepository _chatRepository;

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

  StreamSubscription? _messagesSub;
  StreamSubscription? _typingSub;

  MessageProvider(this._chatRepository);

  void startListening(String chatId, String currentUid) {
    // Start realtime message and typing subscriptions for the active chat. This
    // method is called when ChatScreen opens.
    _isListening = true;
    _activeChatId = chatId;
    _activeUid = currentUid;
    _reconnectTimer?.cancel();
    _messagesSub?.cancel();
    _typingSub?.cancel();

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
      (messages) {
        // Normal messages already contain display-ready content because they are
        // not encrypted.
        _applyMessages(messages, chatId, currentUid);
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
        // Remove the current user from the map so the UI only shows when the
        // other participant is typing.
        _typingUsers = Map.from(typing)..remove(currentUid);
        notifyListeners();
      },
      onError: (_) => _scheduleReconnect(),
    );
  }

  Future<void> _refreshMessages(String chatId, String currentUid) async {
    try {
      // Initial load and fallback if realtime temporarily fails.
      final messages = await _chatRepository.getMessages(chatId);
      _applyMessages(messages, chatId, currentUid);
    } catch (_) {}
  }

  void _applyMessages(
    List<MessageModel> messages,
    String chatId,
    String currentUid,
  ) {
    // Merge confirmed Supabase messages with any local pending messages. When a
    // pending id appears in Supabase, the local pending copy is removed.
    final remoteIds = messages.map((message) => message.id).toSet();
    _pendingMessages.removeWhere((id, _) => remoteIds.contains(id));
    _pendingMediaUploads.removeWhere((upload) => remoteIds.contains(upload.id));
    _messages = [
      ...messages,
      ..._pendingMessages.values,
    ]..sort(_compareMessages);
    _markIncomingMessagesAsRead(chatId, currentUid, messages);
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
    // Reconnect once after a short delay and refresh from the database.
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
    // Called when the chat screen closes. It clears subscriptions and makes sure
    // typing is turned off for this user.
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
    // Add a local pending message immediately so the UI feels responsive.
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
      // Normal chats store plaintext content. Secret chats use a different
      // provider that encrypts before calling the repository.
      await _chatRepository.sendMessage(
        chatId: chatId,
        senderId: senderId,
        messageId: message.id,
        timestamp: message.timestamp,
        content: trimmed,
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
    // Show a pending upload bubble while the file uploads to Supabase Storage.
    // After upload, the message row stores the storage path in media_url.
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
      final url = await _chatRepository.uploadMedia(
        chatId: chatId,
        file: file,
        type: type,
      );
      final sentMessage = await _chatRepository.sendMessage(
        chatId: chatId,
        senderId: senderId,
        messageId: upload.id,
        timestamp: upload.createdAt,
        content: type == AppConstants.imageMessage
            ? 'Photo'
            : type == AppConstants.videoMessage
                ? 'Video'
                : 'Audio',
        type: type,
        mediaUrl: url,
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
      // The repository updates the existing row, so all participants see the new
      // content through the realtime stream.
      await _chatRepository.editMessage(
        chatId: chatId,
        messageId: messageId,
        newContent: newContent,
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
      // Delete is a soft delete. The row remains, but the UI shows a deleted
      // message state for everyone.
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
    // Avoid sending duplicate typing writes for the same state.
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
    // Only mark incoming messages as read. A user's own messages should keep
    // their status until the other participant opens the chat.
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
    // Prevent duplicate read-receipt writes when realtime emits several message
    // updates close together.
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
