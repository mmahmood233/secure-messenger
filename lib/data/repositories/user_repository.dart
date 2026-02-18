import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:secure_messenger/core/constants/app_constants.dart';
import 'package:secure_messenger/core/errors/app_exception.dart';
import 'package:secure_messenger/data/models/user_model.dart';

class UserRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  UserRepository(this._firestore, this._storage);

  Future<UserModel?> getUserById(String uid) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .get();
      if (!doc.exists) return null;
      return UserModel.fromDoc(doc);
    } catch (e) {
      throw NetworkException('Failed to fetch user: $e');
    }
  }

  Stream<UserModel?> watchUser(String uid) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? UserModel.fromDoc(doc) : null);
  }

  Future<List<UserModel>> searchUsers(String query) async {
    try {
      final lowerQuery = query.toLowerCase();
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .where('username', isGreaterThanOrEqualTo: lowerQuery)
          .where('username', isLessThanOrEqualTo: '$lowerQuery\uf8ff')
          .limit(20)
          .get();

      return snapshot.docs.map((doc) => UserModel.fromDoc(doc)).toList();
    } catch (e) {
      throw NetworkException('Search failed: $e');
    }
  }

  Future<UserModel?> getUserByUsername(String username) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .where('username', isEqualTo: username.toLowerCase())
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) return null;
      return UserModel.fromDoc(snapshot.docs.first);
    } catch (e) {
      throw NetworkException('Failed to find user: $e');
    }
  }

  Future<void> updateProfile({
    required String uid,
    String? displayName,
    String? bio,
    String? phoneNumber,
    String? username,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (displayName != null) updates['displayName'] = displayName;
      if (bio != null) updates['bio'] = bio;
      if (phoneNumber != null) updates['phoneNumber'] = phoneNumber;
      if (username != null) {
        final existing = await _firestore
            .collection(AppConstants.usersCollection)
            .where('username', isEqualTo: username.toLowerCase())
            .limit(1)
            .get();
        if (existing.docs.isNotEmpty && existing.docs.first.id != uid) {
          throw const AppException('Username is already taken.');
        }
        updates['username'] = username.toLowerCase();
      }
      if (updates.isEmpty) return;
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update(updates);
    } on AppException {
      rethrow;
    } catch (e) {
      throw NetworkException('Failed to update profile: $e');
    }
  }

  Future<String> uploadProfilePhoto(String uid, File imageFile) async {
    try {
      final ref = _storage.ref().child('profile_photos/$uid.jpg');
      final uploadTask = await ref.putFile(
        imageFile,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await uploadTask.ref.getDownloadURL();
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update({'photoUrl': url});
      return url;
    } catch (e) {
      throw StorageException('Failed to upload photo: $e');
    }
  }

  Future<List<UserModel>> getContacts(String uid) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .collection(AppConstants.contactsCollection)
          .get();

      final contactIds = snapshot.docs.map((d) => d.id).toList();
      if (contactIds.isEmpty) return [];

      final users = await Future.wait(
        contactIds.map((id) => getUserById(id)),
      );
      return users.whereType<UserModel>().toList();
    } catch (e) {
      throw NetworkException('Failed to load contacts: $e');
    }
  }

  Future<void> addContact(String currentUid, String contactUid) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(currentUid)
          .collection(AppConstants.contactsCollection)
          .doc(contactUid)
          .set({'addedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      throw NetworkException('Failed to add contact: $e');
    }
  }

  Future<bool> isContact(String currentUid, String contactUid) async {
    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(currentUid)
        .collection(AppConstants.contactsCollection)
        .doc(contactUid)
        .get();
    return doc.exists;
  }
}
