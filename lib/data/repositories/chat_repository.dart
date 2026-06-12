// Chat repository.
//
// This file is the single backend gateway for chats and messages. Providers call
// this repository, and this repository talks to Supabase tables, realtime
// streams, RPC functions, and storage buckets.
//
// Important split:
// - Normal chat providers pass plaintext content here.
// - Secret chat providers encrypt content first, then pass ciphertext here.
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' hide StorageException;
import 'package:uuid/uuid.dart';
import 'package:secure_messenger/core/constants/app_constants.dart';
import 'package:secure_messenger/core/errors/app_exception.dart';
import 'package:secure_messenger/data/models/chat_model.dart';
import 'package:secure_messenger/data/models/message_model.dart';

class ChatRepository {
  static const _chatMediaBucket = 'chat-media';

  final SupabaseClient _client;
  final Uuid _uuid;

  ChatRepository(this._client) : _uuid = const Uuid();

  Stream<List<ChatModel>> watchChats(String uid) {
    // Normal chat list for the Home screen.
    return _watchChats(uid, isSecret: false);
  }

  Stream<List<ChatModel>> watchSecretChats(String uid) {
    // Secret chat list for the Home screen.
    return _watchChats(uid, isSecret: true);
  }

  Stream<List<ChatModel>> _watchChats(String uid, {required bool isSecret}) {
    // Supabase streams all chat rows allowed by RLS, then the app filters the
    // current user's normal/secret chats and sorts newest first.
    return _client.from('chats').stream(primaryKey: ['id']).map((rows) {
      final chats = rows
          .map(ChatModel.fromSupabase)
          .where((chat) =>
              chat.isSecret == isSecret && chat.participantIds.contains(uid))
          .toList();
      chats.sort((a, b) {
        final at = a.lastMessageTime ?? a.createdAt;
        final bt = b.lastMessageTime ?? b.createdAt;
        return bt.compareTo(at);
      });
      return chats;
    });
  }

  Future<ChatModel> getChat(String chatId) async {
    try {
      final data =
          await _client.from('chats').select().eq('id', chatId).maybeSingle();
      if (data == null) {
        throw const NetworkException('Chat not found.');
      }
      return ChatModel.fromSupabase(data);
    } catch (e) {
      if (e is AppException) rethrow;
      throw NetworkException('Failed to load chat: $e');
    }
  }

  Future<ChatModel> getOrCreateChat(String currentUid, String otherUid,
      {bool isSecret = false}) async {
    try {
      final chatId = _oneToOneChatId(currentUid, otherUid, isSecret);
      // One-on-one chat ids are deterministic, so the same pair always opens the
      // same chat instead of creating duplicates.
      final existing =
          await _client.from('chats').select().eq('id', chatId).maybeSingle();
      if (existing != null) {
        return ChatModel.fromSupabase(existing);
      }

      final chat = ChatModel(
        id: chatId,
        participantIds: [currentUid, otherUid],
        unreadCount: {currentUid: 0, otherUid: 0},
        isSecret: isSecret,
        createdAt: DateTime.now(),
      );

      await _client.from('chats').upsert(chat.toMap());
      return chat;
    } catch (e) {
      throw NetworkException('Failed to create chat: $e');
    }
  }

  Stream<List<MessageModel>> watchMessages(String chatId) {
    // Realtime message stream for one chat. Supabase sends rows whenever the
    // messages table changes, and the provider decides how to display them.
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_id', chatId)
        .order('timestamp', ascending: true)
        .map((rows) => rows.map(MessageModel.fromSupabase).toList());
  }

  Future<List<MessageModel>> getMessages(String chatId) async {
    try {
      final rows = await _client
          .from('messages')
          .select()
          .eq('chat_id', chatId)
          .order('timestamp', ascending: true);
      return rows.map<MessageModel>(MessageModel.fromSupabase).toList();
    } catch (e) {
      throw NetworkException('Failed to load messages: $e');
    }
  }

