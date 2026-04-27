import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/image_compression_level.dart';
import '../../shared/providers/settings_provider.dart';

class ImagePostingSettingsScreen extends ConsumerWidget {
  const ImagePostingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('画像投稿')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'デフォルトの画像圧縮率',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 24, right: 16, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    'jpeg ・ png のみ圧縮の対象です。Compose画面から個別に変更することもできます。',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                RadioGroup<ImageCompressionLevel>(
                  groupValue: settings.defaultImageCompressionLevel,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setDefaultImageCompressionLevel(v!),
                  child: Column(
                    children: ImageCompressionLevel.values
                        .map(
                          (level) => RadioListTile<ImageCompressionLevel>(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(level.label),
                            subtitle: level == ImageCompressionLevel.none
                                ? const Text('そのままアップロード')
                                : Text(
                                    '最大 ${level.maxDimension}px / JPEG品質 ${level.quality}%',
                                  ),
                            value: level,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
