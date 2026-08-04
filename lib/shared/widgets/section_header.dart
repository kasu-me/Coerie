import 'package:flutter/material.dart';

/// 設定系画面でセクションを区切る見出し。
///
/// 各画面で同名の private ウィジェットとして重複実装され、画面ごとに
/// スタイルがずれていたため共通化した。フォントサイズは直書きせず、
/// テーマ（Material Design 3）から解決する。
class SectionHeader extends StatelessWidget {
  final String title;

  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
