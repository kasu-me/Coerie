---
name: hive-adapter-compat
description: Hiveで永続化しているモデル（AccountModel / DraftModel）、そのアダプター、hive_service.dart を変更するときに必ず使う。既存ユーザーの端末に保存済みのデータを壊さないためのルールと、実行必須の互換性テストの手順をまとめている。フィールドの追加・削除・並べ替え・型変更、typeId の変更、Hiveボックスの追加・リネームが該当。
---

# Hiveアダプターの互換性を壊さない

## なぜ必要か

`accountsBox` にはMisskeyのアクセストークンが入っている。かつてはアダプターの読み取りが
失敗すると `HiveService.init()` の例外が `main.dart` を突き抜けて `runApp` に到達せず、
**アプリが起動不能になり、ユーザー側の復旧手段はデータ削除か再インストールしかなかった。**

現在は `_openBoxSafely()` の保険（開けなければ破棄して作り直し、それも駄目ならメモリ上で
開く）が入っているため起動自体は通る。ただし**形式不整合が原因で発動した場合はユーザーが
全アカウントの再ログインを強いられる**。保険は最後の砦であって、発動させないことが目的。
（ファイルI/O失敗が原因の場合はデータを破棄しないので、次回起動で復帰しうる。
下記「復旧フォールバックの3段階」を参照）

これとは別に、CRC 破損は Hive が黙って切り詰めて「成功」させてしまうため、この保険には
乗らない。ファイルサイズの縮みで検知している（下記「CRC 破損は3段階に乗らない」）。

発動した事実は `HiveService.consumeStartupIssue()` で1回だけ取り出せ、ログイン画面が
理由を表示する。**保険の挙動を変えるときは、この通知経路も併せて維持すること**
（黙って初期化されると、ユーザーには「理由もなくログアウトしていた」としか見えない）。
`HiveStartupIssue` に値を足したら、`login_screen.dart` の switch 式は `default` を
持たないのでコンパイルエラーになる。文言の更新漏れを防ぐための設計なので潰さないこと。

## トリガー

以下のいずれかに触れるときは、このスキルの手順に従うこと。

- `lib/data/models/account_model.dart` / `account_model_adapter.dart`
- `lib/data/models/draft_model.dart` / `draft_model_adapter.dart`
- `lib/data/local/hive_service.dart`
- 新しい `TypeAdapter` の追加、`typeId` の変更
- `AppConstants` のHiveボックス名の変更

## 絶対ルール

これらのアダプターは `build_runner` 生成ではなく**手書きの位置依存バイナリ形式**で、
バージョンバイトもフィールドインデックスも持たない。読み書きの順序がそのまま保存形式になる。

| 操作 | 可否 | 理由 |
|------|------|------|
| フィールドを**末尾に**追加 | ○ | 旧レコードには後続バイトが無いだけなので、`availableBytes` ガードで既定値に落とせる |
| フィールドの削除 | ✗ | 以降の読み取り位置が全部ずれる |
| フィールドの並べ替え | ✗ | 同上 |
| フィールドの型変更 | ✗ | 読み取りバイト数が変わる |
| `typeId` の変更 | ✗ | 旧レコードのアダプターが解決できなくなる |

削除・並べ替え・型変更がどうしても必要になった場合は、この末尾追加方式では扱えない。
新しい `typeId` の新形式アダプターを追加し、旧 `typeId` のアダプターは読み取り専用で残して
起動時に旧レコードを新形式へ書き直す（Hiveはレコードごとに `typeId` を持つので併存できる）。
その場合は本スキルではなく移行計画を立ててから着手すること。

## フィールドを追加する手順

1. モデルクラスにフィールドを追加する。**nullable、または既定値を持つ型にする**
   （旧レコードには値が存在しないため）。
2. `write()` の**最後**に書き込みを追加する。既存の書き込み順は一切変えない。
3. `read()` の最後に、`availableBytes` ガード付きの読み取りを追加する。
   既存のパターンに合わせること:

   ```dart
   bool isSensitive = false;
   if (reader.availableBytes > 0) {
     isSensitive = reader.readInt() == 1;
   }
   ```

   nullable文字列で「フラグ＋本体」の2段構えにする場合は、フラグを読んだあとにも
   `availableBytes` を確認する（`account_model_adapter.dart` の `avatarUrl` を参照）。
