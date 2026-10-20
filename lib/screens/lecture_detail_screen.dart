import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/gemini_summarizer.dart';
import '../services/lecture_note_prompt.dart';
import '../services/lecture_store.dart';
import '../services/settings.dart';
import 'settings_screen.dart';

/// 保存した講義の要約と文字起こし全文を表示する画面。
///
/// 要約がまだ無ければ、開いたときに Gemini（無料枠）で自動で作り始める。
/// Gemini が使えないときは、Claude アプリに渡して貼り付ける方法も選べる。
class LectureDetailScreen extends StatefulWidget {
  final LectureStore store;
  final AppSettings settings;
  final Lecture lecture;
  const LectureDetailScreen({
    super.key,
    required this.store,
    required this.settings,
    required this.lecture,
  });

  @override
  State<LectureDetailScreen> createState() => _LectureDetailScreenState();
}

class _LectureDetailScreenState extends State<LectureDetailScreen> {
  String? _transcript;
  String? _summary;
  bool _summarizing = false;
  String? _summaryError;
  StreamSubscription<String>? _summarySub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _summarySub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final transcript = await widget.store.readTranscript(widget.lecture);
    final summary = await widget.store.readSummary(widget.lecture);
    if (!mounted) return;
    setState(() {
      _transcript = transcript;
      _summary = summary;
    });
    if (summary == null &&
        transcript.trim().isNotEmpty &&
        widget.settings.geminiApiKey.isNotEmpty) {
      _summarize();
    }
  }

  /// Gemini で要約を作り、届いた分から画面に出す。終わったら保存する。
  Future<void> _summarize() async {
    final transcript = _transcript ?? '';
    if (transcript.trim().isEmpty || _summarizing) return;
    if (widget.settings.geminiApiKey.isEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SettingsScreen(settings: widget.settings),
        ),
      );
      if (!mounted || widget.settings.geminiApiKey.isEmpty) return;
    }
    final previous = _summary;
    final buffer = StringBuffer();
    setState(() {
      _summarizing = true;
      _summaryError = null;
      _summary = '';
    });
    _summarySub = GeminiSummarizer(apiKey: widget.settings.geminiApiKey)
        .summarize(title: widget.lecture.title, transcript: transcript)
        .listen(
          (chunk) {
            buffer.write(chunk);
            if (mounted) setState(() => _summary = buffer.toString());
          },
          onError: (Object e) {
            // 途中までの要約は不完全なので保存せず、前の要約に戻す。
            if (!mounted) return;
            setState(() {
              _summarizing = false;
              _summaryError = e.toString();
              _summary = previous;
            });
          },
          onDone: () async {
            final text = buffer.toString().trim();
            if (text.isNotEmpty) {
              await widget.store.saveSummary(widget.lecture, text);
            }
            if (mounted) setState(() => _summarizing = false);
          },
          cancelOnError: true,
        );
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
      await _summarySub?.cancel();
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_summarizing)
          const Row(
            children: [
              SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Expanded(child: Text('Gemini が要約を書いています…')),
            ],
          )
        else
          Row(
            children: [
              FilledButton.icon(
                onPressed: _summarize,
                icon: const Icon(Icons.auto_awesome),
                label: Text(summary.isEmpty ? '自動で要約する（無料）' : '要約を作り直す'),
              ),
              const Spacer(),
              if (summary.isNotEmpty)
                IconButton(
                  tooltip: '要約をコピー',
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copy(summary),
                ),
            ],
          ),
        if (_summaryError != null) ...[
          const SizedBox(height: 12),
          Text(
            _summaryError!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 16),
          SelectableText(
            summary,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
        ],
        if (!_summarizing) ...[
          const SizedBox(height: 24),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Claude アプリで要約する（予備の方法）'),
            subtitle: const Text('Gemini の無料回数を使い切ったときなどに'),
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '1.「Claudeアプリに送る」を押し、共有先で Claude を選んで送信\n'
                  '2. 返ってきた要約をコピー\n'
                  '3. ここに戻り「コピーした要約を貼り付けて保存」を押す',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _shareToClaudeApp,
                    icon: const Icon(Icons.share),
                    label: const Text('Claudeアプリに送る'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pasteSummary,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('コピーした要約を貼り付けて保存'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
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
