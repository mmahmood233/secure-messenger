import 'dart:io';

import 'package:flutter/material.dart';
import 'package:secure_messenger/core/constants/app_constants.dart';
import 'package:secure_messenger/core/theme/app_theme.dart';
import 'package:video_player/video_player.dart';

class MediaSendPreviewScreen extends StatefulWidget {
  final File file;
  final String type;
  final Color accentColor;

  const MediaSendPreviewScreen({
    super.key,
    required this.file,
    required this.type,
    this.accentColor = AppTheme.primaryColor,
  });

  @override
  State<MediaSendPreviewScreen> createState() => _MediaSendPreviewScreenState();
}

class _MediaSendPreviewScreenState extends State<MediaSendPreviewScreen> {
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.type == AppConstants.videoMessage) {
      _videoController = VideoPlayerController.file(widget.file)
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() => _videoReady = true);
          _videoController!
            ..setLooping(true)
            ..play();
        }).catchError((_) {
          if (mounted) setState(() => _videoFailed = true);
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (widget.type) {
      AppConstants.imageMessage => 'Photo',
      AppConstants.videoMessage => 'Video',
      AppConstants.audioMessage => 'Audio',
      _ => 'Media',
    };

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(label),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _PreviewBody(
                    file: widget.file,
                    type: widget.type,
                    controller: _videoController,
                    videoReady: _videoReady,
                    videoFailed: _videoFailed,
                    accentColor: widget.accentColor,
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: AppTheme.surfaceColor,
                border: Border(top: BorderSide(color: AppTheme.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _fileName(widget.file),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton(
                    heroTag: null,
                    mini: true,
                    backgroundColor: widget.accentColor,
                    foregroundColor: Colors.white,
                    onPressed: () => Navigator.pop(context, true),
                    child: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fileName(File file) {
    final normalized = file.path.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    return name.isEmpty ? 'Selected media' : name;
  }
}

class _PreviewBody extends StatelessWidget {
  final File file;
  final String type;
  final VideoPlayerController? controller;
  final bool videoReady;
  final bool videoFailed;
  final Color accentColor;

  const _PreviewBody({
    required this.file,
    required this.type,
    required this.controller,
    required this.videoReady,
    required this.videoFailed,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    if (type == AppConstants.imageMessage) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    _ErrorPreview(accentColor: accentColor),
              ),
            ),
          );
        },
      );
    }

    if (type == AppConstants.videoMessage) {
      if (videoFailed) return _ErrorPreview(accentColor: accentColor);
      if (!videoReady || controller == null) {
        return CircularProgressIndicator(color: accentColor);
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final aspect = controller!.value.aspectRatio;
          final maxWidth = constraints.maxWidth;
          final maxHeight = constraints.maxHeight;
          var width = maxWidth;
          var height = width / aspect;
          if (height > maxHeight) {
            height = maxHeight;
            width = height * aspect;
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(controller!),
                  const Icon(
                    Icons.play_circle_fill,
                    color: Colors.white,
                    size: 64,
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.audiotrack, color: accentColor, size: 56),
          const SizedBox(height: 12),
          const Text(
            'Audio file ready to send',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPreview extends StatelessWidget {
  final Color accentColor;

  const _ErrorPreview({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, color: accentColor, size: 56),
        const SizedBox(height: 12),
        const Text(
          'Unable to preview this file',
          style: TextStyle(color: Colors.white70),
        ),
      ],
    );
  }
}
