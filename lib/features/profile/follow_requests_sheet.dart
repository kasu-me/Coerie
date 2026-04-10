import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../data/models/user_model.dart';
import '../../shared/providers/misskey_api_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/follow_requests_badge_provider.dart';

class FollowRequestsSheet extends ConsumerStatefulWidget {
  final String profileOwnerId;
  final VoidCallback? onChanged;
  const FollowRequestsSheet({
    required this.profileOwnerId,
    this.onChanged,
    Key? key,
  }) : super(key: key);

  @override
  ConsumerState<FollowRequestsSheet> createState() =>
      _FollowRequestsSheetState();
}

class _FollowRequestsSheetState extends ConsumerState<FollowRequestsSheet> {
  List<UserModel> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) {
      setState(() {
        _isLoading = false;
        _requests = [];
      });
      return;
    }
    try {
      final list = await api.getFollowRequests();
      if (!mounted) return;
      setState(() {
        _requests = list;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _requests = [];
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _accept(UserModel u, int index) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;
    try {
      await api.acceptFollowRequest(u.id);
      setState(() => _requests.removeAt(index));
      widget.onChanged?.call();
      ref.invalidate(followRequestsBadgeProvider(widget.profileOwnerId));
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('フォローを許可しました')));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作に失敗しました')));
    }
  }

  Future<void> _reject(UserModel u, int index) async {
    final api = ref.read(misskeyApiProvider);
    if (api == null) return;

    final settings = ref.read(settingsProvider);
    if (settings.confirmDestructive) {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('フォローリクエストを拒否'),
              content: const Text('このフォローリクエストを拒否してもよろしいですか？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('拒否'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }

    try {
      await api.rejectFollowRequest(u.id);
      setState(() => _requests.removeAt(index));
      widget.onChanged?.call();
      ref.invalidate(followRequestsBadgeProvider(widget.profileOwnerId));
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('フォローを拒否しました')));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作に失敗しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (_, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'フォローリクエスト',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _requests.isEmpty
                  ? const Center(child: Text('フォローリクエストはありません'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _requests.length,
                      itemBuilder: (context, i) {
                        final u = _requests[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: u.avatarUrl != null
                                ? CachedNetworkImageProvider(u.avatarUrl!)
                                : null,
                            child: u.avatarUrl == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Text(
                            u.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(u.acct),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FilledButton(
                                onPressed: () => _accept(u, i),
                                child: const Text('許可'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: () => _reject(u, i),
                                child: const Text('拒否'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
