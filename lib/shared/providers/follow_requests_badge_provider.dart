import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'misskey_api_provider.dart';
import '../../data/remote/misskey_api.dart';

class _FollowRequestsBadgeNotifier extends StateNotifier<int> {
  final Ref _ref;
  _FollowRequestsBadgeNotifier(this._ref, String accountId) : super(0) {
    _ref.listen<MisskeyApi?>(misskeyApiProvider, (prev, next) {
      if (next != null) refreshFromApi();
    });
    _init();
  }

  Future<void> _init() async {
    await refreshFromApi();
  }

  Future<void> refreshFromApi() async {
    final api = _ref.read(misskeyApiProvider);
    if (api == null) {
      state = 0;
      return;
    }
    try {
      final list = await api.getFollowRequests();
      state = list.length;
    } catch (_) {
      // ignore errors and keep previous state
    }
  }

  /// Clear the badge locally.
  void clear() {
    state = 0;
  }
}

final followRequestsBadgeProvider = StateNotifierProvider.autoDispose
    .family<_FollowRequestsBadgeNotifier, int, String>((ref, accountId) {
      return _FollowRequestsBadgeNotifier(ref, accountId);
    });
