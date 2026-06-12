// Chat bubble displayed while a media file is uploading.
import 'package:flutter/material.dart';
import 'package:secure_messenger/core/constants/app_constants.dart';
import 'package:secure_messenger/data/models/pending_media_upload.dart';

class PendingMediaBubble extends StatelessWidget {
  final PendingMediaUpload upload;
  final Color accentColor;

  const PendingMediaBubble({
    super.key,
    required this.upload,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.68;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth.clamp(180.0, 300.0)),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(6),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PendingMediaPreview(upload: upload),
              const SizedBox(height: 6),
              const _UploadStatusRow(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingMediaPreview extends StatelessWidget {
  final PendingMediaUpload upload;

  const _PendingMediaPreview({required this.upload});

  @override
  Widget build(BuildContext context) {
    if (upload.type == AppConstants.imageMessage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Image.file(
            upload.file,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _FallbackPreview(
              icon: Icons.image_not_supported_outlined,
              label: 'Photo',
            ),
          ),
        ),
      );
    }

    if (upload.type == AppConstants.videoMessage) {
      return const _FallbackPreview(
        icon: Icons.play_circle_fill_rounded,
        label: 'Video',
        wide: true,
      );
    }

    return _FallbackPreview(
      icon: Icons.graphic_eq_rounded,
      label: _fileName(upload.file.path),
    );
  }

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    return name.isEmpty ? 'Audio' : name;
  }
}

class _FallbackPreview extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool wide;

  const _FallbackPreview({
    required this.icon,
    required this.label,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: wide ? 136 : 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.22),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: wide ? 44 : 26),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadStatusRow extends StatelessWidget {
  const _UploadStatusRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Sending...',
          style: TextStyle(
            color: Colors.white.withOpacity(0.84),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
