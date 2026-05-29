import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:secure_messenger/core/constants/app_constants.dart';
import 'package:secure_messenger/core/errors/app_exception.dart';
import 'package:secure_messenger/data/models/chat_model.dart';
import 'package:secure_messenger/data/models/message_model.dart';
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
  bool _isSending = false;
  String? _errorMessage;
  Map<String, bool> _typingUsers = {};
  Timer? _typingTimer;
  Timer? _readSyncTimer;
  Timer? _readFollowUpTimer;
  bool _markingRead = false;
  bool _lastTypingState = false;

  List<MessageModel> get messages => _messages;
  bool get isSending => _isSending;
  String? get errorMessage => _errorMessage;
  Map<String, bool> get typingUsers => _typingUsers;

  StreamSubscription? _messagesSub;
  StreamSubscription? _typingSub;

  MessageProvider(this._chatRepository);

  void startListening(String chatId, String currentUid) {
    _messagesSub?.cancel();
    _typingSub?.cancel();

    _messagesSub = _chatRepository.watchMessages(chatId).listen(
      (messages) {
        final remoteIds = messages.map((message) => message.id).toSet();
        _pendingMessages.removeWhere((id, _) => remoteIds.contains(id));
        _messages = [
          ...messages,
          ..._pendingMessages.values,
        ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        _markIncomingMessagesAsRead(chatId, currentUid, messages);
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
    _syncReadState(chatId, currentUid);
  }

  void stopListening(String chatId, String currentUid) {
    _messagesSub?.cancel();
    _typingSub?.cancel();
    _typingTimer?.cancel();
    _readSyncTimer?.cancel();
    _readFollowUpTimer?.cancel();
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
    final message = MessageModel(
      id: _uuid.v4(),
      senderId: senderId,
      content: trimmed,
      type: AppConstants.textMessage,
      status: AppConstants.statusSent,
      timestamp: DateTime.now(),
    );
    _pendingMessages[message.id] = message;
    _messages = [..._messages, message]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _isSending = true;
    notifyListeners();
    try {
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
    _isSending = true;
    notifyListeners();
    try {
      final url = await _chatRepository.uploadMedia(
        chatId: chatId,
        file: file,
        type: type,
      );
      await _chatRepository.sendMessage(
        chatId: chatId,
        senderId: senderId,
        content: type == AppConstants.imageMessage
            ? 'Photo'
            : type == AppConstants.videoMessage
                ? 'Video'
                : 'Audio',
        type: type,
        mediaUrl: url,
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
    super.dispose();
  }
}
