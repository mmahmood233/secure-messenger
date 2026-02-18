import 'package:flutter/foundation.dart';
import 'package:secure_messenger/core/errors/app_exception.dart';
import 'package:secure_messenger/core/services/biometric_service.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/data/repositories/auth_repository.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  final AuthRepository _authRepository;
  final BiometricService _biometricService;

  AuthStatus _status = AuthStatus.initial;
  UserModel? _currentUser;
  String? _errorMessage;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

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

    _authRepository.authStateChanges.listen((user) async {
      if (user != null) {
        _currentUser = await _authRepository.getCurrentUserProfile();
        _status = AuthStatus.authenticated;
      } else {
        _currentUser = null;
        _status = AuthStatus.unauthenticated;
      }
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
    try {
      _currentUser = await _authRepository.signUp(
        email: email,
        password: password,
        username: username,
        displayName: displayName,
      );
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on AppException catch (e) {
      _setError(e.message);
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
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on AppException catch (e) {
      _setError(e.message);
      return false;
    }
  }

  Future<bool> authenticateWithBiometric() async {
    try {
      return await _biometricService.authenticate();
    } catch (_) {
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

  Future<void> toggleBiometric(bool enabled) async {
    await _biometricService.setBiometricEnabled(enabled);
    _biometricEnabled = enabled;
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
