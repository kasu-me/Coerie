import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/providers/account_visibility_provider.dart';
import '../../../shared/providers/settings_provider.dart';
import '../../../shared/utils/visibility_utils.dart';

const List<String> _renoteVisibilityChoices = [
  AppConstants.visibilityPublic,
  AppConstants.visibilityHome,
  AppConstants.visibilityFollowers,
];

const Map<String, String> _renoteVisibilityShortLabels = {
  AppConstants.visibilityPublic: '全体',
  AppConstants.visibilityHome: 'ホーム',
  AppConstants.visibilityFollowers: 'フォロワー',
};

/// [accountId] のアカウントでリノートするときの既定の公開範囲。
///
/// 直前の投稿が「ユーザー指定」だと選択肢に無いため、意図せず公開範囲が
/// 広がらないよう選択肢の中で最も狭いフォロワー限定に寄せる。
/// 選択 UI を出さずにリノートする場合も同じ値を使い、UI の有無で結果が変わらないようにする。
String defaultRenoteVisibility(WidgetRef ref, String accountId) {
  final setting = ref.read(settingsProvider).renoteVisibility;
  final visibility = setting == AppConstants.renoteVisibilitySameAsLastPost
      ? ref.read(accountVisibilityProvider(accountId))
      : setting;
  return _renoteVisibilityChoices.contains(visibility)
      ? visibility
      : AppConstants.visibilityFollowers;
}

/// リノートの公開範囲を「全体/ホーム/フォロワー」から選ぶボタン群。
/// [onChanged] が null のときは操作不可にする。
class RenoteVisibilitySelector extends StatelessWidget {
  final String value;
  final ValueChanged<String>? onChanged;

  const RenoteVisibilitySelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return SegmentedButton<String>(
      // アイコンを文字の横に置くと、ダイアログやシートの幅では一般的な端末でも
      // 「フォロワー」が折り返すため、上に置いて横幅を文字だけに使う。
      // それでも収まらない狭い端末・大きな文字サイズ設定では、折り返す代わりに
      // FittedBox で縮小する。セグメント自体を縦に並べると枠の形が崩れるため採らない。
      segments: [
        for (final v in _renoteVisibilityChoices)
          ButtonSegment(
            value: v,
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(visibilityIcon(v)),
                    Text(
                      _renoteVisibilityShortLabels[v]!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: onChanged == null ? null : (s) => onChanged(s.first),
    );
  }
}

/// リノートの確認ダイアログを表示し、選ばれた公開範囲を返す。キャンセル時は null。
///
/// 汎用の confirmAction に公開範囲の引数を足さず専用にしているのは、
/// 他の確認ダイアログには無関係な選択 UI の分岐を持ち込まないため。
/// 設定「破壊的操作の前に確認する」がオフの場合は confirmAction と同様にダイアログを出さず、
/// 既定の公開範囲を即座に返す。
Future<String?> confirmRenote(
  BuildContext context,
  WidgetRef ref, {
  required String accountId,
}) async {
  final initial = defaultRenoteVisibility(ref, accountId);
  if (!ref.read(settingsProvider).confirmDestructive) return initial;
  if (!context.mounted) return null;

  return showDialog<String>(
    context: context,
    builder: (_) => _RenoteConfirmDialog(initial: initial),
  );
}

class _RenoteConfirmDialog extends StatefulWidget {
  final String initial;

  const _RenoteConfirmDialog({required this.initial});

  @override
  State<_RenoteConfirmDialog> createState() => _RenoteConfirmDialogState();
}

class _RenoteConfirmDialogState extends State<_RenoteConfirmDialog> {
  late String _visibility = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      // 既定の左右余白 40 では幅 360dp 程度の端末で公開範囲のラベルが縮小されるため狭める。
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('リノート'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('このノートをリノートしますか？'),
          const SizedBox(height: 16),
          Text('公開範囲', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          RenoteVisibilitySelector(
            value: _visibility,
            onChanged: (v) => setState(() => _visibility = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _visibility),
          child: const Text('リノート'),
        ),
      ],
    );
  }
}
