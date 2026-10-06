import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/api_error_message.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/note_model.dart';
import '../../../data/remote/misskey_api.dart';
import '../../../shared/widgets/user_avatar.dart';
import 'renote_visibility.dart';

const String _deniedMessage = '選択したアカウントはこのノートをリノートする権限がありません。';
const String _temporaryFailureMessage = '一時的に通信に失敗しました。時間をおくと回復する可能性があります。';

/// リノートするアカウント側のサーバー、または投稿者側の設定によって拒否されたことを示すエラーコード。
///
/// ap/show は投稿元サーバーへの取得失敗（相手側のブロック・取得制限・障害）を
/// すべて REQUEST_FAILED にまとめて返すため、相手側のブロックはここでは判別できず
/// 一時的な失敗として案内される。
const Set<String> _deniedCodes = {
  // ap/show: リノートするアカウント側のサーバーが投稿元との連合を許可していない
  'FEDERATION_NOT_ALLOWED',
  // ap/show: 取得はできたがノートとして取り込まれなかった
  'NO_SUCH_OBJECT',
  // notes/create
  'CANNOT_RENOTE_DUE_TO_VISIBILITY',
  'YOU_HAVE_BEEN_BLOCKED',
};

/// [note] をアクティブアカウント以外の [accounts] のいずれかでリノートするシート。
///
/// リノートに成功したらそのアカウントを返して閉じる。失敗時はシート内に
/// エラーを表示して開いたままにし、アカウントや公開範囲を変えて再試行できるようにする
/// （モーダルの下に SnackBar を出してもシートに隠れて見えないため）。
class RenoteWithOtherAccountSheet extends ConsumerStatefulWidget {
  final NoteModel note;

  /// ノートを表示しているアカウントのホスト。ノートの URI 組み立てに使う。
  final String activeHost;
  final List<AccountModel> accounts;

  const RenoteWithOtherAccountSheet({
    super.key,
    required this.note,
    required this.activeHost,
    required this.accounts,
  });

  @override
  ConsumerState<RenoteWithOtherAccountSheet> createState() =>
      _RenoteWithOtherAccountSheetState();
}

class _RenoteWithOtherAccountSheetState
    extends ConsumerState<RenoteWithOtherAccountSheet> {
  late AccountModel _account;
  late String _visibility;

  /// 公開範囲を手動で選んだか。選んでいない間は、アカウントを切り替えるたびに
  /// そのアカウントの既定値（「直前の投稿と同じ」設定ならアカウントごとに異なる）へ追従させる。
  bool _visibilityTouched = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _account = widget.accounts.first;
    _visibility = defaultRenoteVisibility(ref, _account.id);
  }

  String get _originHost => widget.note.user.host.isNotEmpty
      ? widget.note.user.host
      : widget.activeHost;

  /// [account] のサーバーがこのノートを取得できる見込みがあるか。
  ///
  /// 他サーバーのノートは投稿元へ ActivityPub で取りに行くが、フォロワー限定・
  /// 連合なしのノートは投稿元が外部に返さない。その失敗は ap/show では
  /// REQUEST_FAILED になり一時的な障害と区別できないため、送信前にはじく。
  bool _isReachableFrom(AccountModel account) {
    final note = widget.note;
    if (note.visibility == AppConstants.visibilitySpecified) return false;
    // 投稿元と同じサーバーなら取得は不要。リノートの可否はサーバーの判定に任せる。
    if (account.host == _originHost) return true;
    return !note.localOnly &&
        note.visibility != AppConstants.visibilityFollowers;
  }

  String _errorMessageOf(Object error) {
    final code = apiErrorCode(error);
    if (_deniedCodes.contains(code)) return _deniedMessage;
    // トークン失効・凍結・権限不足は時間をおいても解決しないため、
    // 一時的な失敗に丸めず原因を案内する。
    if (code == 'AUTHENTICATION_FAILED' ||
        code == 'YOUR_ACCOUNT_SUSPENDED' ||
        isPermissionError(error)) {
      return apiErrorMessage(error);
    }
    return _temporaryFailureMessage;
  }

  Future<void> _submit() async {
    final account = _account;
    if (!_isReachableFrom(account)) {
      setState(() => _error = _deniedMessage);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final api = MisskeyApi(host: account.host, token: account.token);
    try {
      final String renoteId;
      if (account.host == widget.activeHost) {
        // 同じサーバーならノートIDが共通なので、レート制限の厳しい ap/show を経由しない。
        renoteId = widget.note.id;
      } else {
        // 表示中サーバーのローカルノートは uri が null のため、表示中サーバー上の URL を使う。
        final uri =
            widget.note.uri ??
            'https://${widget.activeHost}/notes/${widget.note.id}';
        final resolved = await api.resolveNoteByUri(uri);
        if (resolved == null) {
          if (mounted) {
            setState(() {
              _submitting = false;
              _error = _deniedMessage;
            });
          }
          return;
        }
        renoteId = resolved.id;
      }
      await api.renote(renoteId, visibility: _visibility);
      if (mounted) Navigator.pop(context, account);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = _errorMessageOf(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '他のアカウントでリノート',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('アカウント', style: theme.textTheme.labelLarge),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final a in widget.accounts)
                  ListTile(
                    leading: UserAvatar(avatarUrl: a.avatarUrl),
                    title: Text(a.name),
                    subtitle: Text(a.acct),
                    trailing: a.id == _account.id
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                    enabled: !_submitting,
                    onTap: () => setState(() {
                      _account = a;
                      _error = null;
                      if (!_visibilityTouched) {
                        _visibility = defaultRenoteVisibility(ref, a.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('公開範囲', style: theme.textTheme.labelLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RenoteVisibilitySelector(
              value: _visibility,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() {
                      _visibility = v;
                      _visibilityTouched = true;
                    }),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.repeat),
              label: const Text('リノート'),
            ),
          ),
        ],
      ),
    );
  }
}
