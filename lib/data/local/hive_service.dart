import 'dart:io' show FileSystemException;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/draft_model.dart';
import '../models/account_model.dart';
import '../../core/constants/app_constants.dart';

/// 起動時のローカルストレージ復旧で accountsBox に発生した問題。
///
/// いずれもユーザーから見ると「何もしていないのにデータが消えた」状態なので、
/// UI 側で必ず理由を提示すること。
enum HiveStartupIssue {
  /// 保存データを読めなかったため破棄した。アカウントが失われ再ログインが必要。
  accountsReset,

  /// メモリ上だけで動作している。アプリは起動するが、この起動中に追加した
  /// アカウントは保存されない。
  ///
  /// **ディスク上のデータを温存したまま**メモリ上に落ちた場合を含み、その場合は
  /// 原因が解消すれば次回起動で元のデータに戻る。UI の文言は「データが消えた」と
  /// 断定せず、再起動で復帰しうる旨を伝えること。
  storageUnavailable,
}

class HiveService {
  HiveService._();

  static final Set<String> _resetBoxes = <String>{};
  static final Set<String> _volatileBoxes = <String>{};
  static bool _startupIssueConsumed = false;
  static bool _storageDirectoryAvailable = true;

  /// 中身を破棄して作り直したボックス名（[_openBoxSafely] の step 2）。
  ///
  /// [volatileBoxNames] とは排他。[consumeStartupIssue] を呼んでもクリアされない。
  static Set<String> get resetBoxNames => Set.unmodifiable(_resetBoxes);

  /// メモリ上のみで開いたボックス名（[_openBoxSafely] の step 3）。
  ///
  /// このボックスへの書き込みは **成功するが一切永続化されない**。
  /// 同一起動中は読み戻せてしまうため、保存できたように見える点に注意。
  /// [resetBoxNames] とは排他。
  static Set<String> get volatileBoxNames => Set.unmodifiable(_volatileBoxes);

  /// [boxName] が永続化されない状態（step 3 に落ちている）か。
  ///
  /// 保存操作のフィードバックを出す箇所は、これを見て文言を変えること。
  static bool isVolatile(String boxName) => _volatileBoxes.contains(boxName);

  /// 起動時に **accountsBox に** 発生した問題を取り出す。
  /// 一度取り出すとクリアされ、次回以降は null を返す。
  ///
  /// 対象を accountsBox に絞っているのは、この結果を表示するのがログイン画面
  /// だけであり、「アカウントが失われた」という文言と対象がずれないようにするため。
  /// draftsBox の問題は起動時には通知せず、step 3 のときだけ保存時に [isVolatile]
  /// で警告する（`compose_screen.dart` の `_saveDraft`）。
  ///
  /// 通知しないと決めた経緯と、方針を変える場合の手掛かりは
  /// `.claude/skills/hive-adapter-compat` の「意図的に見送っているもの」を参照。
  static HiveStartupIssue? consumeStartupIssue() {
    if (_startupIssueConsumed) return null;
    _startupIssueConsumed = true;

    if (_volatileBoxes.contains(AppConstants.accountsBox)) {
      return HiveStartupIssue.storageUnavailable;
    }
    if (_resetBoxes.contains(AppConstants.accountsBox)) {
      return HiveStartupIssue.accountsReset;
    }
    return null;
  }

  /// ボックスを開けなかったとき、中身を破棄してよい失敗か。
  ///
  /// **破棄はアクセストークンの消去を意味する**ので、原因を選ばずに実行しては
  /// いけない。ここに到達する失敗は実質2系統に分かれる。
  ///
  /// - **形式不整合**（`HiveError('Cannot read, unknown typeId')`、アダプターの
  ///   `RangeError` など）… ディスク上のデータは今後も読めないので破棄する。
  ///   未知の例外もこちら側に倒す（取りこぼすと step 2 が永久に動かず、
  ///   メモリ上で動き続けて復旧手段が無くなるため）。
  /// - **ファイルI/O・ロック失敗**（`FileSystemException`）… ストレージが一時的に
  ///   読めない、権限が無い等の**復旧可能**なケースなので破棄しない。破棄すると
  ///   一時的な失敗のたびにトークンが消え「起動するたびログアウトする」挙動になる。
  ///
  /// 分類の根拠（CRC 破損がここに来ない理由など）は
  /// `.claude/skills/hive-adapter-compat` の「復旧フォールバックの3段階」を参照。
  @visibleForTesting
  static bool shouldDiscardOnFailure(Object error) {
    // 保存先ディレクトリ自体が取れていない場合、ファイルには一切触れていない。
    // 破棄する対象も無く、データは無傷なので消してはいけない。
    if (!_storageDirectoryAvailable) return false;
    if (error is FileSystemException) return false;
    return true;
  }

