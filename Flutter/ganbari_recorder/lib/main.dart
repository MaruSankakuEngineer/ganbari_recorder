// main.dart
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:table_calendar/table_calendar.dart';
import 'setting.dart';

const String notificationHourKey = 'notification_hour';
const String notificationMinuteKey = 'notification_minute';

/// アプリのエントリーポイント。通知サービスを初期化し、アプリを起動する。
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  handleInitialNotificationIfNeeded();
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));

  final notificationService = NotificationService();
  await notificationService.init();
  runApp(MyApp());
}

/// アプリのルートウィジェット。
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

/// ユーザーの頑張り記録を表示・登録するカレンダー画面。
class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final NotificationService _notificationService = NotificationService();
  Map<String, String> recordMap = {};
  DateTime focusedDay = DateTime.now();

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
    _loadRecords();
    _notificationService.onRecordAdded = (String date, String result) {
      _addRecordForDate(date, result);
    };
    _notificationService.scheduleDailyNotification();
  }

  /// SharedPreferencesから記録を読み込む。
  void _loadRecords() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> records = prefs.getStringList('records') ?? [];
    Map<String, String> map = {};
    for (var record in records) {
      final match = RegExp(r"記録日: (\d{4}-\d{2}-\d{2}) - (.+)").firstMatch(record);
      if (match != null) {
        map[match.group(1)!] = match.group(2)!;
      }
    }
    setState(() {
      recordMap = map;
    });
  }

  /// 指定日に記録を追加して保存。
  Future<void> _addRecordForDate(String date, String result) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    recordMap[date] = result;
    List<String> records = recordMap.entries
        .map((entry) => "記録日: ${entry.key} - ${entry.value}")
        .toList();
    await prefs.setStringList('records', records);
  print('[静的保存] \$date - \$response を保存完了');
    setState(() {});
  }

  /// 表示中の月の勝ち負け数をカウント。
  Map<String, int> _countWinLossThisMonth() {
    final int year = focusedDay.year;
    final int month = focusedDay.month;
    int win = 0;
    int loss = 0;
    recordMap.forEach((key, value) {
      final date = DateTime.tryParse(key);
      if (date != null && date.year == year && date.month == month) {
        if (value == '勝ち') win++;
        if (value == '負け') loss++;
      }
    });
    return {'勝ち': win, '負け': loss};
  }

  /// 勝ち負けの割合バーを表示するウィジェット。
  Widget _monthlyWinLossBarWidget() {
    final counts = _countWinLossThisMonth();
    final int win = counts['勝ち']!;
    final int loss = counts['負け']!;
    final int total = win + loss;

    if (total == 0) {
      return Text("${focusedDay.month}月の記録がありません", style: TextStyle(fontSize: 16));
    }

    final double winRatio = win / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("${focusedDay.month}月の勝ち負け： 勝ち: $win / 負け: $loss", style: TextStyle(fontSize: 16)),
        SizedBox(height: 8),
        Stack(
          children: [
            Container(
              height: 20,
              decoration: BoxDecoration(color: Colors.red.shade300, borderRadius: BorderRadius.circular(10)),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: winRatio,
              child: Container(
                height: 20,
                decoration: BoxDecoration(color: Colors.green.shade400, borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("頑張り記録"),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SettingPage(onTimeUpdated: () async {
              await _notificationService.rescheduleNotification();
            }))),
          ),
        ],
      ),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: focusedDay,
            calendarFormat: CalendarFormat.month,
            onDaySelected: (selectedDay, newFocusedDay) {
              setState(() { focusedDay = newFocusedDay; });
              String key = selectedDay.toIso8601String().split('T')[0];
              String? result = recordMap[key];
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text("記録"),
                  content: Text(result != null ? "$key の記録: $result" : "$key に記録はありません。"),
                  actions: [
                    if (result == null) ...[
                      TextButton(onPressed: () async { await _addRecordForDate(key, "勝ち"); Navigator.pop(context); }, child: Text("勝ちとして記録")),
                      TextButton(onPressed: () async { await _addRecordForDate(key, "負け"); Navigator.pop(context); }, child: Text("負けとして記録")),
                    ],
                    TextButton(onPressed: () => Navigator.pop(context), child: Text("OK")),
                  ],
                ),
              );
            },
            onPageChanged: (newFocusedDay) {
              setState(() { focusedDay = newFocusedDay; });
            },
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                final dateKey = day.toIso8601String().split('T')[0];
                final result = recordMap[dateKey];
                if (result != null) {
                  String emoji = result == '勝ち' ? '🟢' : '🔴';
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Text('${day.day}', style: TextStyle(fontSize: 14)), Text(emoji, style: TextStyle(fontSize: 14))],
                  );
                }
                return null;
              },
            ),
          ),
          SizedBox(height: 20),
          _monthlyWinLossBarWidget(),
          SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// 通知を管理するサービス。通知のスケジューリングや応答処理を担当。
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  void Function(String date, String result)? onRecordAdded;

  /// 通知プラグインを初期化し、通知をスケジュール。アラーム権限も確認。
  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final initSettings = InitializationSettings(android: androidInit);
    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
          );
    scheduleDailyNotification();
    await requestExactAlarmPermission();
  }

  /// 通知を再スケジュール。
  Future<void> rescheduleNotification() async {
    await flutterLocalNotificationsPlugin.cancelAll();
    await scheduleDailyNotification();
  }

  /// 通知の応答を処理。
  void _handleNotificationResponse(NotificationResponse details) {
    final actionId = details.actionId;
    if (details.notificationResponseType == NotificationResponseType.selectedNotificationAction) {
      if (actionId == 'yes_action') {
        _saveRecord('勝ち');
      } else if (actionId == 'no_action') {
        _saveRecord('負け');
      }
    }
  }

  /// 正確なアラーム権限をリクエスト（Android 12以降）。
  Future<void> requestExactAlarmPermission() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    if (androidInfo.version.sdkInt >= 31) {
      final permission = await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestExactAlarmsPermission();
      print(permission == true ? "🔔 アラーム許可あり" : "⚠️ アラーム許可なし");
    }
  }

  /// 通知に使用するメッセージをランダムに取得。
  String getRandomMessage() {
    final messages = [
      '今日、やるべきことに取り組めた？',
      '少しでも前に進めたって感じた？',
      '何か一歩進めた？',
      '自分との約束を守れた？',
      '昨日よりちょっとだけ成長できた？',
      '今日の自分を褒められる？',
      '一日を自分らしく過ごせた？',
      '小さな達成感、味わえた？',
      '今日は「やりきった」って思えた？',
      '今の自分にできることをやった？'
    ];
    messages.shuffle();
    return messages.first;
  }

  /// 毎日指定時刻に通知をスケジュール。
  Future<void> scheduleDailyNotification() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(notificationHourKey) ?? 23;
    final minute = prefs.getInt(notificationMinuteKey) ?? 0;
    final location = tz.getLocation('Asia/Tokyo');
    final now = tz.TZDateTime.now(location);
    tz.TZDateTime scheduledDate = tz.TZDateTime(location, now.year, now.month, now.day, hour, minute);
    if (now.isAfter(scheduledDate)) scheduledDate = scheduledDate.add(Duration(days: 1));

    const androidDetails = AndroidNotificationDetails(
      'daily_notify', 'Daily Notifications',
      channelDescription: '毎日指定時刻の習慣通知', importance: Importance.high, priority: Priority.high,
      actions: [
        AndroidNotificationAction('yes_action', 'Yes', showsUserInterface: true),
        AndroidNotificationAction('no_action', 'No', showsUserInterface: true),
      ],
    );

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        0,
        '今日の頑張り',
        getRandomMessage(),
        scheduledDate,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      print("✅ 通知スケジュール: $scheduledDate");
    } catch (e) {
      print("❌ 通知スケジュール失敗: $e");
    }
  }

  /// 勝ち負け記録を保存し、コールバックを呼び出す。
  void _saveRecord(String response) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> records = prefs.getStringList('records') ?? [];
    final date = DateTime.now().toIso8601String().split('T')[0];
    records.removeWhere((record) => record.startsWith("記録日: $date -"));
    records.add("記録日: $date - $response");
    await prefs.setStringList('records', records);
    onRecordAdded?.call(date, response);
  }
}

/// バックグラウンドで通知の応答を処理する関数。
// 通知タップ時にアプリが起動されたら通知内容を処理する
void handleInitialNotificationIfNeeded() async {
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  final NotificationAppLaunchDetails? launchDetails =
      await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();

  if (launchDetails?.didNotificationLaunchApp ?? false) {
    final String? actionId = launchDetails!.notificationResponse?.actionId;
    if (actionId == 'yes_action') {
      NotificationService()._saveRecord('勝ち');
    } else if (actionId == 'no_action') {
      NotificationService()._saveRecord('負け');
    }
  }
}

/// バックグラウンドでの記録保存用の静的関数。
@pragma('vm:entry-point')
Future<void> _saveRecordStatic(String response) async {
  print('[静的保存] 保存開始');
  final prefs = await SharedPreferences.getInstance();
  List<String> records = prefs.getStringList('records') ?? [];
  final date = DateTime.now().toIso8601String().split('T')[0];
  records.removeWhere((record) => record.startsWith("記録日: $date -"));
  records.add("記録日: $date - $response");
  await prefs.setStringList('records', records);
}
