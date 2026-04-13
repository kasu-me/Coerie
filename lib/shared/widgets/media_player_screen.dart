import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

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
    final theme = Theme.of(context);
    final popupBg = theme.colorScheme.surface;
    final popupOn = theme.colorScheme.onSurface;

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
        actions: [
          PopupMenuButton<String>(
            color: popupBg,
            icon: const Icon(Icons.more_vert, color: Colors.white),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 8,
            offset: const Offset(0, 8),
            onSelected: (v) {
              if (v == 'download') _downloadMedia();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, color: popupOn, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'ダウンロード',
                      style: TextStyle(color: popupOn, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
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

  Future<void> _downloadMedia() async {
    final url = widget.url;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('ダウンロードを開始します...')));
    try {
      final dio = Dio();
      String filename = Uri.tryParse(url)?.pathSegments.last ?? widget.title;

      Directory? dir;
      try {
        if (Platform.isAndroid) {
          final dirs = await getExternalStorageDirectories(
            type: StorageDirectory.downloads,
          );
          if (dirs != null && dirs.isNotEmpty) {
            dir = dirs.first;
          } else {
            dir = await getExternalStorageDirectory();
          }
        } else if (Platform.isIOS) {
          dir = await getApplicationDocumentsDirectory();
        } else {
          dir = await getDownloadsDirectory();
          dir ??= await getApplicationDocumentsDirectory();
        }
      } catch (_) {
        dir = await getApplicationDocumentsDirectory();
      }

      final saveFile = File('${dir!.path}${Platform.pathSeparator}$filename');
      final tempFile = File('${saveFile.path}.part');

      await dio.download(url, tempFile.path);
      if (await tempFile.exists()) {
        await tempFile.rename(saveFile.path);
      }

      messenger.showSnackBar(
        SnackBar(content: Text('保存しました: ${saveFile.path}')),
      );
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('ダウンロードに失敗しました')));
    }
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
