import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:secure_messenger/core/constants/app_constants.dart';
import 'package:secure_messenger/core/errors/app_exception.dart';
import 'package:secure_messenger/data/models/chat_model.dart';
import 'package:secure_messenger/data/models/message_model.dart';

class ChatRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final Uuid _uuid;

  ChatRepository(this._firestore, this._storage) : _uuid = const Uuid();

  Stream<List<ChatModel>> watchChats(String uid) {
    return _firestore
        .collection(AppConstants.chatsCollection)
        .where('participantIds', arrayContains: uid)
        .where('isSecret', isEqualTo: false)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => ChatModel.fromDoc(d)).toList());
  }

  Stream<List<ChatModel>> watchSecretChats(String uid) {
    return _firestore
        .collection(AppConstants.chatsCollection)
        .where('participantIds', arrayContains: uid)
        .where('isSecret', isEqualTo: true)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => ChatModel.fromDoc(d)).toList());
  }

  Future<ChatModel> getOrCreateChat(
      String currentUid, String otherUid, {bool isSecret = false}) async {
    try {
      final existing = await _firestore
          .collection(AppConstants.chatsCollection)
          .where('participantIds', arrayContains: currentUid)
          .where('isSecret', isEqualTo: isSecret)
          .get();

      for (final doc in existing.docs) {
        final chat = ChatModel.fromDoc(doc);
        if (chat.participantIds.contains(otherUid)) {
          return chat;
        }
      }

      final chatId = _uuid.v4();
      final chat = ChatModel(
        id: chatId,
        participantIds: [currentUid, otherUid],
        unreadCount: {currentUid: 0, otherUid: 0},
        isSecret: isSecret,
        createdAt: DateTime.now(),
      );

      final chatData = chat.toMap();
      chatData['typing'] = {currentUid: false, otherUid: false};

      await _firestore
          .collection(AppConstants.chatsCollection)
          .doc(chatId)
          .set(chatData);

      return chat;
    } catch (e) {
      throw NetworkException('Failed to create chat: $e');
    }
  }

  Stream<List<MessageModel>> watchMessages(String chatId) {
    return _firestore
        .collection(AppConstants.chatsCollection)
        .doc(chatId)
        .collection(AppConstants.messagesCollection)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) => MessageModel.fromDoc(d)).toList());
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

      final batch = _firestore.batch();

      final msgRef = _firestore
          .collection(AppConstants.chatsCollection)
          .doc(chatId)
          .collection(AppConstants.messagesCollection)
          .doc(msgId);

      batch.set(msgRef, message.toMap());

      final chatRef =
          _firestore.collection(AppConstants.chatsCollection).doc(chatId);

      final chatDoc = await chatRef.get();
      final chat = ChatModel.fromDoc(chatDoc);
      final otherUid = chat.getOtherParticipantId(senderId);

      batch.update(chatRef, {
        'lastMessage': type == AppConstants.textMessage ? content : '📎 $type',
        'lastMessageType': type,
        'lastMessageSenderId': senderId,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount.$otherUid': FieldValue.increment(1),
      });

      await batch.commit();
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
      await _firestore
          .collection(AppConstants.chatsCollection)
          .doc(chatId)
          .collection(AppConstants.messagesCollection)
          .doc(messageId)
          .update({'content': newContent, 'isEdited': true});
    } catch (e) {
      throw NetworkException('Failed to edit message: $e');
    }
  }

  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) async {
    try {
      await _firestore
          .collection(AppConstants.chatsCollection)
          .doc(chatId)
          .collection(AppConstants.messagesCollection)
          .doc(messageId)
          .update({'isDeleted': true, 'content': 'This message was deleted'});
    } catch (e) {
      throw NetworkException('Failed to delete message: $e');
    }
  }

  Future<void> markMessagesAsRead(String chatId, String uid) async {
    try {
      final snap = await _firestore
          .collection(AppConstants.chatsCollection)
          .doc(chatId)
          .collection(AppConstants.messagesCollection)
          .where('senderId', isNotEqualTo: uid)
          .get();

      if (snap.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        final status = doc.data()['status'] as String? ?? AppConstants.statusSent;
        if (status != AppConstants.statusRead) {
          batch.update(doc.reference, {'status': AppConstants.statusRead});
        }
      }

      batch.update(
        _firestore.collection(AppConstants.chatsCollection).doc(chatId),
        {'unreadCount.$uid': 0},
      );

      await batch.commit();
    } catch (_) {}
  }

  Future<void> markMessagesDelivered(String chatId, String uid) async {
    try {
      final snap = await _firestore
          .collection(AppConstants.chatsCollection)
          .doc(chatId)
          .collection(AppConstants.messagesCollection)
          .where('senderId', isNotEqualTo: uid)
          .where('status', isEqualTo: AppConstants.statusSent)
          .get();

      if (snap.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'status': AppConstants.statusDelivered});
      }
      await batch.commit();
    } catch (_) {}
  }

  Future<void> setTyping(String chatId, String uid, bool isTyping) async {
    try {
      await _firestore
          .collection(AppConstants.chatsCollection)
          .doc(chatId)
          .update({'typing.$uid': isTyping});
    } catch (_) {}
  }

  Stream<Map<String, bool>> watchTyping(String chatId) {
    return _firestore
        .collection(AppConstants.chatsCollection)
        .doc(chatId)
        .snapshots()
        .map((doc) {
      final data = doc.data();
      if (data == null || !data.containsKey('typing')) return {};
      return Map<String, bool>.from(data['typing'] as Map);
    });
  }

  Future<String> uploadMedia({
    required String chatId,
    required File file,
    required String type,
  }) async {
    try {
      final ext = type == AppConstants.imageMessage ? 'jpg' : 'mp4';
      final fileName = '${_uuid.v4()}.$ext';
      final ref = _storage.ref().child('chat_media/$chatId/$fileName');
      final uploadTask = await ref.putFile(file);
      return await uploadTask.ref.getDownloadURL();
    } catch (e) {
      throw StorageException('Failed to upload media: $e');
    }
  }
}