  Future<MessageModel> sendMessage({
    required String chatId,
    required String senderId,
    required String content,
    required String type,
    String? messageId,
    DateTime? timestamp,
    String? mediaUrl,
    String? thumbnailUrl,
  }) async {
    try {
      // Build the message model first. The same method handles text and media,
      // normal and secret messages.
      final message = MessageModel(
        id: messageId ?? _uuid.v4(),
        senderId: senderId,
        content: content,
        type: type,
        status: AppConstants.statusSent,
        timestamp: timestamp ?? DateTime.now(),
        mediaUrl: mediaUrl,
        thumbnailUrl: thumbnailUrl,
      );

      final chat = await getChat(chatId);
      final otherUid = chat.getOtherParticipantId(senderId);
      // Unread count is tracked per participant in the chat row.
      final unreadCount = Map<String, int>.from(chat.unreadCount);
      unreadCount[otherUid] = (unreadCount[otherUid] ?? 0) + 1;

      await _client.from('chats').update({
        // Keep chat list previews fast by storing last-message data on the chat
        // row. For secret text this content is ciphertext, so the home screen
        // shows a generic encrypted preview instead of trying to read it.
        'last_message': type == AppConstants.textMessage
            ? content
            : type == AppConstants.imageMessage
                ? 'Photo'
                : type == AppConstants.videoMessage
                    ? 'Video'
                    : 'Audio',
        'last_message_type': type,
        'last_message_sender_id': senderId,
        'last_message_time': DateTime.now().toUtc().toIso8601String(),
        'unread_count': unreadCount,
      }).eq('id', chatId);

      await _client.from('messages').insert({
        ...message.toMap(),
        'chat_id': chatId,
      });

      return message;
    } catch (e) {
      throw NetworkException('Failed to send message: $e');
    }
  }

