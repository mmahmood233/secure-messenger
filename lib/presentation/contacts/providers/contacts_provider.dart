import 'package:flutter/foundation.dart';
import 'package:secure_messenger/core/errors/app_exception.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/data/repositories/user_repository.dart';

enum ContactsStatus { idle, loading, success, error }

class ContactsProvider extends ChangeNotifier {
  final UserRepository _userRepository;

  ContactsStatus _status = ContactsStatus.idle;
  String? _errorMessage;
  List<UserModel> _contacts = [];
  List<UserModel> _searchResults = [];
  bool _isSearching = false;

  ContactsStatus get status => _status;
  String? get errorMessage => _errorMessage;
  List<UserModel> get contacts => _contacts;
  List<UserModel> get searchResults => _searchResults;
  bool get isSearching => _isSearching;

  ContactsProvider(this._userRepository);

  Future<void> loadContacts(String uid) async {
    _setLoading();
    try {
      _contacts = await _userRepository.getContacts(uid);
      _status = ContactsStatus.success;
      notifyListeners();
    } on AppException catch (e) {
      _setError(e.message);
    }
  }

  Future<void> searchUsers(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
      _isSearching = false;
      notifyListeners();
      return;
    }
    _isSearching = true;
    notifyListeners();
    try {
      _searchResults = await _userRepository.searchUsers(query.trim());
      _isSearching = false;
      notifyListeners();
    } on AppException catch (e) {
      _isSearching = false;
      _setError(e.message);
    }
  }

  Future<UserModel?> getUserByUid(String uid) async {
    try {
      return await _userRepository.getUserById(uid);
    } catch (_) {
      return null;
    }
  }

  Future<bool> addContact(String currentUid, String contactUid) async {
    try {
      await _userRepository.addContact(currentUid, contactUid);
      await loadContacts(currentUid);
      return true;
    } on AppException catch (e) {
      _setError(e.message);
      return false;
    }
  }

  Future<bool> isContact(String currentUid, String contactUid) async {
    return _userRepository.isContact(currentUid, contactUid);
  }

  void clearSearch() {
    _searchResults = [];
    _isSearching = false;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading() {
    _status = ContactsStatus.loading;
    _errorMessage = null;
    notifyListeners();
  }

  void _setError(String message) {
    _status = ContactsStatus.error;
    _errorMessage = message;
    notifyListeners();
  }
}
