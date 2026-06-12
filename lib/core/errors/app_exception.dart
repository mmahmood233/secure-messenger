// App-specific exception classes and auth error mapping.
// These give the UI clean messages instead of exposing raw backend errors.
class AppException implements Exception {
  final String message;
  final String? code;

  const AppException(this.message, {this.code});

  @override
  String toString() => message;
}

class AuthException extends AppException {
  const AuthException(super.message, {super.code});
}

class NetworkException extends AppException {
  const NetworkException(super.message, {super.code});
}

class StorageException extends AppException {
  const StorageException(super.message, {super.code});
}

class EncryptionException extends AppException {
  const EncryptionException(super.message, {super.code});
}

String mapAuthError(String message) {
  final normalized = message.toLowerCase();
  if (normalized.contains('invalid login') ||
      normalized.contains('invalid credentials')) {
    return 'Invalid credentials. Please check your email and password.';
  }
  if (normalized.contains('already registered') ||
      normalized.contains('already exists')) {
    return 'An account already exists with this email.';
  }
  if (normalized.contains('email')) {
    return 'Please enter a valid email address.';
  }
  if (normalized.contains('password')) {
    return 'Password is too weak. Use at least 6 characters.';
  }
  if (normalized.contains('network')) {
    return 'Network error. Please check your connection.';
  }
  return 'Authentication failed. Please try again.';
}
