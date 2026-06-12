// Data model for a chat row.
//
// A chat is the container around messages. It stores participant ids, chat-list
// preview data, unread counters, typing state, and whether the chat is normal or
// secret. Secret chats also use encryptedKeys to store the encrypted AES chat
// key for each participant.
class ChatModel {
  final String id;
  final List<String> participantIds;
  final String? lastMessage;
  final String? lastMessageType;
  final String? lastMessageSenderId;
  final DateTime? lastMessageTime;
  final Map<String, int> unreadCount;
  final Map<String, String> encryptedKeys;
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
    this.encryptedKeys = const {},
    this.isSecret = false,
    required this.createdAt,
  });

  factory ChatModel.fromMap(Map<String, dynamic> map, String id) {
    // Accepts both Dart-style keys and Supabase snake_case keys. This makes the
    // model easy to use with real Supabase rows and with simpler test maps.
    return ChatModel(
      id: id,
      participantIds: List<String>.from(
          map['participantIds'] ?? map['participant_ids'] ?? []),
      lastMessage: map['lastMessage'] ?? map['last_message'],
      lastMessageType: map['lastMessageType'] ?? map['last_message_type'],
      lastMessageSenderId:
          map['lastMessageSenderId'] ?? map['last_message_sender_id'],
      lastMessageTime:
          _parseDate(map['lastMessageTime'] ?? map['last_message_time']),
      unreadCount: _intMapFrom(map['unreadCount'] ?? map['unread_count'] ?? {}),
      encryptedKeys: Map<String, String>.from(
          map['encryptedKeys'] ?? map['encrypted_keys'] ?? {}),
      isSecret: map['isSecret'] ?? map['is_secret'] ?? false,
      createdAt:
          _parseDate(map['createdAt'] ?? map['created_at']) ?? DateTime.now(),
    );
  }

  factory ChatModel.fromSupabase(Map<String, dynamic> map) {
    return ChatModel.fromMap(map, map['id'] ?? '');
  }

  Map<String, dynamic> toMap() {
    // Supabase columns use snake_case, so this map is ready to insert/update.
    // typing starts with every participant set to false.
    return {
      'id': id,
      'participant_ids': participantIds,
      'last_message': lastMessage,
      'last_message_type': lastMessageType,
      'last_message_sender_id': lastMessageSenderId,
      'last_message_time': lastMessageTime?.toIso8601String(),
      'unread_count': unreadCount,
      'encrypted_keys': encryptedKeys,
      'typing': {for (final id in participantIds) id: false},
      'is_secret': isSecret,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String getOtherParticipantId(String currentUserId) {
    // This app only supports one-on-one chats, so "the other participant" is the
    // id that is not the current user.
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
    Map<String, String>? encryptedKeys,
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
      encryptedKeys: encryptedKeys ?? this.encryptedKeys,
      isSecret: isSecret ?? this.isSecret,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }

  static Map<String, int> _intMapFrom(dynamic value) {
    // JSON values from Supabase may come back as num, so convert them to int for
    // the Dart model.
    final map = Map<String, dynamic>.from(value as Map? ?? {});
    return map.map((key, value) => MapEntry(key, (value as num).toInt()));
  }
}
