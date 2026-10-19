import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/lecture_store.dart';

/// 保存した講義の文字起こし全文を表示する画面。
class LectureDetailScreen extends StatelessWidget {
  final LectureStore store;
  final Lecture lecture;
  const LectureDetailScreen({
    super.key,
    required this.store,
    required this.lecture,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(lecture.title),
        actions: [
          IconButton(
            tooltip: '削除',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('この講義を削除しますか？'),
                  content: const Text('文字起こしと録音が消えます。元に戻せません。'),
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
                await store.delete(lecture);
                if (context.mounted) Navigator.of(context).pop(true);
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: store.readTranscript(lecture),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final text = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      text.isEmpty ? '文字起こしはありません。' : '${text.length}文字',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  if (text.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('全文コピー'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('コピーしました')),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                text,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          );
        },
      ),
    );
  }
}
