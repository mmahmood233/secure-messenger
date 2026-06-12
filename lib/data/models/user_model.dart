// Data model for a user profile row.
//
// This is the app's public profile object. It is used for login state, profile
// editing, contact lists, chat headers, QR codes, and secret-chat public keys.
class UserModel {
  final String uid;
  final String email;
  final String username;
  final String displayName;
  final String? photoUrl;
  final String? bio;
  final String? phoneNumber;
  final String? publicKey;
  final bool isOnline;
  final DateTime? lastSeen;
  final DateTime createdAt;

  const UserModel({
    required this.uid,
    required this.email,
    required this.username,
    required this.displayName,
    this.photoUrl,
    this.bio,
    this.phoneNumber,
    this.publicKey,
    this.isOnline = false,
    this.lastSeen,
    required this.createdAt,
  });

  factory UserModel.fromMap(Map<String, dynamic> map, String uid) {
    // Handles both local Dart maps and Supabase profile rows by accepting
    // camelCase and snake_case names.
    return UserModel(
      uid: uid,
      email: map['email'] ?? '',
      username: map['username'] ?? '',
      displayName: map['displayName'] ?? map['display_name'] ?? '',
      photoUrl: map['photoUrl'] ?? map['photo_url'],
      bio: map['bio'],
      phoneNumber: map['phoneNumber'] ?? map['phone_number'],
      publicKey: map['publicKey'] ?? map['public_key'],
      isOnline: map['isOnline'] ?? map['is_online'] ?? false,
      lastSeen: _parseDate(map['lastSeen'] ?? map['last_seen']),
      createdAt:
          _parseDate(map['createdAt'] ?? map['created_at']) ?? DateTime.now(),
    );
  }

  factory UserModel.fromSupabase(Map<String, dynamic> map) {
    return UserModel.fromMap(map, map['id'] ?? map['uid'] ?? '');
  }

  Map<String, dynamic> toMap() {
    // Converts the profile to the Supabase profiles-table shape. The public key
    // is safe to store in Supabase; the private key is never included here.
    return {
      'id': uid,
      'email': email,
      'username': username,
      'display_name': displayName,
      'photo_url': photoUrl,
      'bio': bio,
      'phone_number': phoneNumber,
      'public_key': publicKey,
      'is_online': isOnline,
      'last_seen': lastSeen?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? username,
    String? displayName,
    String? photoUrl,
    String? bio,
    String? phoneNumber,
    String? publicKey,
    bool? isOnline,
    DateTime? lastSeen,
    DateTime? createdAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      bio: bio ?? this.bio,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      publicKey: publicKey ?? this.publicKey,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    // Supabase returns date columns as strings, but tests/local objects may
    // already pass DateTime values.
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}
