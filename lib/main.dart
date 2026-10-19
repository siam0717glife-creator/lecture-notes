import 'package:flutter/material.dart';

import 'screens/lecture_detail_screen.dart';
import 'screens/recording_screen.dart';
import 'screens/settings_screen.dart';
import 'services/lecture_store.dart';
import 'services/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final store = await LectureStore.open();
  runApp(LectureNotesApp(settings: settings, store: store));
}

class LectureNotesApp extends StatelessWidget {
  final AppSettings settings;
  final LectureStore store;
  const LectureNotesApp({
    super.key,
    required this.settings,
    required this.store,
  });

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
      home: HomeScreen(settings: settings, store: store),
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecordingScreen(
          store: widget.store,
          settings: widget.settings,
          title: title,
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
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          LectureDetailScreen(store: widget.store, lecture: l),
                    ),
                  );
                  _reload();
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
