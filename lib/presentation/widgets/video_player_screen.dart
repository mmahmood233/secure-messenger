import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:secure_messenger/core/theme/app_theme.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerScreen({super.key, required this.videoUrl});

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
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
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
      body: Center(
        child: _hasError
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.white54, size: 64),
                  SizedBox(height: 16),
                  Text('Failed to load video',
                      style: TextStyle(color: Colors.white54)),
                ],
              )
            : !_isInitialized
                ? const CircularProgressIndicator(color: AppTheme.primaryColor)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      ),
                      const SizedBox(height: 16),
                      VideoProgressIndicator(
                        _controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: AppTheme.primaryColor,
                          bufferedColor: Colors.white24,
                          backgroundColor: Colors.white12,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
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
                                  pos - const Duration(seconds: 10));
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
                                  pos + const Duration(seconds: 10));
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }
}
