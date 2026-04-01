import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('プライバシーポリシー')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _Section(
              title: 'プライバシーポリシー',
              body:
                  'Coerie（以下「本アプリ」）は、M_Kasumi（以下「開発者」）が提供するMisskey向けクライアントアプリです。'
                  '本アプリのご利用に際し、以下のプライバシーポリシーをご確認ください。',
            ),
            _Section(
              title: '1. 収集する情報',
              body:
                  '本アプリは、以下の情報を端末内に保存します。\n\n'
                  '• アカウント情報（ユーザーID、表示名、アカウント識別子、サーバーURL、アバター画像URL、アクセストークン）\n'
                  '• アプリ設定（テーマ、フォントサイズ、タブ構成、通知設定など）\n'
                  '• 下書き（作成した投稿の下書きテキストおよび添付ファイル情報）\n\n'
                  'これらの情報はすべて端末内のみに保存され、開発者のサーバーに送信されることはありません。',
            ),
            _Section(
              title: '2. 情報の利用目的',
              body:
                  '収集した情報は以下の目的にのみ使用します。\n\n'
                  '• Misskeyサーバーへのログインおよびタイムラインの閲覧・操作\n'
                  '• アプリ設定の保持および復元\n'
                  '• 下書き機能の提供',
            ),
            _Section(
              title: '3. 外部サービスとの通信',
              body:
                  '本アプリは、ユーザーが登録したMisskeyサーバー（以下「接続先サーバー」）とHTTPSおよびWebSocketを通じて通信します。'
                  '接続先サーバーへ送信されるデータ（投稿内容、リアクション操作など）の取り扱いは、各サーバーのプライバシーポリシーに準じます。\n\n'
                  '本アプリ自体が運営するサーバーは存在せず、開発者はユーザーの通信内容を収集・閲覧しません。',
            ),
            _Section(
              title: '4. 第三者への情報提供',
              body:
                  '開発者は、ユーザーの個人情報を第三者に販売・提供・開示することはありません。'
                  'ただし、法令に基づく開示請求があった場合はこの限りではありません。',
            ),
            _Section(
              title: '5. 広告・アナリティクス',
              body: '本アプリは広告を表示せず、Google Analyticsなどの外部アナリティクスサービスを使用しません。',
            ),
            _Section(
              title: '6. データの保管と削除',
              body:
                  '本アプリのデータはすべて端末内に保存されます。'
                  'アプリをアンインストールすることで、端末内のすべてのデータが削除されます。'
                  'アカウントは設定画面から個別に削除することもできます。',
            ),
            _Section(
              title: '7. 権限について',
              body:
                  '本アプリが要求する端末の権限は以下のとおりです。\n\n'
                  '• インターネット接続: Misskeyサーバーとの通信に使用\n'
                  '• ストレージ（写真・メディア）: 画像・動画の添付および設定ファイルのエクスポートに使用\n\n'
                  '上記以外の権限は要求しません。',
            ),
            _Section(
              title: '8. お子様のプライバシー',
              body:
                  '本アプリは13歳未満の方を対象としていません。'
                  '13歳未満の方の個人情報を意図的に収集することはありません。',
            ),
            _Section(
              title: '9. プライバシーポリシーの変更',
              body:
                  '本ポリシーは予告なく変更されることがあります。'
                  '変更後のポリシーはGitHubリポジトリまたはアプリ内に掲載します。',
            ),
            _Section(
              title: '10. お問い合わせ',
              body:
                  'プライバシーポリシーに関するご質問は、GitHubリポジトリのIssue、または開発者のMisskeyアカウントにお寄せください。',
            ),
            SizedBox(height: 16),
            Text(
              '制定日: 2026年4月1日',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
