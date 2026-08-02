import 'dart:async';
import 'dart:io' show File, FileSystemException, Platform;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
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

  /// 保存データの一部が壊れており、Hive の自動復旧で切り捨てられた。
  /// ボックス自体は開けているが中身が欠けている（全件欠けることもある）。
  accountsPartiallyLost,

  /// メモリ上だけで動作している。アプリは起動するが、この起動中に追加した
  /// アカウントは保存されない。
  ///
  /// **ディスク上のデータを温存したまま**メモリ上に落ちた場合を含み、その場合は
  /// 原因が解消すれば次回起動で元のデータに戻る。UI の文言は「データが消えた」と
  /// 断定せず、再起動で復帰しうる旨を伝えること。
  storageUnavailable,

  /// 保存データを破棄したうえでメモリ上に落ちた。アカウントが失われ再ログインが
  /// 必要で、しかもその再ログインもこの起動中しか保持されない。
  accountsResetAndVolatile,
}

class HiveService {
  HiveService._();

  static final Set<String> _resetBoxes = <String>{};
  static final Set<String> _volatileBoxes = <String>{};
  static final Set<String> _recoveredBoxes = <String>{};
  static bool _startupIssueConsumed = false;
  static bool _storageDirectoryAvailable = true;
  static String? _boxDirectory;

  /// 中身を破棄して作り直したボックス名（[_openBoxSafely] の step 2）。
  ///
  /// 破棄が成立した状態で step 3 に落ちた場合は [volatileBoxNames] にも残る。
  /// [consumeStartupIssue] を呼んでもクリアされない。
  static Set<String> get resetBoxNames => Set.unmodifiable(_resetBoxes);

  /// メモリ上のみで開けたボックス名（[_openBoxSafely] の step 3）。開けなかった
  /// 場合はここに記録されない。
  ///
  /// このボックスへの書き込みは **成功するが一切永続化されない**。
  /// 同一起動中は読み戻せてしまうため、保存できたように見える点に注意。
  /// step 2 の破棄を経てここに落ちた場合は [resetBoxNames] にも残る。
  static Set<String> get volatileBoxNames => Set.unmodifiable(_volatileBoxes);

