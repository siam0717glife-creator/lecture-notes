import 'package:flutter/material.dart';

import '../services/settings.dart';

/// 音声認識のAPIキーを入力する画面。
class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _key = TextEditingController(text: widget.settings.deepgramApiKey);
  late final _model = TextEditingController(text: widget.settings.model);
  late final _geminiKey = TextEditingController(
    text: widget.settings.geminiApiKey,
  );
  bool _hidden = true;
  bool _geminiHidden = true;

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    _geminiKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.settings.setDeepgramApiKey(_key.text);
    await widget.settings.setModel(_model.text);
    await widget.settings.setGeminiApiKey(_geminiKey.text);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '文字起こしには Deepgram の音声認識を使います。'
            'deepgram.com で無料登録し、作成した API キーを貼り付けてください。',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _key,
            obscureText: _hidden,
            decoration: InputDecoration(
              labelText: 'Deepgram API キー',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _model,
            decoration: const InputDecoration(
              labelText: '認識モデル（通常は変更不要）',
              helperText: '日本語がうまく認識されないときは nova-2 を試してください',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            '要約には Google の Gemini（無料枠）を使います。'
            'aistudio.google.com で「Get API key」からキーを作り、貼り付けてください。'
            '無料枠では、送った内容が Google の AI 改善に使われることがあります。',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _geminiKey,
            obscureText: _geminiHidden,
            decoration: InputDecoration(
              labelText: 'Gemini API キー',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _geminiHidden ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () => setState(() => _geminiHidden = !_geminiHidden),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
    );
  }
}
