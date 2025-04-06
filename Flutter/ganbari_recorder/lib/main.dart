import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));
  await NotificationService().init();
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
  List<String> records = [];

  @override
  void initState() {
    super.initState();
    _loadRecords();
    NotificationService().onRecordAdded = () {
      _loadRecords();
    };
    NotificationService().scheduleDailyNotification();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadRecords();
  }

  void _loadRecords() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      records = prefs.getStringList('records') ?? [];
    });
  }

  void _addRecord(String result) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> records = prefs.getStringList('records') ?? [];
    String date = DateTime.now().toIso8601String().split('T')[0];
    records.add("記録日: $date - $result");
    await prefs.setStringList('records', records);
    setState(() {
      this.records = records;
    });
  }

  void _clearRecords() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('records');
    setState(() {
      records = [];
    });
  }

  void checkScheduledNotifications() async {
    final List<PendingNotificationRequest> pendingNotifications =
        await NotificationService().flutterLocalNotificationsPlugin.pendingNotificationRequests();

    print("📅 スケジュール済み通知の数: ${pendingNotifications.length}");
    for (var notification in pendingNotifications) {
      print("🔔 ID: ${notification.id}, タイトル: ${notification.title}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("頑張り記録")),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: records.length,
              itemBuilder: (context, index) {
                return ListTile(title: Text(records[index]));
              },
            ),
          ),
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
          SizedBox(height: 10),
        ],
      ),
    );
  }
}

class NotificationService {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  VoidCallback? onRecordAdded;

  Future<void> init() async {
    const AndroidInitializationSettings androidInitSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initSettings =
        InitializationSettings(android: androidInitSettings);

    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        final actionId = details.actionId;

        if (actionId == 'yes_action') {
          _saveRecord('勝ち');
        } else if (actionId == 'no_action') {
          _saveRecord('負け');
        } else {
          print("🔔 通知がタップされました");
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
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
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
      '今日はどんな1日だった？',
      '何か一歩進めた？',
      '自分に拍手したいことは？',
      'ちゃんと休めた？',
      '今日もお疲れさま！',
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
        AndroidNotificationAction('yes_action', 'Yes'),
        AndroidNotificationAction('no_action', 'No'),
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
    records.add("記録日: $date - $response");
    await prefs.setStringList('records', records);
    onRecordAdded?.call();
  }
}
