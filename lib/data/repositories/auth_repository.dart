import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:secure_messenger/core/constants/app_constants.dart';
import 'package:secure_messenger/core/errors/app_exception.dart';
import 'package:secure_messenger/data/models/user_model.dart';

class AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthRepository(this._auth, this._firestore);

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserModel> signUp({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    try {
      final existing = await _firestore
          .collection(AppConstants.usersCollection)
          .where('username', isEqualTo: username.toLowerCase())
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        throw const AuthException('Username is already taken.');
      }

      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = UserModel(
        uid: credential.user!.uid,
        email: email,
        username: username.toLowerCase(),
        displayName: displayName,
        isOnline: true,
        createdAt: DateTime.now(),
      );

      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .set(user.toMap());

      return user;
    } on FirebaseAuthException catch (e) {
      throw AuthException(mapFirebaseAuthError(e.code), code: e.code);
    } on AppException {
      rethrow;
    } catch (e) {
      throw AuthException('Sign up failed. Please try again.');
    }
  }

  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      await _updateOnlineStatus(credential.user!.uid, true);

      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(credential.user!.uid)
          .get();

      if (!doc.exists) {
        throw const AuthException('User profile not found.');
      }

      return UserModel.fromDoc(doc);
    } on FirebaseAuthException catch (e) {
      throw AuthException(mapFirebaseAuthError(e.code), code: e.code);
    } on AppException {
      rethrow;
    } catch (e) {
      throw AuthException('Sign in failed. Please try again.');
    }
  }

  Future<void> signOut() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        await _updateOnlineStatus(uid, false);
      }
      await _auth.signOut();
    } catch (e) {
      throw AuthException('Sign out failed.');
    }
  }

  Future<UserModel?> getCurrentUserProfile() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return null;

      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .get();

      if (!doc.exists) return null;
      return UserModel.fromDoc(doc);
    } catch (e) {
      return null;
    }
  }

  Future<void> _updateOnlineStatus(String uid, bool isOnline) async {
    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .update({
      'isOnline': isOnline,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }
}
