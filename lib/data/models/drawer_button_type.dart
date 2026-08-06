import 'package:flutter/material.dart';

/// ホームドロワーの表示/非表示をユーザーがカスタマイズできるボタンの種類。
///
/// ドロワー最上部（アカウント関連）と最下部（アプリ設定・アプリ情報）は
/// カスタマイズ対象外のため含まない。
enum DrawerButtonKey {
  search,
  announcements,
  directMessages,
  drive,
  drafts,
  clips,
  lists,
  antennas,
  favorites,
  channels,
  pages,
  gallery,
}

class DrawerButtonInfo {
  final DrawerButtonKey key;
  final String label;
  final IconData icon;

  const DrawerButtonInfo({
    required this.key,
    required this.label,
    required this.icon,
  });
}

/// カスタマイズ対象ボタンの一覧（ドロワー表示順）。
///
/// 新しいボタンをドロワーに追加する場合はここにも追記する。
/// [AppSettingsModel.hiddenDrawerButtons] に含まれないキーは自動的に
/// 「表示」扱いになるため、追加時に既存ユーザーの設定を壊すことはない。
const List<DrawerButtonInfo> kCustomizableDrawerButtons = [
  DrawerButtonInfo(
    key: DrawerButtonKey.search,
    label: '検索',
    icon: Icons.search,
  ),
  DrawerButtonInfo(
    key: DrawerButtonKey.announcements,
    label: 'お知らせ',
    icon: Icons.campaign_outlined,
  ),
  DrawerButtonInfo(
    key: DrawerButtonKey.directMessages,
    label: 'ダイレクトメッセージ',
    icon: Icons.mail_outline,
  ),
  DrawerButtonInfo(
    key: DrawerButtonKey.drive,
    label: 'ドライブ',
    icon: Icons.cloud_outlined,
  ),
  DrawerButtonInfo(
    key: DrawerButtonKey.drafts,
    label: '下書き',
    icon: Icons.edit_note,
  ),
  DrawerButtonInfo(
    key: DrawerButtonKey.clips,
    label: 'クリップ',
    icon: Icons.bookmark_outline,
  ),
  DrawerButtonInfo(key: DrawerButtonKey.lists, label: 'リスト', icon: Icons.list),
  DrawerButtonInfo(
    key: DrawerButtonKey.antennas,
    label: 'アンテナ',
    icon: Icons.settings_input_antenna,
  ),
  DrawerButtonInfo(
    key: DrawerButtonKey.favorites,
    label: 'お気に入り',
    icon: Icons.star_outline,
  ),
  DrawerButtonInfo(key: DrawerButtonKey.channels, label: 'チャンネル', icon: Icons.tv),
  DrawerButtonInfo(
    key: DrawerButtonKey.pages,
    label: 'ページ',
    icon: Icons.description_outlined,
  ),
  DrawerButtonInfo(
    key: DrawerButtonKey.gallery,
    label: 'ギャラリー',
    icon: Icons.collections_outlined,
  ),
];