  Future<void> editMessage({
    required String chatId,
    required String messageId,
    required String newContent,
  }) async {
    try {
      // Secret chats pass encrypted replacement text here; normal chats pass
      // plaintext replacement text.
      await _client
          .from('messages')
          .update({'content': newContent, 'is_edited': true})
          .eq('id', messageId)
          .eq('chat_id', chatId);
    } catch (e) {
      throw NetworkException('Failed to edit message: $e');
    }
  }

  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) async {
    try {
      // Soft delete keeps the row for all participants but changes how the UI
      // displays it.
      await _client
          .from('messages')
          .update({'is_deleted': true, 'content': 'This message was deleted'})
          .eq('id', messageId)
          .eq('chat_id', chatId);
    } catch (e) {
      throw NetworkException('Failed to delete message: $e');
    }
  }

  Future<void> markMessagesAsRead(String chatId, String uid) async {
    try {
      // Prefer the database function because it updates messages and unread
      // counters consistently in one backend operation.
      await _client.rpc('mark_chat_read', params: {'target_chat_id': chatId});
    } catch (_) {
      try {
        await _client
            .from('messages')
            .update({'status': AppConstants.statusRead})
            .eq('chat_id', chatId)
            .neq('sender_id', uid)
            .neq('status', AppConstants.statusRead);

        final chat = await getChat(chatId);
        final unreadCount = Map<String, int>.from(chat.unreadCount);
        unreadCount[uid] = 0;
        await _client
            .from('chats')
            .update({'unread_count': unreadCount}).eq('id', chatId);
      } catch (_) {}
    }
  }

  Future<void> markMessagesDelivered(String chatId, String uid) async {
    try {
      // When a user opens or receives a chat stream, incoming "sent" messages
      // become "delivered".
      await _client
          .from('messages')
          .update({'status': AppConstants.statusDelivered})
          .eq('chat_id', chatId)
          .neq('sender_id', uid)
          .eq('status', AppConstants.statusSent);
    } catch (_) {}
  }

  Future<void> setTyping(String chatId, String uid, bool isTyping) async {
    try {
      // Typing state is stored in the chat row as a map of user id -> bool.
      final chat = await getChat(chatId);
      final typing = <String, bool>{
        for (final id in chat.participantIds) id: false,
      };
      final row = await _client
          .from('chats')
          .select('typing')
          .eq('id', chatId)
          .single();
      typing.addAll(Map<String, bool>.from(row['typing'] ?? {}));
      typing[uid] = isTyping;
      await _client.from('chats').update({'typing': typing}).eq('id', chatId);
    } catch (_) {}
  }

  Stream<Map<String, bool>> watchTyping(String chatId) {
    // Typing indicators are lightweight realtime updates from the chat row.
    return _client
        .from('chats')
        .stream(primaryKey: ['id'])
        .eq('id', chatId)
        .map((rows) {
          if (rows.isEmpty) return <String, bool>{};
          return Map<String, bool>.from(rows.first['typing'] ?? {});
        });
  }

  Future<String> uploadMedia({
    required String chatId,
    required File file,
    required String type,
  }) async {
    try {
      // Normal media is uploaded as the original file. Access is protected by
      // Supabase Storage policies and signed URLs.
      final ext = _extensionFor(file.path, type);
      final path = '$chatId/${_uuid.v4()}.$ext';
      await _client.storage.from(_chatMediaBucket).upload(
            path,
            file,
            fileOptions: FileOptions(
              contentType: _contentTypeFor(type),
              upsert: false,
            ),
          );
      return path;
    } catch (e) {
      throw StorageException('Failed to upload media: $e');
    }
  }

  Future<String> uploadEncryptedMediaBytes({
    required String chatId,
    required Uint8List encryptedBytes,
    required String type,
  }) async {
    try {
      // Secret media is already encrypted before this method receives it, so it
      // is uploaded as opaque bytes with a .enc file name.
      final path = '$chatId/${_uuid.v4()}.$type.enc';
      await _client.storage.from(_chatMediaBucket).uploadBinary(
            path,
            encryptedBytes,
            fileOptions: const FileOptions(
              contentType: 'application/octet-stream',
              upsert: false,
            ),
          );
      return path;
    } catch (e) {
      throw StorageException('Failed to upload encrypted media: $e');
    }
  }

  Future<String> createSignedMediaUrl(String path) {
    // Storage paths are private, so the UI asks for a temporary signed URL when
    // it needs to display or play media.
    if (path.startsWith('http')) return Future.value(path);
    return _client.storage.from(_chatMediaBucket).createSignedUrl(path, 3600);
  }

  Future<Uint8List> downloadMediaBytes(String path) {
    return _client.storage.from(_chatMediaBucket).download(path);
  }

  Future<Map<String, String>> getParticipantPublicKeys(
    List<String> participantIds,
  ) async {
    try {
      // Secret chat setup needs every participant's public key so the same AES
      // chat key can be wrapped separately for each user.
      final rows = await _client
          .from('profiles')
          .select('id, public_key')
          .inFilter('id', participantIds);
      final result = <String, String>{};
      for (final row in rows) {
        final publicKey = row['public_key'] as String?;
        if (publicKey == null || publicKey.isEmpty) {
          throw NetworkException('User ${row['id']} has no encryption key.');
        }
        result[row['id'] as String] = publicKey;
      }
      if (result.length != participantIds.length) {
        throw const NetworkException('Missing participant encryption keys.');
      }
      return result;
    } catch (e) {
      if (e is AppException) rethrow;
      throw NetworkException('Failed to load encryption keys: $e');
    }
  }

  Future<void> saveEncryptedChatKeys({
    required String chatId,
    required Map<String, String> encryptedKeys,
  }) async {
    try {
      // encrypted_keys maps user id -> RSA-OAEP encrypted AES chat key.
      await _client
          .from('chats')
          .update({'encrypted_keys': encryptedKeys}).eq('id', chatId);
    } catch (e) {
      throw NetworkException('Failed to save encrypted chat keys: $e');
    }
  }

  String _extensionFor(String path, String type) {
    // Prefer the user's actual file extension. If there is none, fall back to a
    // sensible extension based on message type.
    final lastDot = path.lastIndexOf('.');
    if (lastDot != -1 && lastDot < path.length - 1) {
      return path.substring(lastDot + 1).toLowerCase();
    }
    switch (type) {
      case AppConstants.imageMessage:
        return 'jpg';
      case AppConstants.videoMessage:
        return 'mp4';
      case AppConstants.audioMessage:
        return 'm4a';
      default:
        return 'bin';
    }
  }

  String _contentTypeFor(String type) {
    // Supabase Storage uses this content type when serving normal media.
    switch (type) {
      case AppConstants.imageMessage:
        return 'image/jpeg';
      case AppConstants.videoMessage:
        return 'video/mp4';
      case AppConstants.audioMessage:
        return 'audio/mpeg';
      default:
        return 'application/octet-stream';
    }
  }

  String _oneToOneChatId(String firstUid, String secondUid, bool isSecret) {
    // Sorting means userA + userB and userB + userA produce the same id.
    // Prefix keeps normal and secret chats separate for the same two users.
    final ids = [firstUid, secondUid]..sort();
    final prefix = isSecret ? 'secret' : 'chat';
    return '${prefix}_${ids[0]}_${ids[1]}';
  }
}