4. `toJson()` / `fromJson()` にも追加する。`fromJson` 側は必ず既定値を用意する。
5. 下のテストを実行する。

## 実行必須のテスト

```bash
flutter test test/data
```

実装後は併せて `flutter analyze` をエラー0件になるまで実行する（CLAUDE.md の規約）。

このテストは各テストファイルの先頭にある「過去の保存形式を再現するヘルパー」が
**スナップショットとして機能する**ことで成立している。

- `account_model_adapter_test.dart` … `writeV0_9_1Format()`
- `draft_model_adapter_test.dart` … `writeLegacyFormat()`
  （`withFiles` / `withCw` / `withIsSensitive` で第1〜第4世代を再現する）

**これらのヘルパーは現行 `write()` の写しではないので、絶対に現行実装に合わせて
書き換えないこと。** 書き換えるとテストが何も検証しなくなる。
フィールドを末尾に追加した場合、ヘルパーは触らず**テストケースだけを足す**。

### 失敗したときの読み解き方

- **「v0.9.1 形式を接頭辞として保持する」が落ちた**
  → 既存フィールドのバイト表現を変えている。削除・並べ替え・型変更をしていないか確認する。
  末尾追加だけならこのテストは通る。
- **「v0.9.1 形式のレコードを現行アダプターで読める」が落ちた**
  → 既存ユーザーのアカウントが読めなくなる。そのままリリースすると全員が再ログインになる。
- **「末尾フィールドを欠いたレコードは既定値で読める」が落ちた**
  → `availableBytes` ガードが漏れている。追加したフィールドの読み取りを囲む。

## 現状のカバレッジと限界

- `AccountModelAdapter` … カバー済み（5ケース）。
- `DraftModelAdapter` … カバー済み（8ケース）。末尾追加を3回重ねた結果、端末には
  第1〜第4世代のレコードが混在しうるため、世代ごとの読み取りを個別に検証している。
- `HiveService` の復旧判定 … カバー済み（`test/data/local/hive_service_test.dart`、
  22ケース）。`consumeStartupIssue()` の対象・優先順位・一度きりの取り出しと、
  `shouldDiscardOnFailure()` の分類を固定している。状態は `@visibleForTesting` の
  `debugSetStartupState()` から注入する。
- `_openBoxSafely()` の実挙動 … カバー済み
  （`test/data/local/hive_service_recovery_test.dart`、5ケース）。
  `@visibleForTesting` の `HiveService.debugInitAt(directory)` で保存先を一時
  ディレクトリに差し替え、壊した `.hive` を置いて本番と同じコードを通す。
  `Hive.initFlutter()` は path_provider に依存しユニットテストでは必ず失敗する
  ため、`init()` をそのまま呼んでも全ボックスが step 3 に落ちて何も検証できない。
  - **step 2 と step 3 のどちらに落ちるかはプラットフォームで変わる。** hive は
    オープン失敗時の `newBox?.close()` を await しないので、Windows では
    ファイルハンドルが残って `deleteBoxFromDisk` が `PathAccessException`
    （`FileSystemException` のサブクラス）で失敗し、step 3 に落ちる。Android と
    Linux はオープン中の unlink が通るので step 2 で止まる。開発機で
    「step 2 に落ちること」を assert しないこと。
- 新しいアダプターを追加したら、上記を雛形に同等のテストも必ず追加すること。

### 復旧フォールバックの3段階

`_openBoxSafely()` は失敗するたびに段階的に諦める。**step 2 と step 3 は性質が違う**ので
混同しないこと。

| | 状態 | ユーザーから見た挙動 |
|---|---|---|
| step 1 | 通常どおり開けた | — |
| step 2 | 中身を破棄して作り直した（`resetBoxNames`） | 保存データが消える |
| step 3 | メモリ上のみで開いた（`volatileBoxNames`） | **保存は成功して見えるが再起動で消える** |