  /// Hive の自動復旧でレコードの一部（または全部）が失われたボックス名。
  ///
  /// step 1 が成功した場合にだけ記録される。つまり [resetBoxNames] /
  /// [volatileBoxNames] とは同時に立たない。判定方法と限界は
  /// [_recordRecoveryIfShrunk] を参照。
  static Set<String> get recoveredBoxNames => Set.unmodifiable(_recoveredBoxes);

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
  /// **限界**: 表示側がログイン画面なので、アカウントが1件でも残っていれば
  /// ユーザーはここを通らず、通知されないまま先へ進む
  /// （[HiveStartupIssue.accountsPartiallyLost] で起きうる）。
  ///
  /// 通知しないと決めた経緯と、方針を変える場合の手掛かりは
  /// `.claude/skills/hive-adapter-compat` の「意図的に見送っているもの」を参照。
  static HiveStartupIssue? consumeStartupIssue() {
    if (_startupIssueConsumed) return null;
    _startupIssueConsumed = true;

    final wasReset = _resetBoxes.contains(AppConstants.accountsBox);
    final isVolatile = _volatileBoxes.contains(AppConstants.accountsBox);
    final wasRecovered = _recoveredBoxes.contains(AppConstants.accountsBox);

    if (wasReset && isVolatile) {
      return HiveStartupIssue.accountsResetAndVolatile;
    }
    if (isVolatile) return HiveStartupIssue.storageUnavailable;
    if (wasReset) return HiveStartupIssue.accountsReset;
    if (wasRecovered) return HiveStartupIssue.accountsPartiallyLost;
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
    Set<String> recovered = const {},
    bool storageDirectoryAvailable = true,
  }) {
    _resetBoxes
      ..clear()
      ..addAll(reset);
    _volatileBoxes
      ..clear()
      ..addAll(volatile);
    _recoveredBoxes
      ..clear()
      ..addAll(recovered);
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

    if (_storageDirectoryAvailable) {
      // initFlutter() は getApplicationDocumentsDirectory() の結果をそのまま
      // Hive.init() に渡す（hive_flutter 1.1.0）。破損検知でファイルサイズを見る
      // ために同じパスを控える。**ここで Hive.init() を呼び直してはいけない**
      // （保存先がずれると全ユーザーのデータが行方不明になる）。
      // hive_flutter の実装が変わって予測がずれた場合は
      // [_recordRecoveryIfShrunk] が box.path との突き合わせで気付き、検知を見送る。
      try {
        _boxDirectory = (await getApplicationDocumentsDirectory()).path;
      } catch (e) {
        // 破損検知ができなくなるだけなので、起動は止めない。
        debugPrint('Hive: 保存先パスを特定できず、破損検知は行いません: $e');
      }
    }

    await _registerAdaptersAndOpenBoxes();
  }

  /// テストから保存先を差し替えて [_openBoxSafely] を実地で通すための入口。
  ///
  /// [init] は `Hive.initFlutter()` を使うが、これは path_provider に依存するため
  /// ユニットテストでは必ず失敗し、全ボックスが step 3 に落ちてしまう。壊れた
  /// `.hive` を置いた一時ディレクトリを渡せば、step 1→2→3 と破損検知を本番と
  /// 同じコードで検証できる。
  ///
  /// アダプターは登録済みなら上書きしないので、壊れたアダプターを先に
  /// `override: true` で登録しておけば step 1 の失敗を再現できる。
  @visibleForTesting
  static Future<void> debugInitAt(String directory) async {
    Hive.init(directory);
    _boxDirectory = directory;
    _storageDirectoryAvailable = true;
    await _registerAdaptersAndOpenBoxes();
  }

  static Future<void> _registerAdaptersAndOpenBoxes() async {
    if (!Hive.isAdapterRegistered(DraftModelAdapter().typeId)) {
      Hive.registerAdapter(DraftModelAdapter());
    }
    if (!Hive.isAdapterRegistered(AccountModelAdapter().typeId)) {
      Hive.registerAdapter(AccountModelAdapter());
    }
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
  /// step 1 が成功しても、Hive の自動復旧が黙ってレコードを切り捨てていることが
  /// ある。これは [_recordRecoveryIfShrunk] が [recoveredBoxNames] に記録する。
  ///
  /// 2 以降に落ちた場合は [consumeStartupIssue] / [isVolatile] 経由で
  /// UI に理由を出すこと。accountsBox を破棄した場合はログイン済み判定が外れ、
  /// ログイン画面へ遷移する。
  ///
  /// **契約の限界**: step 3 まで失敗した場合はボックスが開かないまま return する。
  /// この関数自体は投げないが、代わりに [draftsBox] / [accountsBox] の
  /// `Hive.box<T>()` が後から `HiveError` を投げる。メモリバックエンドはほぼ
  /// 失敗要因が無いため到達確率は極めて低いが、完全に潰せてはいない。この場合
  /// [volatileBoxNames] にも記録されず、[isVolatile] は false を返す。
  static Future<void> _openBoxSafely<T>(String name) async {
    final sizeBeforeOpen = _boxFileSize(name);
    try {
      final box = await _openBoxIsolated<T>(name);
      _recordRecoveryIfShrunk(name, box, sizeBeforeOpen);
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
    var discarded = false;
    try {
      await Hive.deleteBoxFromDisk(name);
      discarded = true;
      await _openBoxIsolated<T>(name);
      return;
    } catch (e, stackTrace) {
      debugPrint('Hive: ボックス "$name" の作り直しにも失敗しました: $e');
      debugPrintStack(stackTrace: stackTrace);
    }

    // 最後の手段。永続化は諦め、起動だけは通す。
    // 破棄が成立していなければディスク上のデータは無傷なので step 2 の記録を
    // 取り消す。成立していた場合は両方に記録が残る。
    if (!discarded) _resetBoxes.remove(name);
    await _openInMemory<T>(name);
  }

  /// メモリ上だけでボックスを開く（step 3）。永続化は行われない。
  static Future<void> _openInMemory<T>(String name) async {
    try {
      await _openBoxIsolated<T>(name, bytes: Uint8List(0));
      _volatileBoxes.add(name);
    } catch (e, stackTrace) {
      debugPrint('Hive: ボックス "$name" をメモリ上でも開けませんでした: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// [Hive.openBox] を隔離した zone で実行する。
  ///
  /// `HiveImpl._openBox` は失敗時、**誰も listen していない内部 completer にも**
  /// 同じエラーを流してから rethrow する（hive 2.2.3）。呼び出し側が catch できる
  /// のは rethrow された方だけで、completer 側は未処理の非同期エラーとして zone に
  /// 漏れる。ここで受け止めないと次の実害が出る。
  ///
  /// - `flutter test` では、復旧経路を通るテストが本題と無関係な例外で落ちる
  /// - `runZonedGuarded` でクラッシュレポータを入れた場合、復旧が**成功**する
  ///   たびに致命的エラーとして報告される
  ///
  /// 呼び出し側は返り値の Future だけを見ればよい。
  static Future<Box<T>> _openBoxIsolated<T>(String name, {Uint8List? bytes}) {
    final completer = Completer<Box<T>>();
    runZonedGuarded(
      () async {
        try {
          completer.complete(await Hive.openBox<T>(name, bytes: bytes));
        } catch (e, stackTrace) {
          completer.completeError(e, stackTrace);
        }
      },
      (error, stackTrace) {
        // rethrow された分は completer 経由で呼び出し側が処理済み。ここに来るのは
        // hive が二重に流した同じエラーなので捨てる。
        debugPrint('Hive: ボックス "$name" のオープンで漏れた非同期エラーを無視します: $error');
      },
    );
    return completer.future;
  }

  /// [name] のボックスファイルの想定パス。**破損検知にのみ使う。**
  ///
  /// hive の `BackendManager.open()` は `<保存先>/<name>.hive` を開く。
  /// 実際に開かれたパスは `Box.path` で取れるが、開く**前**のサイズが要るので
  /// ここで組み立てる。予測が外れても [_recordRecoveryIfShrunk] が気付く。
  static String? _boxFilePath(String name) {
    var dir = _boxDirectory;
    if (dir == null) return null;
    // hive は末尾の区切りを落としてから組み立てる（BackendManager.open）。
    // 揃えておかないと box.path との突き合わせが外れて検知が黙って止まる。
    if (dir.endsWith(Platform.pathSeparator)) {
      dir = dir.substring(0, dir.length - 1);
    }
    return '$dir${Platform.pathSeparator}$name.hive';
  }

  static int _boxFileSize(String name) {
    final path = _boxFilePath(name);
    if (path == null) return 0;
    try {
      final file = File(path);
      return file.existsSync() ? file.lengthSync() : 0;
    } catch (e) {
      // 読めないだけなら検知を諦める。起動は止めない。
      debugPrint('Hive: ボックス "$name" のサイズを取得できませんでした: $e');
      return 0;
    }
  }

  /// Hive の自動復旧でレコードが失われたかを、ファイルサイズの縮みで判定する。
  ///
  /// CRC 破損は `crashRecovery: true`（`Hive.openBox` の既定）により
  /// `StorageBackendVm.initialize()` が「最初に読めなかった位置以降を truncate」
  /// して黙って復旧するので、**step 1 は成功してしまい 3段階フォールバックには
  /// 乗らない**。開く前後でファイルが縮んでいれば、その差分だけレコードが失われて
  /// いる。正常なオープンでは 1 バイトも縮まない。
  ///
  /// **限界**:
  /// - 「書き込み中に kill された」場合も同じシグナルになる（末尾フレームだけが
  ///   失われる正常系）。ただしその場合も書きかけの1件は実際に失われており、
  ///   通知が事実と食い違うわけではないため区別していない。
  /// - 通知はログイン画面でしか出ないので、アカウントが1件でも残っていれば
  ///   ユーザーには伝わらない（[consumeStartupIssue] の「限界」を参照）。
  static void _recordRecoveryIfShrunk(
    String name,
    Box<dynamic> box,
    int sizeBeforeOpen,
  ) {
    if (sizeBeforeOpen <= 0) return;

    final expected = _boxFilePath(name);
    final actual = box.path;
    if (actual == null || actual != expected) {
      // hive_flutter の保存先の決め方が変わって予測がずれている。
      // 誤検知するくらいなら検知しない。
      debugPrint('Hive: ボックス "$name" の想定パスが実際と異なるため'
          '破損検知を見送ります（想定=$expected 実際=$actual）');
      return;
    }

    final sizeAfterOpen = _boxFileSize(name);
    if (sizeAfterOpen < sizeBeforeOpen) {
      debugPrint('Hive: ボックス "$name" の一部を読めなかったため失われました'
          '（$sizeBeforeOpen → $sizeAfterOpen バイト）');
      _recoveredBoxes.add(name);
    }
  }

  static Box<DraftModel> get draftsBox =>
      Hive.box<DraftModel>(AppConstants.draftsBox);

  static Box<AccountModel> get accountsBox =>
      Hive.box<AccountModel>(AppConstants.accountsBox);
}
