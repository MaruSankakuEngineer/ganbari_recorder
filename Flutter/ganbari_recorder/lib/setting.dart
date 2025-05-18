import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingPage extends StatefulWidget {
  final VoidCallback? onTimeUpdated;

  const SettingPage({Key? key, this.onTimeUpdated}) : super(key: key);

  @override
  _SettingPageState createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  TimeOfDay _selectedTime = TimeOfDay(hour: 23, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadSavedTime();
  }

  Future<void> _loadSavedTime() async {
    final prefs = await SharedPreferences.getInstance();
    int hour = prefs.getInt('notification_hour') ?? 23;
    int minute = prefs.getInt('notification_minute') ?? 0;
    setState(() {
      _selectedTime = TimeOfDay(hour: hour, minute: minute);
    });
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );

    if (picked != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('notification_hour', picked.hour);
      await prefs.setInt('notification_minute', picked.minute);

      setState(() {
        _selectedTime = picked;
      });

      // 🔁 通知再スケジュールコールバック
      widget.onTimeUpdated?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("通知時刻を ${picked.format(context)} に変更しました")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('設定')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('現在の通知時刻: ${_selectedTime.format(context)}'),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _pickTime,
              child: Text('通知時刻を変更'),
            ),
          ],
        ),
      ),
    );
  }
}
