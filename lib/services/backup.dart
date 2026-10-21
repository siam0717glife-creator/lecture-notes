import 'dart:io';

import 'package:archive/archive_io.dart';

import 'lecture_store.dart';

/// すべての会議（文字起こし・要約・録音など）を1つの zip ファイルにまとめたり、
/// その zip から会議を戻したりする。
///
/// データはスマホの中にしか無いので、Google ドライブなどに置いておけば
/// 機種変更やアプリの入れ直しのあとでも戻せる。
class Backup {
  /// 会議をすべて zip にまとめ、[outDir] に書き出したファイルを返す。
  static Future<File> export(
    LectureStore store,
    Directory outDir, {
    DateTime? now,
  }) async {
    final lectures = await store.list();
    if (lectures.isEmpty) {
      throw const BackupException('バックアップする会議がありません。');
    }
    final at = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'gijiroku_backup_${at.year}${two(at.month)}${two(at.day)}_${two(at.hour)}${two(at.minute)}.zip';
    final file = File('${outDir.path}/$name');
    if (await file.exists()) await file.delete();
    final encoder = ZipFileEncoder()..create(file.path);
    for (final lecture in lectures) {
      await encoder.addDirectory(lecture.dir);
    }
    await encoder.close();
    return file;
  }

  /// zip から会議を戻し、戻した件数を返す。
  ///
  /// すでにある会議は上書きせず、そのままにする。
  static Future<int> restore(
    LectureStore store,
    File zip,
    Directory tempDir,
  ) async {
    final work = await tempDir.createTemp('restore');
    try {
      final input = InputFileStream(zip.path);
      try {
        final archive = ZipDecoder().decodeStream(input);
        await extractArchiveToDisk(archive, work.path);
      } catch (_) {
        throw const BackupException('バックアップのファイルとして読み込めませんでした。');
      } finally {
        await input.close();
      }
      var restored = 0;
      var found = 0;
      await for (final entity in work.list()) {
        if (entity is! Directory) continue;
        if (!await File('${entity.path}/meta.json').exists()) continue;
        found++;
        final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
        final target = Directory('${store.root.path}/$name');
        if (await target.exists()) continue;
        await _copyDir(entity, target);
        restored++;
      }
      if (found == 0) {
        throw const BackupException('このファイルには会議が入っていませんでした。');
      }
      return restored;
    } finally {
      await work.delete(recursive: true);
    }
  }

  static Future<void> _copyDir(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list()) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (entity is File) {
        await entity.copy('${to.path}/$name');
      } else if (entity is Directory) {
        await _copyDir(entity, Directory('${to.path}/$name'));
      }
    }
  }
}

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}
