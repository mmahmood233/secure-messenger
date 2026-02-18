import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:secure_messenger/core/constants/app_constants.dart';

class MessageModel {
  final String id;
  final String senderId;
  final String content;
  final String type;
  final String status;
  final DateTime timestamp;
  final bool isEdited;
  final bool isDeleted;
  final String? mediaUrl;
  final String? thumbnailUrl;

  const MessageModel({
    required this.id,
    required this.senderId,
    required this.content,
    required this.type,
    required this.status,
    required this.timestamp,
    this.isEdited = false,
    this.isDeleted = false,
    this.mediaUrl,
    this.thumbnailUrl,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map, String id) {
    return MessageModel(
      id: id,
      senderId: map['senderId'] ?? '',
      content: map['content'] ?? '',
      type: map['type'] ?? AppConstants.textMessage,
      status: map['status'] ?? AppConstants.statusSent,
      timestamp: map['timestamp'] != null
          ? (map['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      isEdited: map['isEdited'] ?? false,
      isDeleted: map['isDeleted'] ?? false,
      mediaUrl: map['mediaUrl'],
      thumbnailUrl: map['thumbnailUrl'],
    );
  }

  factory MessageModel.fromDoc(DocumentSnapshot doc) {
    return MessageModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'content': content,
      'type': type,
      'status': status,
      'timestamp': Timestamp.fromDate(timestamp),
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      'mediaUrl': mediaUrl,
      'thumbnailUrl': thumbnailUrl,
    };
  }

  MessageModel copyWith({
    String? id,
    String? senderId,
    String? content,
    String? type,
    String? status,
    DateTime? timestamp,
    bool? isEdited,
    bool? isDeleted,
    String? mediaUrl,
    String? thumbnailUrl,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      type: type ?? this.type,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    );
  }
}
