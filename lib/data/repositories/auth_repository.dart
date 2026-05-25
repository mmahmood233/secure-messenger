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
        throw const AuthException(
          'Account created. Please verify your email, then sign in.',
        );
      }

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
        await updateOnlineStatus(uid, false);
      }
      await _client.auth.signOut();
    } catch (_) {
      throw const AuthException('Sign out failed.');
    }
  }

  Future<UserModel?> getCurrentUserProfile() async {
    try {
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
    await _client.from('profiles').update({
      'is_online': isOnline,
      'last_seen': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', uid);
  }

  Future<UserModel> _ensurePublicKey(UserModel user) async {
    final publicKey = await _encryptionService.ensureIdentityKeyPair();
    if (user.publicKey == publicKey) return user;
    await _client
        .from('profiles')
        .update({'public_key': publicKey}).eq('id', user.uid);
    return user.copyWith(publicKey: publicKey);
  }
}
