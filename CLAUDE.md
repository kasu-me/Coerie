# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 前提条件

- **回答は日本語で行ってください。**
- 全てのファイルはUTF-8で保存されています。
- 本プロジェクトは日本語で開発されています。

## プロジェクト概要

MisskeyクライアントのFlutterモバイルアプリ（Android向け）。分散型SNS Misskeyに接続し、タイムライン閲覧・ノート投稿・通知確認などの機能を提供する。バージョンは `pubspec.yaml` の `version` を参照。

API実装は **Misskey v2026.6.0** に準拠している（`lib/data/remote/misskey_api.dart`）。API変更時は当該バージョンのAPIリファレンスと照合すること。

## 基本ルール

- 「実装せよ」という意味の明確な指示があるまで実装には入らないこと。
  - 「○○できるか？」というような、実現可能性・可否を尋ねる質問に対応する場合、「できる」または「できない」とその理由を答えるだけにとどめること。
- 実装にあたって不明な点がある場合は、些細な事でも質問し、方向性について合意を形成してから着手すること。
  - 疑問点はまとめて一度に質問すること。
  - 実装方針に影響する不明点に絞ること。（変数名レベルの些細な選択は含めない）
  - 実装方針に複数の案がある場合、それぞれの案にどのような利点/欠点があるのかを提示し、推奨される選択肢がどれなのかも提示すること。
- 新機能を実装する場合は、実装前に、既存コードと共通化できる部分がないか探すこと。
  共通化する場合は、以下のいずれかに該当しないか確認する:
  - 現時点でロジックが似ているだけで、将来的に別々の理由で変化する可能性が高い（例: 見た目は同じだが、片方は税制、もう片方はポイント計算のロジックであり、法改正とキャンペーン仕様変更という別々のトリガーで変わる）
  - 共通化すると、関係のないif文が増えて可読性が大きく下がる
  - その他抽象化のコストが見合わないと判断できる

  該当する場合は無理に共通化せず、重複を許容してよい。
- コメントは、コードそのものからは読み取れない背景・意図を書く。実装内容の説明（「何をしているか」）は書かない。特に以下を優先する：
  - なぜそう実装しなければならなかったか（制約・仕様上の理由・過去の障害対応など）
  - 敢えてやらなかったこと・採用しなかった選択肢とその理由
  - 一見不要/非効率に見えるが意図的な実装であること（自明でないトレードオフ）
  - 外部要因による制約（API仕様、パフォーマンス要件、ライブラリの既知のバグ回避など）
  - 変更履歴やgit logからは追いにくい「なぜ今の形になったか」の文脈

## 主要コマンド

```bash
# 依存関係インストール
flutter pub get

# アプリ実行
flutter run

# コード解析（実装後に必ず実行）
flutter analyze

# Hiveモデルのコード生成
dart run build_runner build

# リリースAPKビルド
$commitCount = (git rev-list --count HEAD).Trim();
flutter build apk --release --split-per-abi --build-number=$commitCount;
```

> **重要**: 実装が終わった後は必ず `flutter analyze` を実行し、エラーが完全になくなるまで修正を繰り返してください。

## アーキテクチャ概要

### ディレクトリ構造

```
lib/
├── main.dart             # エントリーポイント
├── app.dart              # アプリルート（ProviderScope, MaterialApp.router）
├── core/                 # 横断的関心事
│   ├── auth/             # MiAuth OAuth認証サービス
│   ├── router/           # GoRouterルーティング定義
│   ├── services/         # 共通サービス（画像圧縮、キャッシュ）
│   ├── streaming/        # WebSocketストリーミングサービス
│   ├── theme/            # Material Design 3テーマ
│   └── constants/        # アプリ定数
├── data/
│   ├── models/           # データモデル（JSON シリアライズ、Hiveアダプター）
│   ├── remote/           # MisskeyApiラッパー（Dio HTTPクライアント）
│   └── local/            # HiveServiceローカルストレージ
├── features/             # 機能別UIモジュール
│   ├── home/             # メイン画面（タブナビゲーション）
│   ├── timeline/         # タイムライン（ホーム/ローカル/ソーシャル/グローバル）
│   ├── compose/          # ノート投稿
│   ├── notifications/    # 通知
│   ├── profile/          # プロフィール
│   ├── search/           # 検索
│   ├── auth/             # ログイン画面
│   └── ...               # その他機能（favorites, lists, channels, drive, settings等）
└── shared/
    └── providers/        # アプリ横断のRiverpodプロバイダー
```

### 状態管理（Riverpod）

状態管理はすべて Riverpod で行う。主要なグローバルプロバイダーは `lib/shared/providers/` に配置。

```dart
// アカウント管理（StateNotifier で変更可能な状態）
final accountProvider = StateNotifierProvider<AccountNotifier, List<AccountModel>>

// アクティブアカウント（派生状態）
final activeAccountProvider = Provider<AccountModel?>

// API クライアント（認証依存）
final misskeyApiProvider = Provider<MisskeyApi?>

// WebSocket ストリーミング
final streamingServiceProvider = ...
```

- `ref.watch()` で状態を購読、`ref.read()` でアクションを実行
- 機能固有のプロバイダーは各 features/ サブディレクトリに配置

### データフロー

```
MiAuthService (OAuth, coerie://auth ディープリンク)
  → AccountProvider (Hive: accountsBox)
    → MisskeyApiProvider (Dio HTTP)
      → StreamingService (WebSocket wss://host/streaming)
        → Feature Providers → UI
```

### ローカルストレージ

- **Hive**: アカウント情報・下書きの永続化（型安全なアダプター使用）
- **SharedPreferences**: アプリ設定（フォントサイズ、テーマ等）

## UI/UXルール

- ボタンにはアイコンを表示し、ユーザーが直感的に機能を理解できるようにする
- 既存画面と統一感のあるUIを採用し、アプリ全体の一貫性を保つ
- `ModalBottomSheet` 使用時は `SafeArea` でAndroidナビゲーションバーとの重なりを防ぐ
- テーマカラー: シードカラー `0xFF7B61FF`（紫）、Material Design 3
- 日本語フォント: Noto Sans JP（google_fonts）

## 主要ライブラリ

| 用途 | パッケージ |
|------|-----------|
| HTTP通信 | `dio` |
| WebSocket | `web_socket_channel` |
| 状態管理 | `flutter_riverpod` |
| ナビゲーション | `go_router` |
| ローカルDB | `hive_flutter` |
| 設定 | `shared_preferences` |
| MFMパース | `mfm_parser` |
| 画像キャッシュ | `cached_network_image` |
| 動画再生 | `video_player` + `chewie` |
| 認証/ディープリンク | `app_links` + `url_launcher` |
