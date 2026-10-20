import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/claude_summarizer.dart';
import '../services/lecture_store.dart';
import '../services/settings.dart';
import 'settings_screen.dart';

/// 保存した講義の要約と文字起こし全文を表示する画面。
///
/// 要約がまだ無ければ、開いたときに自動で作り始める。
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
        widget.settings.anthropicApiKey.isNotEmpty) {
      _summarize();
    }
  }

  Future<void> _summarize() async {
    final transcript = _transcript ?? '';
    if (transcript.trim().isEmpty || _summarizing) return;
    if (widget.settings.anthropicApiKey.isEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SettingsScreen(settings: widget.settings),
        ),
      );
      if (widget.settings.anthropicApiKey.isEmpty) return;
    }
    final buffer = StringBuffer();
    setState(() {
      _summarizing = true;
      _summaryError = null;
      _summary = '';
    });
    final summarizer = ClaudeSummarizer(
      apiKey: widget.settings.anthropicApiKey,
    );
    _summarySub = summarizer
        .summarize(title: widget.lecture.title, transcript: transcript)
        .listen(
          (chunk) {
            buffer.write(chunk);
            if (mounted) setState(() => _summary = buffer.toString());
          },
          onError: (Object e) async {
            // 途中までの要約は不完全なので保存しない。
            final saved = await widget.store.readSummary(widget.lecture);
            if (!mounted) return;
            setState(() {
              _summarizing = false;
              _summaryError = e.toString();
              _summary = saved;
            });
          },
          onDone: () async {
            if (_summaryError != null) return;
            final text = buffer.toString().trim();
            if (text.isNotEmpty) {
              await widget.store.saveSummary(widget.lecture, text);
            }
            if (mounted) setState(() => _summarizing = false);
          },
          cancelOnError: true,
        );
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
    final transcriptEmpty = (_transcript ?? '').trim().isEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (transcriptEmpty)
          Text(
            '文字起こしが無いので、要約できません。',
            style: TextStyle(color: theme.colorScheme.outline),
          )
        else
          Row(
            children: [
              if (_summarizing) ...[
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                const Expanded(child: Text('Claude が要約を書いています…')),
              ] else ...[
                FilledButton.tonalIcon(
                  onPressed: _summarize,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(summary.isEmpty ? '要約する' : '要約を作り直す'),
                ),
                const Spacer(),
                if (summary.isNotEmpty)
                  IconButton(
                    tooltip: '要約をコピー',
                    icon: const Icon(Icons.copy),
                    onPressed: () => _copy(summary),
                  ),
              ],
            ],
          ),
        if (_summaryError != null) ...[
          const SizedBox(height: 12),
          Text(
            _summaryError!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        SelectableText(
          summary,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
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
