import 'package:flutter/material.dart';

/// 画面を消すと録音が止まるときの、スマホ側の設定方法を案内する。
///
/// OPPO などのスマホは電池を長持ちさせるため、画面が消えたアプリを止めてしまう。
/// その対象から、このアプリを外してもらう。
Future<void> showBackgroundHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    title: const Text('画面を消しても録音を続けるには'),
    content: const SingleChildScrollView(
      child: Text(
        'スマホの電池を長持ちさせる機能が、画面が消えたアプリを止めてしまうことがあります。'
        '次の設定をすると止まりにくくなります（OPPO の場合）。\n\n'
        '1. スマホの「設定」を開く\n'
        '2.「アプリ」→「アプリ管理」→「議事録」を選ぶ\n'
        '3.「バッテリー使用」を開き、「バックグラウンドアクティビティを許可」をオンにする\n'
        '4. 設定のトップに戻り「バッテリー」を開き、「省電力モード」をオフにする\n\n'
        'あわせて、録音中は最近使ったアプリの一覧からこのアプリを消さないでください。'
        '機種によって言葉が少し違うことがあります。',
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('閉じる')),
    ],
  ),
);
