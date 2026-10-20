import 'package:flutter/material.dart';

import 'screens/lecture_detail_screen.dart';
import 'screens/recording_screen.dart';
import 'screens/settings_screen.dart';
import 'services/lecture_store.dart';
import 'services/settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 本番版では画面の部品でエラーが起きると灰色の箱になるだけなので、内容を表示する。
  ErrorWidget.builder = (details) => _ErrorView(details.exceptionAsString());
  runApp(const LectureNotesApp());
}

/// 起動時に読み込むもの（設定と保存先）。
class _AppData {
  final AppSettings settings;
  final LectureStore store;
  _AppData(this.settings, this.store);

  static Future<_AppData> load() async {
    const limit = Duration(seconds: 10);
    final settings = await AppSettings.load().timeout(
      limit,
      onTimeout: () => throw '設定の読み込みが終わりません',
    );
    final store = await LectureStore.open().timeout(
      limit,
      onTimeout: () => throw '保存フォルダの準備が終わりません',
    );
    return _AppData(settings, store);
  }
}

class LectureNotesApp extends StatefulWidget {
  const LectureNotesApp({super.key});

  @override
  State<LectureNotesApp> createState() => _LectureNotesAppState();
}

class _LectureNotesAppState extends State<LectureNotesApp> {
  // 先に画面を出してから読み込み、失敗したら理由を表示する。
  late final Future<_AppData> _data = _AppData.load();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '講義録',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: FutureBuilder<_AppData>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(body: _ErrorView('起動できませんでした: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return HomeScreen(
            settings: snap.data!.settings,
            store: snap.data!.store,
          );
        },
      ),
    );
  }
}

/// エラーの内容を、スクリーンショットで送れるように表示する。
class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView(this.message);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Text(
              'エラーが起きました。この画面のスクリーンショットを送ってください。\n\n$message',
              style: const TextStyle(color: Colors.black, fontSize: 14),
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
      ),
    );
  }
}

/// 保存した講義の一覧と、録音開始ボタンがある最初の画面。
class HomeScreen extends StatefulWidget {
  final AppSettings settings;
  final LectureStore store;
  const HomeScreen({super.key, required this.settings, required this.store});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Lecture>> _lectures = widget.store.list();

  void _reload() => setState(() => _lectures = widget.store.list());

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(settings: widget.settings),
      ),
    );
    setState(() {});
  }

  Future<void> _startRecording() async {
    if (widget.settings.deepgramApiKey.isEmpty) {
      await _openSettings();
      if (widget.settings.deepgramApiKey.isEmpty) return;
    }
    if (!mounted) return;
    final title = await _askTitle();
    if (title == null || !mounted) return;
    final saved = await Navigator.of(context).push<Lecture>(
      MaterialPageRoute(
        builder: (_) => RecordingScreen(
          store: widget.store,
          settings: widget.settings,
          title: title,
        ),
      ),
    );
    _reload();
    // 録音が終わったら、そのまま講義の画面を開いて要約を始める。
    if (saved != null && mounted) await _openLecture(saved);
  }

  Future<void> _openLecture(Lecture lecture) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LectureDetailScreen(
          store: widget.store,
          settings: widget.settings,
          lecture: lecture,
        ),
      ),
    );
    _reload();
  }

  Future<String?> _askTitle() {
    final now = DateTime.now();
    final controller = TextEditingController(
      text:
          '${now.month}/${now.day} ${now.hour}:${now.minute.toString().padLeft(2, '0')} の講義',
    );
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('講義名'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              c,
              controller.text.trim().isEmpty ? '無題の講義' : controller.text.trim(),
            ),
            child: const Text('録音を始める'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) => d.inHours > 0
      ? '${d.inHours}時間${d.inMinutes % 60}分'
      : '${d.inMinutes}分${d.inSeconds % 60}秒';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('講義録'),
        actions: [
          IconButton(
            tooltip: '設定',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: FutureBuilder<List<Lecture>>(
        future: _lectures,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final lectures = snap.data!;
          if (lectures.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'まだ講義がありません。\n下のボタンで録音を始めましょう。',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: lectures.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final l = lectures[i];
              return ListTile(
                title: Text(l.title),
                subtitle: Text(
                  '${l.createdAt.year}/${l.createdAt.month}/${l.createdAt.day}・${_formatDuration(l.duration)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await _openLecture(l);
                },
              );
            },
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startRecording,
        icon: const Icon(Icons.mic),
        label: const Text('録音を始める'),
      ),
    );
  }
}
