import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/deepgram_transcriber.dart';
import '../services/lecture_store.dart';
import '../services/settings.dart';
import '../services/transcript_buffer.dart';
import '../services/wav_writer.dart';

/// 録音しながら、文字起こしをリアルタイムで表示する画面。
class RecordingScreen extends StatefulWidget {
  final LectureStore store;
  final AppSettings settings;
  final String title;

  const RecordingScreen({
    super.key,
    required this.store,
    required this.settings,
    required this.title,
  });

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final _recorder = AudioRecorder();
  final _buffer = TranscriptBuffer();
  final _scroll = ScrollController();
  final _stopwatch = Stopwatch();

  DeepgramTranscriber? _transcriber;
  WavWriter? _wav;
  Lecture? _lecture;
  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription<TranscriptEvent>? _eventSub;
  Timer? _ticker;
  Future<void> _writeChain = Future.value();

  bool _starting = true;
  bool _stopping = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        throw 'マイクの使用が許可されていません。スマホの設定でこのアプリのマイクを許可してください。';
      }
      final lecture = await widget.store.create(title: widget.title);
      _lecture = lecture;

      final wav = WavWriter(
        lecture.audioFile,
        sampleRate: DeepgramTranscriber.sampleRate,
      );
      await wav.open();
      _wav = wav;

      final transcriber = DeepgramTranscriber(
        apiKey: widget.settings.deepgramApiKey,
        model: widget.settings.model,
      );
      _eventSub = transcriber.events.listen(_onTranscript, onError: _onError);
      await transcriber.connect();
      _transcriber = transcriber;

      final audio = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: DeepgramTranscriber.sampleRate,
          numChannels: 1,
          noiseSuppress: true,
        ),
      );
      _audioSub = audio.listen((chunk) {
        transcriber.sendAudio(chunk);
        _writeChain = _writeChain.then((_) => wav.add(chunk));
      });

      await WakelockPlus.enable();
      _stopwatch.start();
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
      setState(() => _starting = false);
    } catch (e) {
      _onError(e);
    }
  }

  void _onTranscript(TranscriptEvent event) {
    setState(
      () => _buffer.add(
        event.text,
        isFinal: event.isFinal,
        speaker: event.speaker,
      ),
    );
    if (event.isFinal && _lecture != null) {
      // 途中で落ちても消えないよう、文が確定するたびに保存する。
      widget.store.save(
        _lecture!,
        transcript: _buffer.finalText,
        duration: _stopwatch.elapsed,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onError(Object e) {
    if (!mounted) return;
    setState(() {
      _starting = false;
      _error = e.toString();
    });
  }

  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    _stopwatch.stop();
    _ticker?.cancel();
    await _recorder.stop();
    await _audioSub?.cancel();
    await _transcriber?.finish();
    await _eventSub?.cancel();
    _buffer.flushInterim();
    await _writeChain;
    await _wav?.close();
    Lecture? saved;
    if (_lecture != null) {
      saved = await widget.store.save(
        _lecture!,
        transcript: _buffer.finalText,
        duration: _stopwatch.elapsed,
      );
    }
    await WakelockPlus.disable();
    // 保存した講義を返し、そのまま要約画面に進めるようにする。
    if (mounted) Navigator.of(context).pop(saved);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _audioSub?.cancel();
    _eventSub?.cancel();
    _transcriber?.dispose();
    _recorder.dispose();
    _scroll.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  /// 録音が始まっていれば、エラーが出ても「録音を終える」で保存できるようにする。
  bool get _recordingStarted => _transcriber != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: _error != null && !_recordingStarted,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          automaticallyImplyLeading: _error != null && !_recordingStarted,
        ),
        body: Column(
          children: [
            _StatusBar(
              recording: !_starting && !_stopping && _error == null,
              elapsed: _formatElapsed(_stopwatch.elapsed),
            ),
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                leading: const Icon(Icons.error_outline),
                actions: [
                  TextButton(
                    onPressed: _recordingStarted
                        ? _stop
                        : () => Navigator.of(context).pop(false),
                    child: Text(_recordingStarted ? '保存して終える' : '戻る'),
                  ),
                ],
              ),
            Expanded(
              child: _starting
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final line in _buffer.finals)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(line, style: theme.textTheme.bodyLarge),
                          ),
                        if (_buffer.interim.isNotEmpty)
                          Text(
                            _buffer.interim,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        if (_buffer.finals.isEmpty && _buffer.interim.isEmpty)
                          Text(
                            '話し始めると、ここに文字が出ます。',
                            style: TextStyle(color: theme.colorScheme.outline),
                          ),
                      ],
                    ),
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: !_recordingStarted
            ? null
            : FloatingActionButton.extended(
                onPressed: _stopping ? null : _stop,
                icon: _stopping
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.stop),
                label: Text(_stopping ? '保存中…' : '録音を終える'),
              ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final bool recording;
  final String elapsed;
  const _StatusBar({required this.recording, required this.elapsed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: recording ? scheme.errorContainer : scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            recording ? Icons.fiber_manual_record : Icons.pause,
            color: recording ? scheme.error : scheme.outline,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(recording ? '録音・文字起こし中' : '停止中'),
          const Spacer(),
          Text(
            elapsed,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
