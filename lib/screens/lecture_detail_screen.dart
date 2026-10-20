import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/lecture_note_prompt.dart';
import '../services/lecture_store.dart';

/// 保存した講義の要約と文字起こし全文を表示する画面。
///
/// 要約は無料の Claude アプリで作ってもらい、返ってきた文章を貼り付けて保存する。
class LectureDetailScreen extends StatefulWidget {
  final LectureStore store;
  final Lecture lecture;
  const LectureDetailScreen({
    super.key,
    required this.store,
    required this.lecture,
  });

  @override
  State<LectureDetailScreen> createState() => _LectureDetailScreenState();
}

class _LectureDetailScreenState extends State<LectureDetailScreen> {
  String? _transcript;
  String? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final transcript = await widget.store.readTranscript(widget.lecture);
    final summary = await widget.store.readSummary(widget.lecture);
    if (!mounted) return;
    setState(() {
      _transcript = transcript;
      _summary = summary;
    });
  }

  /// 要約の指示と文字起こしを、共有メニューから Claude アプリに渡す。
  Future<void> _shareToClaudeApp() async {
    final text = LectureNotePrompt.build(
      title: widget.lecture.title,
      transcript: _transcript ?? '',
    );
    await SharePlus.instance.share(
      ShareParams(text: text, subject: '${widget.lecture.title} の講義ノート'),
    );
  }

  /// Claude アプリでコピーした要約を、この講義の要約として保存する。
  Future<void> _pasteSummary() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('コピーされた文章がありません。Claude アプリで要約をコピーしてください。'),
        ),
      );
      return;
    }
    await widget.store.saveSummary(widget.lecture, text);
    if (!mounted) return;
    setState(() => _summary = text);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('要約を保存しました')));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('この講義を削除しますか？'),
        content: const Text('文字起こし・要約・録音が消えます。元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('やめる'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.store.delete(widget.lecture);
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('コピーしました')));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.lecture.title),
          actions: [
            IconButton(
              tooltip: '削除',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '要約'),
              Tab(text: '文字起こし'),
            ],
          ),
        ),
        body: _transcript == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [_buildSummary(), _buildTranscript()]),
      ),
    );
  }

  Widget _buildSummary() {
    final theme = Theme.of(context);
    final summary = _summary ?? '';
    if ((_transcript ?? '').trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '文字起こしが無いので、要約できません。',
          style: TextStyle(color: theme.colorScheme.outline),
        ),
      );
    }
    final steps = theme.textTheme.bodyMedium;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (summary.isEmpty) ...[
          Text('Claude アプリ（無料）で要約を作れます。', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text('1. 下の「Claudeアプリで要約する」を押し、共有先で Claude を選ぶ', style: steps),
          Text('2. Claude アプリで送信し、返ってきた要約をコピーする', style: steps),
          Text('3. このアプリに戻り「コピーした要約を貼り付けて保存」を押す', style: steps),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: _shareToClaudeApp,
          icon: const Icon(Icons.share),
          label: Text(summary.isEmpty ? 'Claudeアプリで要約する' : 'Claudeアプリで要約し直す'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pasteSummary,
          icon: const Icon(Icons.content_paste),
          label: const Text('コピーした要約を貼り付けて保存'),
        ),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Text('保存した要約', style: theme.textTheme.titleSmall),
              const Spacer(),
              IconButton(
                tooltip: '要約をコピー',
                icon: const Icon(Icons.copy),
                onPressed: () => _copy(summary),
              ),
            ],
          ),
          SelectableText(
            summary,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
        ],
      ],
    );
  }

  Widget _buildTranscript() {
    final text = _transcript ?? '';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                text.isEmpty ? '文字起こしはありません。' : '${text.length}文字',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            if (text.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('全文コピー'),
                onPressed: () => _copy(text),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(text, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}
