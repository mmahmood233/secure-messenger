import 'package:cloud_firestore/cloud_firestore.dart';

class ChatModel {
  final String id;
  final List<String> participantIds;
  final String? lastMessage;
  final String? lastMessageType;
  final String? lastMessageSenderId;
  final DateTime? lastMessageTime;
  final Map<String, int> unreadCount;
  final bool isSecret;
  final DateTime createdAt;

  const ChatModel({
    required this.id,
    required this.participantIds,
    this.lastMessage,
    this.lastMessageType,
    this.lastMessageSenderId,
    this.lastMessageTime,
    required this.unreadCount,
    this.isSecret = false,
    required this.createdAt,
  });

  factory ChatModel.fromMap(Map<String, dynamic> map, String id) {
    return ChatModel(
      id: id,
      participantIds: List<String>.from(map['participantIds'] ?? []),
      lastMessage: map['lastMessage'],
      lastMessageType: map['lastMessageType'],
      lastMessageSenderId: map['lastMessageSenderId'],
      lastMessageTime: map['lastMessageTime'] != null
          ? (map['lastMessageTime'] as Timestamp).toDate()
          : null,
      unreadCount: Map<String, int>.from(map['unreadCount'] ?? {}),
      isSecret: map['isSecret'] ?? false,
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  factory ChatModel.fromDoc(DocumentSnapshot doc) {
    return ChatModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'participantIds': participantIds,
      'lastMessage': lastMessage,
      'lastMessageType': lastMessageType,
      'lastMessageSenderId': lastMessageSenderId,
      'lastMessageTime': lastMessageTime != null
          ? Timestamp.fromDate(lastMessageTime!)
          : null,
      'unreadCount': unreadCount,
      'isSecret': isSecret,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  String getOtherParticipantId(String currentUserId) {
    return participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );
  }

  ChatModel copyWith({
    String? id,
    List<String>? participantIds,
    String? lastMessage,
    String? lastMessageType,
    String? lastMessageSenderId,
    DateTime? lastMessageTime,
    Map<String, int>? unreadCount,
    bool? isSecret,
    DateTime? createdAt,
  }) {
    return ChatModel(
      id: id ?? this.id,
      participantIds: participantIds ?? this.participantIds,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isSecret: isSecret ?? this.isSecret,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
