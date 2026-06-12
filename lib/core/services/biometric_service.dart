// Biometric authentication service.
//
// This file is the only place that directly talks to the phone's biometric API.
// AuthProvider uses this service to:
// 1. Check whether fingerprint/Face ID is available.
// 2. Ask the OS to authenticate the user.
// 3. Save or remove the credentials used for biometric login.
//
// The app never receives fingerprint or Face ID data. The OS only returns true
// or false after the biometric prompt.
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:secure_messenger/core/constants/app_constants.dart';

class BiometricService {
  final LocalAuthentication _localAuth;
  final FlutterSecureStorage _secureStorage;

  BiometricService(this._localAuth, this._secureStorage);

  Future<bool> isAvailable() async {
    try {
      // isDeviceSupported means the hardware/OS can use biometrics.
      // canCheckBiometrics means the user has enrolled a fingerprint/Face ID.
      // Both must be true before showing biometric login as an option.
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      return isDeviceSupported && canCheckBiometrics;
    } on PlatformException {
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      // Returns the actual biometric types available on the device, for example
      // face, fingerprint, or iris. The UI can use this if it wants a specific
      // label instead of a generic "Biometrics" label.
      return await _localAuth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    }
  }

  Future<bool> authenticate() async {
    try {
      // The OS owns the biometric prompt. If the user passes, local_auth returns
      // true. If they cancel, fail, or the platform throws, this method returns
      // false and the app stays locked.
      //
      // biometricOnly keeps this flow focused on fingerprint/Face ID instead of
      // silently falling back to the phone passcode.
      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to access SecureMessenger',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }

  Future<void> storeCredentials({
    required String email,
    required String password,
  }) async {
    // These credentials are used only after biometric verification succeeds.
    // They are stored with flutter_secure_storage, which maps to platform secure
    // storage such as iOS Keychain and Android encrypted storage.
    await _secureStorage.write(
      key: AppConstants.biometricEmailKey,
      value: email,
    );
    await _secureStorage.write(
      key: AppConstants.biometricPasswordKey,
      value: password,
    );
  }

  Future<Map<String, String>?> getStoredCredentials() async {
    // If either value is missing, biometric sign-in cannot continue because
    // Supabase still needs both email and password for signInWithPassword.
    final email =
        await _secureStorage.read(key: AppConstants.biometricEmailKey);
    final password = await _secureStorage.read(
      key: AppConstants.biometricPasswordKey,
    );
    if (email == null || password == null) return null;
    return {'email': email, 'password': password};
  }

  Future<void> clearStoredCredentials() async {
    await _secureStorage.delete(key: AppConstants.biometricEmailKey);
    await _secureStorage.delete(key: AppConstants.biometricPasswordKey);
  }

  Future<bool> isBiometricEnabled() async {
    // The boolean flag is stored separately from the credentials so the UI can
    // know whether biometric login is enabled before trying to read credentials.
    final value = await _secureStorage.read(
      key: AppConstants.biometricEnabledKey,
    );
    return value == 'true';
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    // This only controls app behavior. The actual biometric enrollment remains
    // managed by the phone's settings.
    await _secureStorage.write(
      key: AppConstants.biometricEnabledKey,
      value: enabled.toString(),
    );
    if (!enabled) {
      // Turning biometrics off also removes saved login credentials.
      await clearStoredCredentials();
    }
  }
}
