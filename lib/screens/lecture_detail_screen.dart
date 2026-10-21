import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';

import '../services/lecture_note_prompt.dart';
import '../services/lecture_store.dart';
import '../services/speaker_names.dart';
import '../services/transcript_edit.dart';

/// 保存した会議の要約と文字起こし全文を表示する画面。
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
  Map<String, String> _names = {};
  List<double?>? _lineStarts;
  final _player = AudioPlayer();
  bool _hasAudio = false;

  /// 話者の名前を置き換えた文字起こし。
  String get _namedTranscript => SpeakerNames.apply(_transcript ?? '', _names);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final transcript = await widget.store.readTranscript(widget.lecture);
    final summary = await widget.store.readSummary(widget.lecture);
    final names = await widget.store.readSpeakerNames(widget.lecture);
    final starts = await widget.store.readLineStarts(widget.lecture);
    var hasAudio = false;
    final audio = widget.lecture.audioFile;
    if (await audio.exists() && await audio.length() > 44) {
      try {
        await _player.setFilePath(audio.path);
        hasAudio = true;
      } catch (_) {
        // 再生できない録音なら、再生ボタンを出さない。
      }
    }
    if (!mounted) return;
    setState(() {
      _transcript = transcript;
      _summary = summary;
      _names = names;
      _lineStarts = starts;
      _hasAudio = hasAudio;
    });
  }

  /// 要約の指示と文字起こしを、共有メニューから Claude アプリに渡す。
  Future<void> _shareToClaudeApp() async {
    final text = LectureNotePrompt.build(
      title: widget.lecture.title,
      transcript: _namedTranscript,
    );
    await SharePlus.instance.share(
      ShareParams(text: text, subject: '${widget.lecture.title} の議事録'),
    );
  }

  /// Claude アプリでコピーした要約を、この会議の要約として保存する。
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

  /// 文字起こしの1行を直す。空にして保存するとその行を消す。
  Future<void> _editLine(int index) async {
    final raw = _transcript ?? '';
    final lines = raw.split('\n');
    if (index >= lines.length) return;
    final controller = TextEditingController(
      text: TranscriptEdit.body(lines[index]),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('文を直す'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(
            helperText: '空にして保存すると、この文を消します',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    final edited = TranscriptEdit.editLine(raw, _lineStarts, index, result);
    await widget.store.save(
      widget.lecture,
      transcript: edited.transcript,
      lineStarts: edited.starts,
    );
    if (mounted) {
      setState(() {
        _transcript = edited.transcript;
        _lineStarts = edited.starts;
      });
    }
  }

  /// 「話者1」などに、参加者の名前を付ける。
  Future<void> _renameSpeakers() async {
    final speakers = SpeakerNames.find(_transcript ?? '');
    final controllers = {
      for (final s in speakers) s: TextEditingController(text: _names[s] ?? ''),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('話者の名前'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in speakers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: controllers[s],
                    decoration: InputDecoration(
                      labelText: s,
                      hintText: '例：田中',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final names = {
      for (final e in controllers.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    };
    for (final c in controllers.values) {
      c.dispose();
    }
    if (ok != true) return;
    await widget.store.saveSpeakerNames(widget.lecture, names);
    if (mounted) setState(() => _names = names);
  }

  /// 文字起こしの行をタップしたとき、その発言の少し前から再生する。
  Future<void> _playFrom(double seconds) async {
    final ms = ((seconds - 1) * 1000).clamp(0, double.infinity).toInt();
    await _player.seek(Duration(milliseconds: ms));
    _player.play();
  }

  Future<void> _shareAudio() async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(widget.lecture.audioFile.path, mimeType: 'audio/wav')],
        subject: '${widget.lecture.title} の録音',
      ),
    );
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('この会議を削除しますか？'),
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
      await _player.stop();
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
            if (_hasAudio)
              IconButton(
                tooltip: '録音を共有',
                icon: const Icon(Icons.ios_share),
                onPressed: _shareAudio,
              ),
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
        bottomNavigationBar: _hasAudio ? _PlayerBar(player: _player) : null,
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
    final theme = Theme.of(context);
    final text = _namedTranscript;
    final hasSpeakers = SpeakerNames.find(_transcript ?? '').isNotEmpty;
    final lines = text.isEmpty ? <String>[] : text.split('\n');
    // 時刻の記録が行と合っていれば、行をタップして再生できる。
    final starts = _lineStarts?.length == lines.length ? _lineStarts : null;
    final canJump = _hasAudio && starts != null;
    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (context, snap) {
        final position = (snap.data ?? Duration.zero).inMilliseconds / 1000;
        var current = -1;
        if (canJump && _player.playing) {
          for (var i = 0; i < lines.length; i++) {
            final s = starts[i];
            if (s != null && s <= position + 0.5) current = i;
          }
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    text.isEmpty ? '文字起こしはありません。' : '${text.length}文字',
                    style: TextStyle(color: theme.colorScheme.outline),
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
            if (hasSpeakers)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.badge_outlined),
                  label: const Text('話者の名前を変える'),
                  onPressed: _renameSpeakers,
                ),
              ),
            if (lines.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  canJump
                      ? '文をタップするとその発言から再生、長押しすると文を直せます。'
                      : '文をタップすると、聞き間違いを直せます。',
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
              ),
            const SizedBox(height: 8),
            for (var i = 0; i < lines.length; i++)
              _TranscriptLine(
                text: lines[i],
                start: starts?[i],
                playing: i == current,
                onTap: canJump && starts[i] != null
                    ? () => _playFrom(starts[i]!)
                    : () => _editLine(i),
                onLongPress: () => _editLine(i),
              ),
          ],
        );
      },
    );
  }
}

