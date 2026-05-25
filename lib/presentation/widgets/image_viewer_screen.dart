import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:secure_messenger/core/theme/app_theme.dart';

class ImageViewerScreen extends StatelessWidget {
  final String imageUrl;
  final Uint8List? imageBytes;
  final String? heroTag;

  const ImageViewerScreen({super.key, required this.imageUrl, this.heroTag})
      : imageBytes = null;

  const ImageViewerScreen.bytes({
    super.key,
    required this.imageBytes,
    this.heroTag,
  }) : imageUrl = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: PhotoView(
        imageProvider: imageBytes != null
            ? MemoryImage(imageBytes!)
            : NetworkImage(imageUrl),
        heroAttributes:
            heroTag != null ? PhotoViewHeroAttributes(tag: heroTag!) : null,
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 3,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        loadingBuilder: (_, __) => const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
        ),
      ),
    );
  }
}
