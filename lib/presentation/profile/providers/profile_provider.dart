import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:secure_messenger/core/errors/app_exception.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/data/repositories/user_repository.dart';

enum ProfileStatus { idle, loading, success, error }

class ProfileProvider extends ChangeNotifier {
  final UserRepository _userRepository;

  ProfileStatus _status = ProfileStatus.idle;
  String? _errorMessage;
  UserModel? _profileUser;

  ProfileStatus get status => _status;
  String? get errorMessage => _errorMessage;
  UserModel? get profileUser => _profileUser;

  ProfileProvider(this._userRepository);

  Future<bool> updateProfile({
    required String uid,
    String? displayName,
    String? bio,
    String? phoneNumber,
    String? username,
  }) async {
    _setLoading();
    try {
      await _userRepository.updateProfile(
        uid: uid,
        displayName: displayName,
        bio: bio,
        phoneNumber: phoneNumber,
        username: username,
      );
      _status = ProfileStatus.success;
      notifyListeners();
      return true;
    } on AppException catch (e) {
      _setError(e.message);
      return false;
    }
  }

  Future<String?> uploadProfilePhoto(String uid, File imageFile) async {
    _setLoading();
    try {
      final url = await _userRepository.uploadProfilePhoto(uid, imageFile);
      _status = ProfileStatus.success;
      notifyListeners();
      return url;
    } on AppException catch (e) {
      _setError(e.message);
      return null;
    }
  }

  Future<void> loadUser(String uid) async {
    _setLoading();
    try {
      _profileUser = await _userRepository.getUserById(uid);
      _status = ProfileStatus.success;
      notifyListeners();
    } on AppException catch (e) {
      _setError(e.message);
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading() {
    _status = ProfileStatus.loading;
    _errorMessage = null;
    notifyListeners();
  }

  void _setError(String message) {
    _status = ProfileStatus.error;
    _errorMessage = message;
    notifyListeners();
  }
}