/// 文字起こしの1行。左に話し始めた時刻を出し、タップでそこから再生する。
class _TranscriptLine extends StatelessWidget {
  final String text;
  final double? start;
  final bool playing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const _TranscriptLine({
    required this.text,
    required this.start,
    required this.playing,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: playing ? theme.colorScheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (start != null)
                SizedBox(
                  width: 56,
                  child: Text(
                    start == null
                        ? ''
                        : formatTime(
                            Duration(milliseconds: (start! * 1000).round()),
                          ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 録音の再生・一時停止と、再生位置のつまみ。
class _PlayerBar extends StatelessWidget {
  final AudioPlayer player;
  const _PlayerBar({required this.player});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        // 高さを決めないと、つまみ（Slider）が画面いっぱいに広がってしまう。
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: StreamBuilder<Duration>(
            stream: player.positionStream,
            builder: (context, snap) {
              final total = player.duration ?? Duration.zero;
              var pos = snap.data ?? Duration.zero;
              if (pos > total) pos = total;
              return Row(
                children: [
                  StreamBuilder<PlayerState>(
                    stream: player.playerStateStream,
                    builder: (context, s) {
                      final playing = s.data?.playing ?? false;
                      final done =
                          s.data?.processingState == ProcessingState.completed;
                      return IconButton(
                        tooltip: playing && !done ? '一時停止' : '再生',
                        icon: Icon(
                          playing && !done ? Icons.pause : Icons.play_arrow,
                        ),
                        onPressed: () async {
                          if (playing && !done) {
                            await player.pause();
                          } else {
                            if (done) await player.seek(Duration.zero);
                            player.play();
                          }
                        },
                      );
                    },
                  ),
                  Text(
                    formatTime(pos),
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: pos.inMilliseconds.toDouble(),
                      max: total.inMilliseconds.toDouble().clamp(
                        1,
                        double.infinity,
                      ),
                      onChanged: (v) =>
                          player.seek(Duration(milliseconds: v.round())),
                    ),
                  ),
                  Text(
                    formatTime(total),
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 時間を「12:34」や「1:02:03」の形にする。
String formatTime(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final m = d.inMinutes % 60;
  final sec = two(d.inSeconds % 60);
  return d.inHours > 0 ? '${d.inHours}:${two(m)}:$sec' : '$m:$sec';
}
