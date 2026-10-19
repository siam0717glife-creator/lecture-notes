import 'dart:io';
import 'dart:typed_data';

/// 16bit PCM の音声を、少しずつ WAV ファイルに書き込む。
///
/// 先に空のヘッダーを書いておき、閉じるときに長さを書き込む。
class WavWriter {
  final File file;
  final int sampleRate;
  final int channels;
  RandomAccessFile? _raf;
  int _dataBytes = 0;

  WavWriter(this.file, {this.sampleRate = 16000, this.channels = 1});

  int get dataBytes => _dataBytes;

  Future<void> open() async {
    _raf = await file.open(mode: FileMode.write);
    await _raf!.writeFrom(buildHeader(0));
  }

  Future<void> add(Uint8List pcm) async {
    final raf = _raf;
    if (raf == null) return;
    await raf.writeFrom(pcm);
    _dataBytes += pcm.length;
  }

  Future<void> close() async {
    final raf = _raf;
    if (raf == null) return;
    await raf.setPosition(0);
    await raf.writeFrom(buildHeader(_dataBytes));
    await raf.close();
    _raf = null;
  }

  Uint8List buildHeader(int dataLength) {
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final b = ByteData(44);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    b.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, channels, Endian.little);
    b.setUint32(24, sampleRate, Endian.little);
    b.setUint32(28, byteRate, Endian.little);
    b.setUint16(32, blockAlign, Endian.little);
    b.setUint16(34, bitsPerSample, Endian.little);
    ascii(36, 'data');
    b.setUint32(40, dataLength, Endian.little);
    return b.buffer.asUint8List();
  }
}
