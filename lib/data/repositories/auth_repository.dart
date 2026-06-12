// Authentication repository.
//
// This is the backend-facing part of login/signup. Screens and providers do not
// call Supabase Auth directly; they call this repository instead.
//
// Responsibilities:
// - Create and sign in Supabase Auth users.
// - Create/load the matching row in the profiles table.
// - Update online status when users sign in/out.
// - Make sure every user has an RSA public key for secret chats.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:secure_messenger/core/errors/app_exception.dart';
import 'package:secure_messenger/core/services/encryption_service.dart';
import 'package:secure_messenger/data/models/user_model.dart';

class AuthRepository {
  final supabase.SupabaseClient _client;
  final EncryptionService _encryptionService;

  AuthRepository(this._client, this._encryptionService);

  supabase.User? get currentUser => _client.auth.currentUser;
  Stream<supabase.AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;

  Future<UserModel> signUp({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    try {
      // Check username first because Supabase Auth only knows about email.
      // Usernames are stored lowercase so searching and duplicate checks are
      // consistent.
      final existing = await _client
          .from('profiles')
          .select('id')
          .eq('username', username.toLowerCase())
          .maybeSingle();

      if (existing != null) {
        throw const AuthException('Username is already taken.');
      }

      final response = await _client.auth.signUp(
        email: email,
        password: password,
      );
      final authUser = response.user;
      if (authUser == null) {
        // This can happen when email confirmation is required. The account may
        // exist, but the app cannot create a profile until a user id is present.
        throw const AuthException(
          'Account created. Please verify your email, then sign in.',
        );
      }

      // Create the local RSA identity key pair now. The profile stores only the
      // public key; the private key stays on this device.
      final publicKey = await _encryptionService.ensureIdentityKeyPair();
      final user = UserModel(
        uid: authUser.id,
        email: email,
        username: username.toLowerCase(),
        displayName: displayName,
        publicKey: publicKey,
        isOnline: true,
        createdAt: DateTime.now(),
      );

      await _client.from('profiles').upsert(user.toMap());
      return user;
    } on supabase.AuthException catch (e) {
      throw AuthException(mapAuthError(e.message), code: e.statusCode);
    } on AppException {
      rethrow;
    } catch (e) {
      throw AuthException('Sign up failed. Please try again. $e');
    }
  }

  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final authUser = response.user;
      if (authUser == null) {
        throw const AuthException('Invalid credentials.');
      }

      await updateOnlineStatus(authUser.id, true);
      final profile = await getCurrentUserProfile();
      if (profile == null) {
        throw const AuthException('User profile not found.');
      }
      // If an older profile or a profile created on another device has no local
      // public key, create/update it so secret chat setup can work.
      return _ensurePublicKey(profile);
    } on supabase.AuthException catch (e) {
      throw AuthException(mapAuthError(e.message), code: e.statusCode);
    } on AppException {
      rethrow;
    } catch (e) {
      throw AuthException('Sign in failed. Please try again. $e');
    }
  }

  Future<void> signOut() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid != null) {
        // Store presence data before ending the Supabase session.
        await updateOnlineStatus(uid, false);
      }
      await _client.auth.signOut();
    } catch (_) {
      throw const AuthException('Sign out failed.');
    }
  }

  Future<UserModel?> getCurrentUserProfile() async {
    try {
      // The current Supabase auth user id is the primary key in profiles.
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;

      final data =
          await _client.from('profiles').select().eq('id', uid).maybeSingle();
      if (data == null) return null;
      return UserModel.fromSupabase(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateOnlineStatus(String uid, bool isOnline) async {
    // Other users can display this as an online dot or last-seen status.
    await _client.from('profiles').update({
      'is_online': isOnline,
      'last_seen': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', uid);
  }

  Future<UserModel> _ensurePublicKey(UserModel user) async {
    // Secret chat invitation requires every participant to have a public key.
    // If the stored profile key differs from this device's key, update Supabase.
    final publicKey = await _encryptionService.ensureIdentityKeyPair();
    if (user.publicKey == publicKey) return user;
    await _client
        .from('profiles')
        .update({'public_key': publicKey}).eq('id', user.uid);
    return user.copyWith(publicKey: publicKey);
  }
}
