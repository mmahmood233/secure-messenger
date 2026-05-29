import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' hide StorageException;
import 'package:secure_messenger/core/errors/app_exception.dart';
import 'package:secure_messenger/data/models/user_model.dart';

class UserRepository {
  final SupabaseClient _client;

  UserRepository(this._client);

  Future<UserModel?> getUserById(String uid) async {
    try {
      final data =
          await _client.from('profiles').select().eq('id', uid).maybeSingle();
      if (data == null) return null;
      return UserModel.fromSupabase(data);
    } catch (e) {
      throw NetworkException('Failed to fetch user: $e');
    }
  }

  Stream<UserModel?> watchUser(String uid) {
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', uid)
        .map(
            (rows) => rows.isEmpty ? null : UserModel.fromSupabase(rows.first));
  }

  Future<List<UserModel>> searchUsers(String query) async {
    try {
      final lowerQuery = query.toLowerCase();
      final rows = await _client
          .from('profiles')
          .select()
          .ilike('username', '$lowerQuery%')
          .limit(20);
      return rows.map<UserModel>(UserModel.fromSupabase).toList();
    } catch (e) {
      throw NetworkException('Search failed: $e');
    }
  }

  Future<UserModel?> getUserByUsername(String username) async {
    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('username', username.toLowerCase())
          .maybeSingle();
      if (data == null) return null;
      return UserModel.fromSupabase(data);
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
      if (displayName != null) updates['display_name'] = displayName;
      if (bio != null) updates['bio'] = bio;
      if (phoneNumber != null) updates['phone_number'] = phoneNumber;
      if (username != null) {
        final existing = await _client
            .from('profiles')
            .select('id')
            .eq('username', username.toLowerCase())
            .maybeSingle();
        if (existing != null && existing['id'] != uid) {
          throw const AppException('Username is already taken.');
        }
        updates['username'] = username.toLowerCase();
      }
      if (updates.isEmpty) return;
      await _client.from('profiles').update(updates).eq('id', uid);
    } on AppException {
      rethrow;
    } catch (e) {
      throw NetworkException('Failed to update profile: $e');
    }
  }

  Future<String> uploadProfilePhoto(String uid, File imageFile) async {
    try {
      final path = '$uid.jpg';
      await _client.storage.from('profile-photos').upload(
            path,
            imageFile,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      final url = _client.storage.from('profile-photos').getPublicUrl(path);
      await _client.from('profiles').update({'photo_url': url}).eq('id', uid);
      return url;
    } catch (e) {
      throw StorageException('Failed to upload photo: $e');
    }
  }

  Future<List<UserModel>> getContacts(String uid) async {
    try {
      final rows = await _client
          .from('contacts')
          .select('contact:profiles!contacts_contact_id_fkey(*)')
          .eq('owner_id', uid);
      return rows
          .map<UserModel?>((row) {
            final contact = row['contact'];
            if (contact is! Map<String, dynamic>) return null;
            return UserModel.fromSupabase(contact);
          })
          .whereType<UserModel>()
          .toList();
    } catch (e) {
      throw NetworkException('Failed to load contacts: $e');
    }
  }

  Future<void> addContact(String currentUid, String contactUid) async {
    try {
      await _client.rpc('add_contact', params: {'contact_uid': contactUid});
    } catch (e) {
      throw NetworkException('Failed to add contact: $e');
    }
  }

  Future<bool> isContact(String currentUid, String contactUid) async {
    final data = await _client
        .from('contacts')
        .select('contact_id')
        .eq('owner_id', currentUid)
        .eq('contact_id', contactUid)
        .maybeSingle();
    return data != null;
  }

  Future<void> updateOnlineStatus(String uid, bool isOnline) async {
    await _client.from('profiles').update({
      'is_online': isOnline,
      'last_seen': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', uid);
  }
}
