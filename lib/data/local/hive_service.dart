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
  /// 保存データを破棄したうえでメモリ上に落ちた場合と、ファイルI/O・ロック失敗で
  /// **ディスク上のデータを温存したまま**メモリ上に落ちた場合の両方を含む。
  /// 後者は原因が解消すれば次回起動で元のデータに戻るため、UI の文言は
  /// 「データが消えた」と断定せず、再起動で復帰しうる旨を伝えること。
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
  /// [volatileBoxNames] とは排他。プロセスが生きている限り保持され、
  /// [consumeStartupIssue] を呼んでもクリアされない。
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
  /// draftsBox など他のボックスの問題は意図的に対象外（下記参照）。
  /// 判定を accountsBox に絞っているのは、この結果を表示するのがログイン画面
  /// だけであり、「アカウントが失われた」という文言と対象がずれないようにするため。
  ///
  /// ## 既知の穴（v0.9.1 時点で意図的に見送った）
  ///
  /// draftsBox に問題が起きてもユーザーには通知されない。ログイン状態が維持され
  /// ログイン画面を通らないため、下書きが黙って消える。ただし step 2 と step 3 で
  /// 深刻さが異なるので、その点は分けて評価している。
  ///
  /// ### step 2（破棄して作り直し）… 見送りは妥当
  ///
  /// 起動時に過去の下書きが消えるだけ。失われるのは未送信の下書き数件で、
  /// 全アカウント再ログインに比べれば軽い。発生確率は accountsBox より
  /// **高い**（`DraftModelAdapter` は files / cw / isSensitive と3回拡張された
  /// 実績があり、git 上のコミット数も draft 側 3 に対し account 側 1。次に
  /// 触られて壊れる可能性が高いのは draft 側）が、通知のためにホーム画面へ
  /// 表示経路を新設するコストには見合わない。代わりに
  /// `test/data/models/draft_model_adapter_test.dart` を追加し、
  /// 「壊れたことを事後に伝える」のではなく「壊れる確率を下げる」方針を採った。
  ///
  /// ### step 3（メモリ上のみ）… 性質が異なる
  ///
  /// こちらは「消える」ではなく **「保存できていないのに保存できたように見える」**。
  /// `StorageBackendMemory.writeFrames` は no-op なので `box.put()` は成功し、
  /// 同一起動中は一覧にも出る。そのまま再起動すると全部消える。
  /// 「事後に伝えない」ことの是非以前に、嘘をつかないほうが優先されるため、
  /// 下書き保存時は [isVolatile] を見て「この起動中のみ保持される」旨を
  /// 通知している（`compose_screen.dart` の `_saveDraft`）。
  ///
  /// 方針を変えてホーム画面でも通知する場合: 破棄・非永続の事実は
  /// [resetBoxNames] / [volatileBoxNames] に残り続けるので、そちらを参照すればよい。
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
  /// いけない。`Hive.openBox` は既定で `crashRecovery: true` であり、CRC 破損した
  /// フレームは例外ではなく末尾切り詰めで自動復旧される
  /// （`storage_backend_vm.dart` の `initialize`）。したがってここに到達する失敗は
  /// 実質2系統に分かれる。
  ///
  /// - **形式不整合**（`HiveError('Cannot read, unknown typeId')`、アダプターの
  ///   `RangeError` など）… ディスク上のデータは今後も読めない。破棄が妥当。
  /// - **ファイルI/O・ロック失敗**（`FileSystemException`）… Hive は初期化時に
  ///   `.lock` ファイルを開いてロックする（`storage_backend_vm.dart` の
  ///   `initialize`）。ストレージが一時的に読めない、権限が無い、ファイル
  ///   ハンドルが枯渇している、といった**復旧可能**なケースがここに来るので
  ///   破棄してはいけない。破棄すると一時的な失敗のたびにトークンが消え、
  ///   「起動するたびログアウトする」挙動になる。
  ///
  ///   複数 isolate から同じボックスを開いた場合もロック競合が起きうるが、
  ///   **その構成は本アプリでは未検証**（現状バックグラウンド isolate は無い）。
  ///   この分類は競合時にデータを消さないだけで、多重オープンを成立させる
  ///   ものではない。プッシュ通知ハンドラや WorkManager を追加する際は、
  ///   Hive の多重オープン可否を別途検証すること。
  ///
  /// 未知の例外は破棄側に倒す。形式不整合を取りこぼすと step 2 が永久に動かず、
  /// メモリ上で動き続けて復旧手段が無くなるため。
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
  /// ただし [shouldDiscardOnFailure] が false を返す失敗（ファイルI/O・ロック失敗）
  /// では **step 2 を飛ばして step 3 へ直行する**。ディスク上のデータは無傷の
  /// 可能性が高く、破棄するとトークンを不要に失うため。この場合その起動中は
  /// 保存できないが、原因が解消すれば次回起動で元のデータに戻る。
  ///
  /// 2 以降に落ちた場合は [consumeStartupIssue] / [isVolatile] 経由で
  /// UI に理由を出すこと。accountsBox を破棄した場合はログイン済み判定が外れ、
  /// ログイン画面へ遷移する。
  ///
  /// **契約の限界**: step 3 まで失敗した場合はボックスが開かないまま return する。
  /// この関数自体は投げないが、代わりに [draftsBox] / [accountsBox] の
  /// `Hive.box<T>()` が後から `HiveError` を投げる。つまり「起動時の一箇所で
  /// 落ちる」が「UI の深いところで落ちる」に置き換わっただけになる。
  /// メモリバックエンドは書き込みも no-op でほぼ失敗要因が無いため到達確率は
  /// 極めて低いが、完全に潰せてはいない。
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
    // 「破棄した」ではなく「保存されない」状態なので step 2 の記録は取り消す。
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
