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
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      return isDeviceSupported && canCheckBiometrics;
    } on PlatformException {
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    }
  }

  Future<bool> authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to access SecureMessenger',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }

  Future<bool> isBiometricEnabled() async {
    final value = await _secureStorage.read(
      key: AppConstants.biometricEnabledKey,
    );
    return value == 'true';
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _secureStorage.write(
      key: AppConstants.biometricEnabledKey,
      value: enabled.toString(),
    );
  }
}
