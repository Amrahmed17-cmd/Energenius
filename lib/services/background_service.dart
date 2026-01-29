import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../database/database_helper.dart';
import 'dart:developer' as developer;

// Only import these packages when not on web
import 'package:flutter_background_service/flutter_background_service.dart'
    if (dart.library.html) './background_service_web.dart';

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  // Notification channel details
  static const String notificationChannelId = 'energenius_service_channel';
  static const String notificationChannelName = 'Energenius Energy Tracker';
  static const String notificationTitle = 'Energenius Energy Tracker';
  static const int notificationId = 888;

  // Background task names
  static const String periodicTaskName = 'energenius.periodic.update';
  static const String midnightTaskName = 'energenius.midnight.reset';
  static const String deviceUpdateTaskName = 'energenius.device.update';

  // Background service initialization
  Future<void> initializeService() async {
    // Only run on supported platforms
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        // Initialize mobile-specific background services
        await _initializeMobileService();
      } catch (e) {
        developer.log("Error initializing background service: $e");
      }
    } else {
      developer.log("Background service not supported on this platform");
      // For web, we'll use a different approach - periodic database updates
      _setupWebFallback();
    }
  }

  // Initialize service for mobile platforms
  Future<void> _initializeMobileService() async {
    if (kIsWeb) return; // Safety check

    try {
      // Setup notifications
      await _setupNotifications();

      // Initialize foreground service for Android
      if (Platform.isAndroid) {
        await _initializeAndroidForegroundService();
      }

      // Also set up in-app timers as a fallback
      _setupPeriodicUpdates();
      _setupMidnightCheck();
    } catch (e) {
      developer.log("Error in _initializeMobileService: $e");
    }
  }

  // Initialize Android foreground service
  Future<void> _initializeAndroidForegroundService() async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final service = FlutterBackgroundService();

      // Configure the foreground service
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onForegroundServiceStart,
          autoStart: true,
          isForegroundMode: true,
          notificationChannelId: notificationChannelId,
          initialNotificationTitle: notificationTitle,
          initialNotificationContent: 'Monitoring device energy consumption',
          foregroundServiceNotificationId: notificationId,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: true,
          onForeground: _onForegroundServiceStart,
          onBackground: _onIosBackground,
        ),
      );

      developer.log("Android foreground service initialized");
    } catch (e) {
      developer.log("Error initializing Android foreground service: $e");
    }
  }

  // Setup periodic updates for all platforms
  void _setupPeriodicUpdates() {
    Timer.periodic(const Duration(minutes: 2), (timer) async {
      if (FirebaseAuth.instance.currentUser != null) {
        final userId = FirebaseAuth.instance.currentUser!.uid;
        try {
          // Update device data
          await _updateActiveDevices(userId);
          developer.log(
            "Periodic update at ${DateTime.now().toIso8601String()}",
          );
        } catch (e) {
          developer.log("Error in periodic update: $e");
        }
      }
    });
  }

  // Setup web fallback for platforms that don't support background service
  void _setupWebFallback() {
    // Use the same periodic updates method
    _setupPeriodicUpdates();

    // Setup midnight reset check
    _setupMidnightCheck();
  }

  // Setup midnight check for all platforms
  void _setupMidnightCheck() {
    // Calculate time until next midnight
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = tomorrow.difference(now);

    // Set a one-time timer to trigger at midnight
    Timer(timeUntilMidnight, () async {
      if (FirebaseAuth.instance.currentUser != null) {
        final userId = FirebaseAuth.instance.currentUser!.uid;

        // Reset daily usage
        await DatabaseHelper.instance.checkAndResetDailyUsage(userId);
        developer.log("Midnight reset performed for user: $userId");

        // Set up the next day's timer
        _setupMidnightCheck();
      }
    });

    // Store the expected reset time in shared preferences
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('next_midnight_reset', tomorrow.toIso8601String());
      developer.log(
        "Midnight reset timer set for ${timeUntilMidnight.inHours} hours and ${timeUntilMidnight.inMinutes % 60} minutes from now",
      );
    });
  }

  // Setup notifications
  Future<void> _setupNotifications() async {
    if (!kIsWeb) {
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      const androidInitSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosInitSettings = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidInitSettings,
        iOS: iosInitSettings,
      );

      await flutterLocalNotificationsPlugin.initialize(initSettings);
    }
  }

  // Update all active devices' uptime and consumption
  static Future<void> _updateActiveDevices(String userId) async {
    try {
      // First check if reset needed
      await DatabaseHelper.instance.checkAndResetDailyUsage(userId);

      // Get all devices
      List<Map<String, dynamic>> devices = await DatabaseHelper.instance
          .getUserDevices(userId);

      // Update each active device
      for (var device in devices) {
        String deviceId = device['id'];
        bool isActive = device['last_active'] != null;

        if (isActive) {
          // Update active device's uptime
          await DatabaseHelper.instance.updateDeviceUptime(
            deviceId: deviceId,
            isActive: true,
          );
          developer.log("Updated uptime for device: ${device['model']}");
        }
      }

      // Send consumption data to update history
      await DatabaseHelper.instance.autoSendConsumptionData(userId);

      // Check if we missed a midnight reset
      await _checkForMissedMidnightReset(userId);
    } catch (e) {
      developer.log("Error updating active devices: $e");
    }
  }

  // Check if we missed a midnight reset
  static Future<void> _checkForMissedMidnightReset(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? nextResetStr = prefs.getString('next_midnight_reset');

      if (nextResetStr != null) {
        DateTime nextReset = DateTime.tryParse(nextResetStr) ?? DateTime.now();
        DateTime now = DateTime.now();

        // If we're past the scheduled reset time
        if (now.isAfter(nextReset)) {
          // Force a reset
          await DatabaseHelper.instance.checkAndResetDailyUsage(userId);

          // Calculate the next reset time
          final tomorrow = DateTime(now.year, now.month, now.day + 1);
          await prefs.setString(
            'next_midnight_reset',
            tomorrow.toIso8601String(),
          );

          developer.log("Performed missed midnight reset for user: $userId");
        }
      }
    } catch (e) {
      developer.log("Error checking for missed midnight reset: $e");
    }
  }

  // Foreground service callback
  @pragma('vm:entry-point')
  static Future<void> _onForegroundServiceStart(ServiceInstance service) async {
    // Register Dart plugins
    DartPluginRegistrant.ensureInitialized();

    // For Android, make sure this is a foreground service
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }

    // Periodic update timer
    Timer.periodic(const Duration(minutes: 5), (timer) async {
      try {
        // Get the current user ID from SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('current_user_id');

        if (userId != null) {
          // Update active devices
          await _updateActiveDevices(userId);

          // Update the notification
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: notificationTitle,
              content:
                  "Tracking energy consumption (Last update: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')})",
            );
          }

          // Save last update time
          await prefs.setString(
            'last_background_update',
            DateTime.now().toIso8601String(),
          );

          developer.log(
            "Foreground service updated devices at ${DateTime.now().toIso8601String()}",
          );
        }
      } catch (e) {
        developer.log("Error in foreground service update: $e");
      }
    });

    // Check for missed midnight reset on start
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('current_user_id');

      if (userId != null) {
        await _checkForMissedMidnightReset(userId);
      }
    } catch (e) {
      developer.log("Error checking for missed midnight reset: $e");
    }

    // Setup midnight reset timer in the background service
    _setupMidnightResetInBackground(service);
  }

  // Setup midnight reset timer in the background service
  static void _setupMidnightResetInBackground(ServiceInstance service) {
    // Calculate time until next midnight
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = tomorrow.difference(now);

    // Store the expected reset time in shared preferences
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('next_midnight_reset', tomorrow.toIso8601String());
    });

    // Set a one-time timer to trigger at midnight
    Timer(timeUntilMidnight, () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('current_user_id');

        if (userId != null) {
          // Reset daily usage
          await DatabaseHelper.instance.checkAndResetDailyUsage(userId);
          developer.log(
            "Background service performed midnight reset for user: $userId",
          );

          // Set up the next day's timer
          _setupMidnightResetInBackground(service);
        }
      } catch (e) {
        developer.log("Error in background midnight reset: $e");
      }
    });

    developer.log(
      "Background service midnight reset timer set for ${timeUntilMidnight.inHours} hours and ${timeUntilMidnight.inMinutes % 60} minutes from now",
    );
  }

  // iOS background task handler
  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    return true;
  }
}
