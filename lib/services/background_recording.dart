import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// 画面を消したり別のアプリに切り替えたりしても、録音を止めないための仕組み。
///
/// Android は、通知を出している「フォアグラウンドサービス」がある間は
/// アプリを止めず、マイクも使わせてくれる。録音中は通知に「録音中」と出る。
class BackgroundRecording {
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'recording',
        channelName: '録音中の通知',
        channelDescription: '録音しているあいだ表示されます。',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: false,
        stopWithTask: true,
      ),
    );
  }

  static Future<void> start(String title) async {
    // Android 13 以降は、通知を出すのに許可がいる。
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (await FlutterForegroundTask.isRunningService) return;
    final result = await FlutterForegroundTask.startService(
      serviceId: 1001,
      serviceTypes: [ForegroundServiceTypes.microphone],
      notificationTitle: '会議を録音中',
      notificationText: title,
    );
    if (result is ServiceRequestFailure) throw result.error;
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
