import 'package:shared_preferences/shared_preferences.dart';

/// アプリの設定（音声認識のAPIキーなど）を端末に保存する。
///
/// 試作版のため、APIキーはアプリの設定画面から入力して端末内に保存する。
/// 他の人に配る段階では、キーを中継サーバー側に移す。
class AppSettings {
  static const _keyDeepgramApiKey = 'deepgram_api_key';
  static const _keyModel = 'deepgram_model';
  static const _keyGeminiApiKey = 'gemini_api_key';
  static const defaultModel = 'nova-3';

  final SharedPreferences _prefs;
  AppSettings(this._prefs);

  static Future<AppSettings> load() async =>
      AppSettings(await SharedPreferences.getInstance());

  String get deepgramApiKey => _prefs.getString(_keyDeepgramApiKey) ?? '';
  Future<void> setDeepgramApiKey(String value) =>
      _prefs.setString(_keyDeepgramApiKey, value.trim());

  String get model => _prefs.getString(_keyModel) ?? defaultModel;
  Future<void> setModel(String value) => _prefs.setString(
    _keyModel,
    value.trim().isEmpty ? defaultModel : value.trim(),
  );

  String get geminiApiKey => _prefs.getString(_keyGeminiApiKey) ?? '';
  Future<void> setGeminiApiKey(String value) =>
      _prefs.setString(_keyGeminiApiKey, value.trim());
}
