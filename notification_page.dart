import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  final DatabaseReference database =
      FirebaseDatabase.instance.ref("motorcycle");

  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  String alertText = "Waiting for motorcycle data...";

  String motionLevel = "0";

  @override
  void initState() {
    super.initState();

    initializeNotification();

    listenForMotion();
  }

  Future<void> initializeNotification() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await notificationsPlugin.initialize(
      settings,
    );
  }

  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'motion_channel',
      'Motion Alerts',
      channelDescription: 'MotoGuard motorcycle notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await notificationsPlugin.show(
      0,
      title,
      body,
      details,
    );
  }

  void listenForMotion() {
    database.onValue.listen((event) {
      final data = event.snapshot.value;

      if (data == null) return;

      try {
        final map = Map<String, dynamic>.from(data as Map);

        String level = map['level'].toString();

        if (level == motionLevel) return;

        motionLevel = level;

        // LEVEL 1
        if (level == "1") {
          setState(() {
            alertText = "⚠ Motion Level 1 Detected";
          });

          showNotification(
            title: "MotoGuard Alert",
            body: "Movement detected on motorcycle!",
          );
        }

        // LEVEL 2
        else if (level == "2") {
          setState(() {
            alertText = "🚨 ACCIDENT DETECTED";
          });

          showNotification(
            title: "Emergency Alert",
            body: "Strong impact detected!",
          );
        }

        // NORMAL
        else {
          setState(() {
            alertText = "✅ System Normal";
          });
        }
      } catch (e) {
        debugPrint(
          "Firebase Error: $e",
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF060B14),
        title: const Text(
          "Notifications",
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.notifications_active,
                size: 120,
                color: Colors.red,
              ),
              const SizedBox(height: 30),
              Text(
                alertText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "Motion Level: $motionLevel",
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
