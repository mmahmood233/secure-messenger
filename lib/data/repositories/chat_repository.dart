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
    return _watchChats(uid, isSecret: false);
  }

  Stream<List<ChatModel>> watchSecretChats(String uid) {
    return _watchChats(uid, isSecret: true);
  }

  Stream<List<ChatModel>> _watchChats(String uid, {required bool isSecret}) {
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
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_id', chatId)
        .order('timestamp', ascending: true)
        .map((rows) => rows.map(MessageModel.fromSupabase).toList());
  }

  Future<MessageModel> sendMessage({
    required String chatId,
    required String senderId,
    required String content,
    required String type,
    String? mediaUrl,
    String? thumbnailUrl,
  }) async {
    try {
      final msgId = _uuid.v4();
      final message = MessageModel(
        id: msgId,
        senderId: senderId,
        content: content,
        type: type,
        status: AppConstants.statusSent,
        timestamp: DateTime.now(),
        mediaUrl: mediaUrl,
        thumbnailUrl: thumbnailUrl,
      );

      await _client.from('messages').insert({
        ...message.toMap(),
        'chat_id': chatId,
      });

      final chat = await getChat(chatId);
      final otherUid = chat.getOtherParticipantId(senderId);
      final unreadCount = Map<String, int>.from(chat.unreadCount);
      unreadCount[otherUid] = (unreadCount[otherUid] ?? 0) + 1;

      await _client.from('chats').update({
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
      await _client
          .from('messages')
          .update({'status': AppConstants.statusRead})
          .eq('chat_id', chatId)
          .neq('sender_id', uid);

      final chat = await getChat(chatId);
      final unreadCount = Map<String, int>.from(chat.unreadCount);
      unreadCount[uid] = 0;
      await _client
          .from('chats')
          .update({'unread_count': unreadCount}).eq('id', chatId);
    } catch (_) {}
  }

  Future<void> markMessagesDelivered(String chatId, String uid) async {
    try {
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
      await _client
          .from('chats')
          .update({'encrypted_keys': encryptedKeys}).eq('id', chatId);
    } catch (e) {
      throw NetworkException('Failed to save encrypted chat keys: $e');
    }
  }

  String _extensionFor(String path, String type) {
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
    final ids = [firstUid, secondUid]..sort();
    final prefix = isSecret ? 'secret' : 'chat';
    return '${prefix}_${ids[0]}_${ids[1]}';
  }
}
