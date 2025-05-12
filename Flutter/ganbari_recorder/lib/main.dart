import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:table_calendar/table_calendar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));

  final notificationService = NotificationService();
  await notificationService.init();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, String> recordMap = {};
  DateTime focusedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadRecords();

    NotificationService().onRecordAdded = (String result) {
      _addRecord(result);
    };

    NotificationService().scheduleDailyNotification();
  }

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

  void _addRecord(String result) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String date = DateTime.now().toIso8601String().split('T')[0];
    recordMap[date] = result;
    List<String> records = recordMap.entries
        .map((entry) => "記録日: ${entry.key} - ${entry.value}")
        .toList();
    await prefs.setStringList('records', records);
    setState(() {});
  }

  void _deleteRecordByDate(String date) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    recordMap.remove(date);
    List<String> records = recordMap.entries
        .map((entry) => "記録日: ${entry.key} - ${entry.value}")
        .toList();
    await prefs.setStringList('records', records);
    setState(() {});
  }

  void _clearRecords() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('records');
    setState(() {
      recordMap.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("頑張り記録")),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: focusedDay,
            calendarFormat: CalendarFormat.month,
            onDaySelected: (selectedDay, newFocusedDay) {
              setState(() {
                focusedDay = newFocusedDay;
              });
              String key = selectedDay.toIso8601String().split('T')[0];
              String? result = recordMap[key];
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text("記録"),
                  content: Text(result != null
                      ? "$key の記録: $result"
                      : "$key に記録はありません。"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text("OK"),
                    ),
                  ],
                ),
              );
            },
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                final dateKey = day.toIso8601String().split('T')[0];
                final result = recordMap[dateKey];

                if (result != null) {
                  String emoji = result == '勝ち' ? '🟢' : '🔴';

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${day.day}',
                        style: TextStyle(fontSize: 14),
                      ),
                      Text(
                        emoji,
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  );
                }

                return null; // 通常通り描画
              },
            ),
          ),

          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () => _addRecord("勝ち"),
                child: Text("勝ち"),
              ),
              ElevatedButton(
                onPressed: () => _addRecord("負け"),
                child: Text("負け"),
              ),
              ElevatedButton(
                onPressed: _clearRecords,
                child: Text("クリア"),
              ),
            ],
          ),
          SizedBox(height: 20),
        ],
      ),
    );
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  void Function(String result)? onRecordAdded;

  Future<void> init() async {
    const AndroidInitializationSettings androidInitSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initSettings =
        InitializationSettings(android: androidInitSettings);

    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        final actionId = details.actionId;

        if (details.notificationResponseType ==
            NotificationResponseType.selectedNotificationAction) {
          if (actionId == 'yes_action') {
            _saveRecord('勝ち');
          } else if (actionId == 'no_action') {
            _saveRecord('負け');
          }
        }
      },
    );
    scheduleDailyNotification();
    await requestExactAlarmPermission();
  }

  Future<void> requestExactAlarmPermission() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

    if (androidInfo.version.sdkInt >= 31) {
      final permission = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestExactAlarmsPermission();

      if (permission == true) {
        print("🔔 正確なアラームの権限が許可されました");
      } else {
        print("⚠️ 正確なアラームの権限が拒否されました");
      }
    }
  }

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

  void scheduleDailyNotification() async {
    print("🔔 scheduleDailyNotification() を開始");

    final location = tz.getLocation('Asia/Tokyo');
    final now = tz.TZDateTime.now(location);

    tz.TZDateTime scheduledDate = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      23,
      0,
    );

    if (now.isAfter(scheduledDate)) {
      scheduledDate = scheduledDate.add(Duration(days: 1));
    }

    print("📅 現在時刻: $now");
    print("📅 通知予定時刻（毎日23時）: $scheduledDate");

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'daily_notify',
      'Daily Notifications',
      channelDescription: '毎日23時の習慣通知',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction(
          'yes_action',
          'Yes',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'no_action',
          'No',
          showsUserInterface: true,
        ),
      ],
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        0,
        '今日の頑張り',
        getRandomMessage(),
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      print("✅ 通知スケジュール完了: $scheduledDate");
    } catch (e) {
      print("❌ 通知スケジュール失敗: $e");
    }
  }

  void _saveRecord(String response) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> records = prefs.getStringList('records') ?? [];
    String date = DateTime.now().toIso8601String().split('T')[0];
    records.removeWhere((record) => record.startsWith("記録日: $date -"));
    records.add("記録日: $date - $response");
    await prefs.setStringList('records', records);
    onRecordAdded?.call(response);
  }
}
