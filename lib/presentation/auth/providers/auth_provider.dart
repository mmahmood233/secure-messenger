// Auth state provider.
//
// This file is the bridge between auth UI and backend/security services.
// Screens call methods like signIn(), signUp(), and authenticateWithBiometric().
// The app router watches status to decide whether to show LoginScreen or
// HomeScreen.
import 'package:flutter/foundation.dart';
import 'package:secure_messenger/core/errors/app_exception.dart';
import 'package:secure_messenger/core/services/biometric_service.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/data/repositories/auth_repository.dart';

enum AuthStatus {
  // App just started and has not checked Supabase/biometric state yet.
  initial,
  // A login/signup/signout action is running.
  loading,
  // User has a valid Supabase session and passed any required biometric gate.
  authenticated,
  // Supabase session exists, but biometric unlock is required before HomeScreen.
  biometricLocked,
  // No Supabase session.
  unauthenticated,
  // An auth or profile-loading problem happened.
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
    // Load biometric state first so the router knows whether to lock the app
    // after Supabase restores an existing session.
    _biometricAvailable = await _biometricService.isAvailable();
    _biometricEnabled = await _biometricService.isBiometricEnabled();

    _authRepository.authStateChanges.listen((state) async {
      // Supabase emits auth changes for login, logout, and restored sessions.
      // The provider turns those events into app-friendly AuthStatus values.
      final isCreatingAccount = _accountCreationInProgress;
      if (state.session?.user != null) {
        // Supabase can emit an auth session before the profile row is visible,
        // especially right after signup, so retry briefly.
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
          // If biometric login is enabled, a restored session still opens behind
          // a biometric gate. The user must unlock before seeing HomeScreen.
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
    // Sign up creates both the Supabase auth user and the profile row.
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
    // Email/password sign-in always goes through Supabase first. If biometrics
    // are enabled, the app then locks until biometric authentication succeeds.
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
      // This is called from LoginScreen's biometric button.
      if (!_biometricEnabled) return false;
      final didAuthenticate = await _biometricService.authenticate();
      if (!didAuthenticate) return false;

      if (_currentUser != null) {
        // Existing Supabase session is already present; biometrics only unlock
        // the local app view.
        _status = AuthStatus.authenticated;
        notifyListeners();
        return true;
      }

      // No active session, so use the stored email/password after biometric
      // verification to sign in again.
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
    // Sign out clears the Supabase session and returns the router to LoginScreen.
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
      // Verify the user can pass biometrics and that the password is correct
      // before saving credentials for future biometric login.
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
    // Disabling removes stored biometric credentials in BiometricService.
    await _biometricService.setBiometricEnabled(false);
    _biometricEnabled = false;
    if (_status == AuthStatus.biometricLocked) {
      _status = AuthStatus.authenticated;
    }
    notifyListeners();
  }

  void updateCurrentUser(UserModel user) {
    // ProfileScreen calls this after editing local profile fields so the UI can
    // update immediately without waiting for a fresh auth event.
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