step 1 が成功した場合でも、Hive の自動復旧がレコードを切り捨てていることがある
（`recoveredBoxNames`）。これは3段階とは別系統なので、下の「CRC 破損は3段階に乗らない」
を参照。step 1 成功時にしか記録されないため、`resetBoxNames` / `volatileBoxNames` とは
同時に立たない。

step 2 の破棄が成立しないまま step 3 に落ちた場合は、ディスク上のデータが無傷なので
step 2 の記録を取り消す。破棄が成立していた場合は両方に記録が残り、
`consumeStartupIssue()` は `accountsResetAndVolatile`（データが失われ、かつ再ログインも
この起動中しか保持されない）を返す。

なお step 3 自体が失敗した場合はボックスが開かないまま終わり、`volatileBoxNames` には
記録されない（`resetBoxNames` は破棄が成立していれば残る）。この状態ではボックスへの
最初のアクセスで `HiveError` が投げられる。

**step 2 は失敗の原因を選ぶ。** 破棄はアクセストークンの消去を意味するため、
`shouldDiscardOnFailure()` が false を返す失敗では step 2 を飛ばして step 3 へ直行する。

- 形式不整合（`HiveError`、アダプターの `RangeError` など）… 破棄する
- ファイルI/O・ロック失敗（`FileSystemException`）… **破棄しない**。ストレージが
  一時的に読めない、権限が無い、ファイルハンドルが枯渇している等の復旧可能なケース。
  破棄すると一時的な失敗のたびにトークンが消え「起動するたびログアウトする」挙動になる。
  原因が解消すれば次回起動で元のデータに戻る
- 保存先ディレクトリ未取得（`Hive.initFlutter()` が失敗）… ファイルに触れていないので破棄しない
- 未知の例外… 破棄側に倒す（取りこぼすとメモリ上で動き続けて復旧手段が無くなるため）

### CRC 破損は3段階に乗らない（step 1 が成功してしまう）

CRC 破損は `crashRecovery: true`（`Hive.openBox` の既定）により自動復旧されるので、
上の3段階には到達しない。**ただし自動復旧は無害ではない。**

`FrameHelper.framesFromBytes()` は最初に読めなかったフレームの位置を返し、
`StorageBackendVm.initialize()` はそこから先を**すべて** `truncate()` する。破損位置が
先頭寄りなら**全件消える**（3件・234バイトのボックスの中間1バイトを反転させたところ、
78バイト・1件まで切り詰められた）。step 1 は成功扱いなので、放置すると
「理由もなく全アカウントが消えてログイン画面に戻る」——この保険が消そうとしている
症状そのものになる。

**そのため、ファイルサイズの縮みで検知している**（`_recordRecoveryIfShrunk`）。
`truncate()` はディスク上のファイルを実際に縮めるので、`openBox` の前後でサイズを比べ
れば復旧が走ったと分かる。正常なオープンは1バイトも縮まない。検知したボックスは
`recoveredBoxNames` に載り、accountsBox なら `consumeStartupIssue()` が
`accountsPartiallyLost` を返す。

保存先パスは `_boxDirectory` に控えた「予測」で、`hive_flutter` が
`getApplicationDocumentsDirectory()` の結果を `Hive.init()` に渡すことに依存している。
**ここで `Hive.init()` を呼び直してはいけない**（保存先がずれると全ユーザーのデータが
行方不明になる）。予測がずれた場合はオープン後に `Box.path` と突き合わせて気付き、
検知を見送る（＝誤検知ではなく無検知に倒す）。

限界は2つ。どちらも承知のうえで許容している。

- **「書き込み中に kill された」場合も同じシグナルになる。** 外から区別する手段が無い
  （`crashRecovery: false` での事前オープンでも同じ）。ただしその場合も書きかけの1件は
  実際に失われているので、通知が事実と食い違うわけではない。accountsBox への書き込みは
  ログイン・ログアウト・アカウント切り替えのときだけなので、遭遇率も低い。
- **アカウントが1件でも残っていれば通知されない。** 表示先がログイン画面だけで、
  ルーターは0件のときしかそこへ遷移させないため。全件消えた場合（最悪ケース）は
  必ず通知される。部分消失まで伝えたいなら、ホーム画面に別の通知経路が要る。

### hive はオープン失敗時に未処理の非同期エラーを漏らす

