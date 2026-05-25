class AppConstants {
  static const String appName = 'SecureMessenger';

  // Supabase tables
  static const String usersCollection = 'users';
  static const String chatsCollection = 'chats';
  static const String messagesCollection = 'messages';
  static const String secretChatsCollection = 'secret_chats';
  static const String secretMessagesCollection = 'secret_messages';
  static const String contactsCollection = 'contacts';

  // Secure storage keys
  static const String biometricEnabledKey = 'biometric_enabled';
  static const String biometricEmailKey = 'biometric_email';
  static const String biometricPasswordKey = 'biometric_password';
  static const String identityPrivateKey = 'identity_private_key';
  static const String identityPublicKey = 'identity_public_key';
  static const String secretKeyPrefix = 'secret_key_';

  // Message types
  static const String textMessage = 'text';
  static const String imageMessage = 'image';
  static const String videoMessage = 'video';
  static const String audioMessage = 'audio';

  // Message status
  static const String statusSent = 'sent';
  static const String statusDelivered = 'delivered';
  static const String statusRead = 'read';

  // Timeouts
  static const Duration networkTimeout = Duration(seconds: 30);
  static const Duration typingTimeout = Duration(seconds: 3);
}
