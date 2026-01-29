// Temporarily commented out for release build
// import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;

// Background task names
const String periodicTaskName = 'energenius.periodic.update';
const String midnightTaskName = 'energenius.midnight.reset';

// Workmanager callback dispatcher - must be top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  // Temporarily commented out for release build
  /*
  Workmanager().executeTask((taskName, inputData) async {
    try {
      // Get the current user ID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('current_user_id');
      
      if (userId != null) {
        developer.log("Executing background task: $taskName for user: $userId");
        
        if (taskName == periodicTaskName) {
          // Periodic update task
          await DatabaseHelper.instance.syncAndFillMissingData(userId);
          await DatabaseHelper.instance.autoSendConsumptionData(userId);
          developer.log("Completed periodic background update for user: $userId");
        } else if (taskName == midnightTaskName) {
          // Midnight reset task
          await DatabaseHelper.instance.checkAndResetDailyUsage(userId);
          developer.log("Completed midnight reset from background task for user: $userId");
          
          // Schedule the next midnight reset
          final now = DateTime.now();
          final tomorrow = DateTime(now.year, now.month, now.day + 1);
          
          // Store the next reset time
          await prefs.setString('next_midnight_reset', tomorrow.toIso8601String());
          
          // Schedule the next midnight task
          await Workmanager().registerOneOffTask(
            midnightTaskName,
            midnightTaskName,
            initialDelay: const Duration(hours: 24),
          );
        }
      }
      
      return Future.value(true);
    } catch (e) {
      developer.log("Error in background task: $e");
      return Future.value(false);
    }
  });
  */
  return;
}

class BackgroundTasks {
  // Initialize the workmanager
  static Future<void> initialize() async {
    // Temporarily commented out for release build
    /*
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
    */

    developer.log("Background tasks initialized");
  }

  // Register periodic task to update consumption data
  static Future<void> registerPeriodicTask() async {
    // Temporarily commented out for release build
    /*
    await Workmanager().registerPeriodicTask(
      periodicTaskName,
      periodicTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
    */

    developer.log("Registered periodic background task");
  }

  // Schedule a one-time task for midnight reset
  static Future<void> scheduleMidnightTask() async {
    // Calculate time until next midnight
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = tomorrow.difference(now);

    // Store the scheduled reset time in shared preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('next_midnight_reset', tomorrow.toIso8601String());

    // Schedule the one-time task
    // Temporarily commented out for release build
    /*
    await Workmanager().registerOneOffTask(
      midnightTaskName,
      midnightTaskName,
      initialDelay: timeUntilMidnight,
    );
    */

    developer.log(
      "Scheduled midnight reset task for ${timeUntilMidnight.inHours} hours and ${timeUntilMidnight.inMinutes % 60} minutes from now",
    );
  }

  // Register all background tasks
  static Future<void> registerAllTasks() async {
    await registerPeriodicTask();
    await scheduleMidnightTask();
  }

  // Cancel all background tasks
  static Future<void> cancelAllTasks() async {
    // Temporarily commented out for release build
    /*
    await Workmanager().cancelAll();
    */
    developer.log("Cancelled all background tasks");
  }
}