`HiveImpl._openBox` は失敗時、**誰も listen していない内部 completer にも**同じエラーを
流してから rethrow する（hive 2.2.3, `hive_impl.dart:118`）。呼び出し側が catch できるのは
rethrow された方だけで、completer 側は未処理の非同期エラーとして zone に漏れる。

放置すると、復旧経路を通るテストが本題と無関係な `RangeError` で落ちるうえ、
`runZonedGuarded` でクラッシュレポータを入れた場合に**復旧が成功するたび**致命的エラー
として報告される。`_openBoxIsolated()` が隔離ゾーンで実行して漏れた分を捨てているので、
**`Hive.openBox()` を直接呼ばないこと。** 退行は
`hive_service_recovery_test.dart` の「未処理の非同期エラーを zone に漏らさない」が検知する。

> **未検証事項**: Hive は `StorageBackendVm.initialize()` で `.lock` ファイルを
> 排他ロックする。`RandomAccessFile.lock()` は既定でロック取得を**待つ**ため、競合しても
> 例外にはならず起動がハングする可能性がある（＝上記の分類には乗らない）。
> **その構成は本アプリでは未検証**で、現状バックグラウンド isolate は存在しない。
> プッシュ通知ハンドラや WorkManager を追加する際は、Hive の多重オープン可否を
> 別途検証すること。

### 意図的に見送っているもの

`draftsBox` の問題は**起動時には**通知されない。ログイン状態が維持されるため
ログイン画面を通らず、過去の下書きが黙って消える（step 2）。発生確率はむしろ
accountsBox より高い（`DraftModelAdapter` は files / cw / isSensitive と3回拡張された
実績があり、次に触られて壊れる可能性が高いのは draft 側）が、失われるのは未送信の
下書き数件で影響が軽く、ホーム画面に通知経路を新設するコストに見合わないと判断した。
「壊れたことを事後に伝える」代わりに、上記テストで壊れる確率自体を下げている。

一方 step 3 は「消える」ではなく「保存できたと嘘をつく」ため見送っていない。
`StorageBackendMemory.writeFrames` は no-op なので `box.put()` は成功し同一起動中は
一覧にも出るが、再起動すると全部消える。下書き保存時に `HiveService.isVolatile()` を
見て、この起動中しか保持されない旨を通知している（`compose_screen.dart` の `_saveDraft`）。

自動復旧によるレコード欠落（`recoveredBoxNames`）も、accountsBox が**全件**失われた
場合しか通知されない。1件でも残ればログイン画面を通らないため。全件消失＝強制ログアウト
という最悪ケースだけを押さえ、部分消失は見送っている。

方針を変えてホーム画面でも通知する場合、破棄・非永続・レコード欠落の事実は
`resetBoxNames` / `volatileBoxNames` / `recoveredBoxNames` に残り続けるので、
そちらを参照すればよい（`consumeStartupIssue()` を呼んでもクリアされない）。

テストは `BinaryWriterImpl` / `BinaryReaderImpl` を直接使うため `hive` を
dev_dependencies に直接入れてある（`hive_flutter` 経由の推移的依存だけだと
`depend_on_referenced_packages` に抵触するため）。

## 関連ファイル

- `lib/data/models/account_model_adapter.dart`
- `lib/data/models/draft_model_adapter.dart`
- `lib/data/local/hive_service.dart` … `_openBoxSafely()` の保険、
  `shouldDiscardOnFailure()` の分類、`_recordRecoveryIfShrunk()` の破損検知、
  `_openBoxIsolated()` の zone 隔離、`HiveStartupIssue`
- `lib/features/auth/login_screen.dart` … 初期化が起きた理由をユーザーに提示する箇所
- `lib/features/compose/compose_screen.dart` … `_saveDraft` の非永続時の警告
- `lib/main.dart` … `HiveService.init()` の呼び出し位置
- `test/data/models/account_model_adapter_test.dart`
- `test/data/models/draft_model_adapter_test.dart`
- `test/data/local/hive_service_test.dart` … 復旧判定の状態マッピング
- `test/data/local/hive_service_recovery_test.dart` … 実際の `.hive` を壊して
  `_openBoxSafely()` を通す統合テスト
