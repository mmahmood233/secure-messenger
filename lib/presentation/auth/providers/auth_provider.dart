import 'package:flutter/foundation.dart';
import 'package:secure_messenger/core/errors/app_exception.dart';
import 'package:secure_messenger/core/services/biometric_service.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/data/repositories/auth_repository.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  biometricLocked,
  unauthenticated,
  error,
}

class AuthProvider extends ChangeNotifier {
  final AuthRepository _authRepository;
  final BiometricService _biometricService;

  AuthStatus _status = AuthStatus.initial;
  UserModel? _currentUser;
  String? _errorMessage;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _biometricUnlockInProgress = false;
  bool _accountCreationInProgress = false;

  AuthStatus get status => _status;
  UserModel? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;
  bool get biometricAvailable => _biometricAvailable;
  bool get biometricEnabled => _biometricEnabled;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  AuthProvider(this._authRepository, this._biometricService) {
    _init();
  }

  Future<void> _init() async {
    _biometricAvailable = await _biometricService.isAvailable();
    _biometricEnabled = await _biometricService.isBiometricEnabled();

    _authRepository.authStateChanges.listen((state) async {
      final isCreatingAccount = _accountCreationInProgress;
      if (state.session?.user != null) {
        var profile = await _authRepository.getCurrentUserProfile();
        if (profile == null && isCreatingAccount) {
          for (var attempt = 0; attempt < 4; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            profile = await _authRepository.getCurrentUserProfile();
            if (profile != null) break;
          }
        }
        if (profile == null && isCreatingAccount && _currentUser != null) {
          profile = _currentUser;
        }

        _currentUser = profile;
        if (profile == null) {
          if (isCreatingAccount || _accountCreationInProgress) {
            _status = AuthStatus.loading;
            _errorMessage = null;
          } else {
            _status = AuthStatus.error;
            _errorMessage = 'User profile not found. Please sign in again.';
          }
        } else {
          _status = _biometricEnabled && !_biometricUnlockInProgress
              ? AuthStatus.biometricLocked
              : AuthStatus.authenticated;
        }
      } else {
        _currentUser = null;
        _status = AuthStatus.unauthenticated;
      }
      _biometricUnlockInProgress = false;
      notifyListeners();
    });
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    _setLoading();
    _accountCreationInProgress = true;
    try {
      _currentUser = await _authRepository.signUp(
        email: email,
        password: password,
        username: username,
        displayName: displayName,
      );
      _accountCreationInProgress = false;
      _status = AuthStatus.authenticated;
      _errorMessage = null;
      notifyListeners();
      return true;
    } on AppException catch (e) {
      _accountCreationInProgress = false;
      _setError(e.message);
      return false;
    } catch (e) {
      _accountCreationInProgress = false;
      _setError(e.toString());
      return false;
    }
  }

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _setLoading();
    try {
      _currentUser = await _authRepository.signIn(
        email: email,
        password: password,
      );
      if (_biometricEnabled) {
        await _biometricService.storeCredentials(
          email: email,
          password: password,
        );
        _status = AuthStatus.biometricLocked;
      } else {
        _status = AuthStatus.authenticated;
      }
      notifyListeners();
      return true;
    } on AppException catch (e) {
      _setError(e.message);
      return false;
    }
  }

  Future<bool> authenticateWithBiometric() async {
    try {
      if (!_biometricEnabled) return false;
      final didAuthenticate = await _biometricService.authenticate();
      if (!didAuthenticate) return false;

      if (_currentUser != null) {
        _status = AuthStatus.authenticated;
        notifyListeners();
        return true;
      }

      final credentials = await _biometricService.getStoredCredentials();
      if (credentials == null) return false;
      _setLoading();
      _biometricUnlockInProgress = true;
      _currentUser = await _authRepository.signIn(
        email: credentials['email']!,
        password: credentials['password']!,
      );
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (_) {
      _biometricUnlockInProgress = false;
      return false;
    }
  }

  Future<void> signOut() async {
    _setLoading();
    try {
      await _authRepository.signOut();
      _currentUser = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    } on AppException catch (e) {
      _setError(e.message);
    }
  }

  Future<bool> enableBiometricLogin(String password) async {
    final email = _currentUser?.email;
    if (email == null || email.isEmpty) {
      _setError('Current user email is unavailable.');
      return false;
    }
    if (!_biometricAvailable) {
      _setError('Biometric authentication is not available on this device.');
      return false;
    }
    try {
      final didAuthenticate = await _biometricService.authenticate();
      if (!didAuthenticate) {
        _setError('Biometric authentication failed.');
        return false;
      }
      await _authRepository.signIn(email: email, password: password);
      await _biometricService.storeCredentials(
          email: email, password: password);
      await _biometricService.setBiometricEnabled(true);
      _biometricEnabled = true;
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on AppException catch (e) {
      _setError(e.message);
      return false;
    }
  }

  Future<void> disableBiometricLogin() async {
    await _biometricService.setBiometricEnabled(false);
    _biometricEnabled = false;
    if (_status == AuthStatus.biometricLocked) {
      _status = AuthStatus.authenticated;
    }
    notifyListeners();
  }

  void updateCurrentUser(UserModel user) {
    _currentUser = user;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading() {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();
  }

  void _setError(String message) {
    _status = AuthStatus.error;
    _errorMessage = message;
    notifyListeners();
  }
}
