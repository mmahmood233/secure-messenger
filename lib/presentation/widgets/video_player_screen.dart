import 'dart:io';

// Full-screen video player for chat media.
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:secure_messenger/core/theme/app_theme.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String? videoUrl;
  final File? file;
  final bool isAudio;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    this.isAudio = false,
  }) : file = null;

  const VideoPlayerScreen.file({
    super.key,
    required this.file,
    this.isAudio = false,
  }) : videoUrl = null;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.file != null
        ? VideoPlayerController.file(widget.file!)
        : VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl!))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _isInitialized = true);
          _controller.play();
        }
      }).catchError((_) {
        if (mounted) setState(() => _hasError = true);
      });
    _controller.setLooping(false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SizedBox.expand(
          child: _hasError
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          color: Colors.white54, size: 64),
                      SizedBox(height: 16),
                      Text(
                        'Failed to load video',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                )
              : !_isInitialized
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.primaryColor,
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: widget.isAudio
                                ? const Icon(Icons.audiotrack,
                                    color: Colors.white, size: 88)
                                : LayoutBuilder(
                                    builder: (context, constraints) {
                                      final aspect =
                                          _controller.value.aspectRatio;
                                      final maxWidth = constraints.maxWidth;
                                      final maxHeight = constraints.maxHeight;
                                      var width = maxWidth;
                                      var height = width / aspect;
                                      if (height > maxHeight) {
                                        height = maxHeight;
                                        width = height * aspect;
                                      }
                                      return SizedBox(
                                        width: width,
                                        height: height,
                                        child: VideoPlayer(_controller),
                                      );
                                    },
                                  ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                          child: VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: AppTheme.primaryColor,
                              bufferedColor: Colors.white24,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.replay_10,
                                  color: Colors.white, size: 32),
                              onPressed: () {
                                final pos = _controller.value.position;
                                _controller.seekTo(
                                  pos - const Duration(seconds: 10),
                                );
                              },
                            ),
                            const SizedBox(width: 16),
                            ValueListenableBuilder<VideoPlayerValue>(
                              valueListenable: _controller,
                              builder: (_, value, __) {
                                return IconButton(
                                  icon: Icon(
                                    value.isPlaying
                                        ? Icons.pause_circle_filled
                                        : Icons.play_circle_filled,
                                    color: Colors.white,
                                    size: 56,
                                  ),
                                  onPressed: () {
                                    value.isPlaying
                                        ? _controller.pause()
                                        : _controller.play();
                                  },
                                );
                              },
                            ),
                            const SizedBox(width: 16),
                            IconButton(
                              icon: const Icon(Icons.forward_10,
                                  color: Colors.white, size: 32),
                              onPressed: () {
                                final pos = _controller.value.position;
                                _controller.seekTo(
                                  pos + const Duration(seconds: 10),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
        ),
      ),
    );
  }
}
