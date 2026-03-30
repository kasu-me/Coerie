import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 動画・音声を再生するフルスクリーンプレーヤー。
///
/// [isAudio] = true のとき音声専用UIを表示する。
class MediaPlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final bool isAudio;

  const MediaPlayerScreen({
    super.key,
    required this.url,
    required this.title,
    this.isAudio = false,
  });

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  late VideoPlayerController _vpc;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _vpc = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _vpc.initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _chewieController = ChewieController(
          videoPlayerController: _vpc,
          autoPlay: true,
          looping: false,
          // 音声の場合は縦長にならないよう固定比率
          aspectRatio: widget.isAudio ? 1.0 : _vpc.value.aspectRatio,
          // 音声の場合は映像エリアにアイコンを表示するため placeholder を使用
          placeholder: widget.isAudio
              ? _AudioBackground(title: widget.title)
              : null,
        );
      });
    });
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _vpc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _chewieController != null
          ? widget.isAudio
                ? _buildAudioPlayer()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: _vpc.value.aspectRatio,
                        child: Chewie(controller: _chewieController!),
                      ),
                    ],
                  )
          : const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }

  Widget _buildAudioPlayer() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.audiotrack, size: 96, color: Colors.white54),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            widget.title,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(height: 120, child: Chewie(controller: _chewieController!)),
      ],
    );
  }
}

class _AudioBackground extends StatelessWidget {
  final String title;
  const _AudioBackground({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Icon(Icons.audiotrack, size: 64, color: Colors.white24),
      ),
    );
  }
}