  /// テストから復旧状態を差し込むための注入口。
  @visibleForTesting
  static void debugSetStartupState({
    Set<String> reset = const {},
    Set<String> volatile = const {},
    bool storageDirectoryAvailable = true,
  }) {
    _resetBoxes
      ..clear()
      ..addAll(reset);
    _volatileBoxes
      ..clear()
      ..addAll(volatile);
    _startupIssueConsumed = false;
    _storageDirectoryAvailable = storageDirectoryAvailable;
  }

  static Future<void> init() async {
    try {
      await Hive.initFlutter();
    } catch (e, stackTrace) {
      // path_provider が保存先ディレクトリを返せないケース。ここで投げると
      // main.dart が runApp に到達できないため、握って先へ進む。
      // 保存先が無い状態では各ボックスは step 3（メモリ上）に落ちる。
      _storageDirectoryAvailable = false;
      debugPrint('Hive: 初期化に失敗しました（メモリ上で動作します）: $e');
      debugPrintStack(stackTrace: stackTrace);
    }

    Hive.registerAdapter(DraftModelAdapter());
    Hive.registerAdapter(AccountModelAdapter());
    await _openBoxSafely<DraftModel>(AppConstants.draftsBox);
    await _openBoxSafely<AccountModel>(AppConstants.accountsBox);
  }

  /// ボックスを開く。**この関数は例外を投げない。**
  ///
  /// データ破損やアダプターの形式変更で読み取りに失敗すると、例外が [init] を
  /// 突き抜けて `runApp` に到達できず、アプリが起動不能になってしまう。
  /// それを避けるため、段階的に諦めながら「開いた状態」まで持っていく。
  ///
  /// 1. 通常どおり開く
  /// 2. 失敗したら中身を破棄して作り直す（[resetBoxNames] に記録）
  /// 3. それも失敗したらメモリ上だけで開く（[volatileBoxNames] に記録）
  ///
  /// ただし [shouldDiscardOnFailure] が false を返す失敗では **step 2 を飛ばして
  /// step 3 へ直行する**。この場合その起動中は保存できないが、原因が解消すれば
  /// 次回起動で元のデータに戻る。
  ///
  /// 2 以降に落ちた場合は [consumeStartupIssue] / [isVolatile] 経由で
  /// UI に理由を出すこと。accountsBox を破棄した場合はログイン済み判定が外れ、
  /// ログイン画面へ遷移する。
  ///
  /// **契約の限界**: step 3 まで失敗した場合はボックスが開かないまま return する。
  /// この関数自体は投げないが、代わりに [draftsBox] / [accountsBox] の
  /// `Hive.box<T>()` が後から `HiveError` を投げる。メモリバックエンドはほぼ
  /// 失敗要因が無いため到達確率は極めて低いが、完全に潰せてはいない。
  static Future<void> _openBoxSafely<T>(String name) async {
    try {
      await Hive.openBox<T>(name);
      return;
    } catch (e, stackTrace) {
      if (!shouldDiscardOnFailure(e)) {
        // ディスク上のデータは無傷とみなし、破棄せずメモリ上で起動する。
        debugPrint('Hive: ボックス "$name" に一時的にアクセスできません'
            '（データは保持したままメモリ上で動作します）: $e');
        debugPrintStack(stackTrace: stackTrace);
        await _openInMemory<T>(name);
        return;
      }
      debugPrint('Hive: ボックス "$name" の形式を読めなかったため作り直します: $e');
      debugPrintStack(stackTrace: stackTrace);
    }

    _resetBoxes.add(name);
    try {
      await Hive.deleteBoxFromDisk(name);
      await Hive.openBox<T>(name);
      return;
    } catch (e, stackTrace) {
      debugPrint('Hive: ボックス "$name" の作り直しにも失敗しました: $e');
      debugPrintStack(stackTrace: stackTrace);
    }

    // 最後の手段。永続化は諦め、起動だけは通す。
    // [resetBoxNames] と [volatileBoxNames] は排他なので step 2 の記録を取り消す。
    //
    // TODO: deleteBoxFromDisk が成功した直後に openBox が失敗した場合、実際には
    // 破棄済みなのにその事実まで消えてしまう。結果 storageUnavailable として
    // 「再起動で復帰しうる」と案内するが、データは戻らない。削除の成否を持って
    // 分岐すること。
    _resetBoxes.remove(name);
    await _openInMemory<T>(name);
  }

  /// メモリ上だけでボックスを開く（step 3）。永続化は行われない。
  static Future<void> _openInMemory<T>(String name) async {
    _volatileBoxes.add(name);
    try {
      await Hive.openBox<T>(name, bytes: Uint8List(0));
    } catch (e, stackTrace) {
      debugPrint('Hive: ボックス "$name" をメモリ上でも開けませんでした: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Box<DraftModel> get draftsBox =>
      Hive.box<DraftModel>(AppConstants.draftsBox);

  static Box<AccountModel> get accountsBox =>
      Hive.box<AccountModel>(AppConstants.accountsBox);
}
