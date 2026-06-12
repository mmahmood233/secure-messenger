// Temporary UI model for a media upload that has started locally but has not
// finished saving to Supabase yet.
import 'dart:io';

class PendingMediaUpload {
  final String id;
  final File file;
  final String type;
  final DateTime createdAt;

  const PendingMediaUpload({
    required this.id,
    required this.file,
    required this.type,
    required this.createdAt,
  });
}
