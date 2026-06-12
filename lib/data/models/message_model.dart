// Data model for one message row.
//
// content means different things depending on the chat:
// - Normal text chat: plaintext message.
// - Secret text chat: encrypted payload.
// - Media message: a label such as Photo, Video, or Audio.
//
// mediaUrl stores the Supabase Storage path for image/video/audio messages.
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
    // Accepts both Dart-style keys and Supabase snake_case keys, so the same
    // model works for app-created maps and Supabase rows.
    return MessageModel(
      id: id,
      senderId: map['senderId'] ?? map['sender_id'] ?? '',
      content: map['content'] ?? '',
      type: map['type'] ?? AppConstants.textMessage,
      status: map['status'] ?? AppConstants.statusSent,
      timestamp: _parseDate(map['timestamp']) ?? DateTime.now(),
      isEdited: map['isEdited'] ?? map['is_edited'] ?? false,
      isDeleted: map['isDeleted'] ?? map['is_deleted'] ?? false,
      mediaUrl: map['mediaUrl'] ?? map['media_url'],
      thumbnailUrl: map['thumbnailUrl'] ?? map['thumbnail_url'],
    );
  }

  factory MessageModel.fromSupabase(Map<String, dynamic> map) {
    return MessageModel.fromMap(map, map['id'] ?? '');
  }

  Map<String, dynamic> toMap() {
    // Converts the message to the Supabase messages-table shape.
    // The repository adds chat_id when inserting because chat_id is not part of
    // the reusable MessageModel itself.
    return {
      'id': id,
      'sender_id': senderId,
      'content': content,
      'type': type,
      'status': status,
      'timestamp': timestamp.toIso8601String(),
      'is_edited': isEdited,
      'is_deleted': isDeleted,
      'media_url': mediaUrl,
      'thumbnail_url': thumbnailUrl,
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

  static DateTime? _parseDate(dynamic value) {
    // Supabase timestamps arrive as strings; local code may already have a
    // DateTime when creating pending messages.
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}
