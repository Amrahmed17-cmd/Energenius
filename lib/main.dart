import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'firebase_options.dart'; // Ensure this file exists
import 'theme_provider.dart';
import 'screens/main_screen.dart';
import 'screens/login_screen.dart';
import 'dart:developer' as developer;
import 'localization/app_localizations.dart';
import 'localization/language_provider.dart';
import 'database/database_helper.dart';
import 'services/background_service.dart';
import 'services/update_service.dart';
import 'widgets/update_dialog.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform, // Use generated options
    );
    developer.log("Firebase initialized successfully");

    // Pre-load the saved language preference
    await AppLocalizations.getLocale();

    // Check for app updates if online
    await _checkForUpdates();

    // Initialize database for current user if logged in
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      // Store user ID for background tasks
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_user_id', currentUser.uid);

      // Initialize the database and sync data
      await DatabaseHelper.instance.initialize(currentUser.uid);
      await DatabaseHelper.instance.syncAndFillMissingData(currentUser.uid);

      // Start the timer to periodically send consumption data
      _startConsumptionDataTimer(currentUser.uid);
    }

    // Initialize background service (safely handles all platforms)
    try {
      await BackgroundService().initializeService();

      // Set up auth state listener to handle database operations on auth changes
      _setupAuthListener();
    } catch (e) {
      developer.log("Error initializing background service: $e");
    }
  } catch (e) {
    developer.log("Error during initialization: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

// Check for updates and show update dialog if needed
Future<void> _checkForUpdates() async {
  try {
    // First check if device is online
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        developer.log("Device is offline, skipping update check");
        return;
      }
    } on SocketException catch (_) {
      developer.log("Device is offline, skipping update check");
      return;
    }

    // Check for updates
    final updateService = UpdateService();
    final updateInfo = await updateService.checkForUpdate();

    if (updateInfo != null) {
      // Update available, check if user has previously skipped this version
      final latestVersion = updateInfo['latestVersion'];
      final forceUpdate = updateInfo['forceUpdate'] ?? false;

      if (!forceUpdate) {
        final shouldSkip = await updateService.shouldSkipUpdateCheck(
          latestVersion,
        );
        if (shouldSkip) {
          developer.log(
            "User previously skipped update to version $latestVersion",
          );
          return;
        }
      }

      // Store update info to show dialog after app starts
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_pending_update', true);
      await prefs.setString(
        'update_info',
        '{"latestVersion":"${updateInfo['latestVersion']}",'
            '"currentVersion":"${updateInfo['currentVersion']}",'
            '"updateNotes":"${updateInfo['updateNotes']}",'
            '"forceUpdate":${updateInfo['forceUpdate']},'
            '"downloadUrl":"${updateInfo['downloadUrl']}"}',
      );

      developer.log(
        "Update information stored, dialog will show after app start",
      );
    } else {
      developer.log("No update available or failed to check for updates");
    }
  } catch (e) {
    developer.log("Error during update check: $e");
  }
}

// Timer to periodically send consumption data to the database
Timer? _consumptionDataTimer;
// Timer to reset device uptime at midnight
Timer? _midnightResetTimer;

void _startConsumptionDataTimer(String userId) {
  // Cancel any existing timer
  _consumptionDataTimer?.cancel();

  // Create a new timer that runs every 5 minutes (reduced from 10 minutes)
  _consumptionDataTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
    _sendConsumptionData(userId);
  });

  // Also send data immediately on app start
  _sendConsumptionData(userId);

  developer.log("Started consumption data timer for user: $userId");

  // Start the midnight reset timer
  _setupMidnightResetTimer(userId);
}

void _setupMidnightResetTimer(String userId) {
  // Cancel any existing timer
  _midnightResetTimer?.cancel();

  // Calculate time until next midnight
  final now = DateTime.now();
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final timeUntilMidnight = tomorrow.difference(now);

  // Store the scheduled reset time in shared preferences for recovery
  SharedPreferences.getInstance().then((prefs) {
    prefs.setString('next_midnight_reset', tomorrow.toIso8601String());
  });

  // Set a one-time timer to trigger at midnight
  _midnightResetTimer = Timer(timeUntilMidnight, () {
    // Reset daily usage
    DatabaseHelper.instance.checkAndResetDailyUsage(userId).then((_) {
      developer.log("Midnight reset performed for user: $userId");
      // Set up the next day's timer
      _setupMidnightResetTimer(userId);
    });
  });

  developer.log(
    "Midnight reset timer set for ${timeUntilMidnight.inHours} hours and ${timeUntilMidnight.inMinutes % 60} minutes from now",
  );
}

Future<void> _sendConsumptionData(String userId) async {
  try {
    // First check and reset daily usage if needed
    await DatabaseHelper.instance.checkAndResetDailyUsage(userId);

    // Get all user devices to check for active devices
    List<Map<String, dynamic>> devices = await DatabaseHelper.instance
        .getUserDevices(userId);

    // For each active device, update its uptime
    for (var device in devices) {
      String deviceId = device['id'];
      bool isActive = device['last_active'] != null;

      if (isActive) {
        // Update uptime for active devices
        await DatabaseHelper.instance.updateDeviceUptime(
          deviceId: deviceId,
          isActive: true,
        );
        developer.log("Updated uptime for active device: ${device['model']}");
      }
    }

    // Then send consumption data
    await DatabaseHelper.instance.autoSendConsumptionData(userId);

    // Store the last update time
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(
        'last_consumption_update',
        DateTime.now().toIso8601String(),
      );
    });
  } catch (e) {
    developer.log("Error in periodic consumption data send: $e");
  }
}

void _setupAuthListener() {
  FirebaseAuth.instance.authStateChanges().listen((User? user) {
    if (user != null) {
      // User signed in
      DatabaseHelper.instance.initialize(user.uid);
      _startConsumptionDataTimer(user.uid);

      // Store the current app state and user ID for background tasks
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('app_last_active', DateTime.now().toIso8601String());
        prefs.setString('current_user_id', user.uid);
      });

      // Register background tasks for the user
      // BackgroundTasks.registerAllTasks();

      developer.log("Auth state changed: User signed in - ${user.uid}");
    } else {
      // User signed out
      _consumptionDataTimer?.cancel();
      _consumptionDataTimer = null;
      _midnightResetTimer?.cancel();
      _midnightResetTimer = null;

      // Clear user ID when signed out
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove('current_user_id');
      });

      // Cancel background tasks
      // BackgroundTasks.cancelAllTasks();

      developer.log("Auth state changed: User signed out");
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Check for pending updates after app initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingUpdates();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Check if there's a pending update to show
  Future<void> _checkPendingUpdates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasPendingUpdate = prefs.getBool('has_pending_update') ?? false;

      if (hasPendingUpdate) {
        final updateInfoString = prefs.getString('update_info');
        if (updateInfoString != null) {
          // Parse the update info
          final updateInfo = {};
          final parts = updateInfoString.split(',');
          for (final part in parts) {
            if (part.contains(':')) {
              final keyValue = part.split(':');
              if (keyValue.length == 2) {
                String key = keyValue[0].replaceAll(RegExp(r'[{"}]'), '');
                String value = keyValue[1].replaceAll(RegExp(r'["}]'), '');

                // Handle boolean values
                if (value == 'true') {
                  updateInfo[key] = true;
                } else if (value == 'false') {
                  updateInfo[key] = false;
                } else {
                  updateInfo[key] = value;
                }
              }
            }
          }

          // Show update dialog
          final forceUpdate = updateInfo['forceUpdate'] == true;

          // Clear pending update flag unless it's a force update
          if (!forceUpdate) {
            await prefs.setBool('has_pending_update', false);
          }

          // Show dialog
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: !forceUpdate,
              builder:
                  (context) => UpdateDialog(
                    updateInfo: updateInfo as Map<String, dynamic>,
                    forceUpdate: forceUpdate,
                  ),
            );
          }
        }
      }
    } catch (e) {
      developer.log("Error checking pending updates: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App resumed from background, refresh data
      _refreshAppDataOnResume();
    } else if (state == AppLifecycleState.paused) {
      // App going to background, save state
      _saveAppStateOnPause();
    }
  }

  // Save app state when going to background
  Future<void> _saveAppStateOnPause() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'app_last_active',
        DateTime.now().toIso8601String(),
      );
      await prefs.setString('app_state', 'paused');

      developer.log("App paused: saved state for user ${user.uid}");
    }
  }

  // Refresh data when the app is resumed from background
  Future<void> _refreshAppDataOnResume() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Check when the app was last active
      final prefs = await SharedPreferences.getInstance();
      String? lastActiveStr = prefs.getString('app_last_active');
      await prefs.setString('app_state', 'resumed');

      if (lastActiveStr != null) {
        DateTime lastActive =
            DateTime.tryParse(lastActiveStr) ?? DateTime.now();
        DateTime now = DateTime.now();

        // If it's been more than 2 minutes since the app was last active
        if (now.difference(lastActive).inMinutes > 2) {
          // NEW: Sync and fill missing data before anything else
          await DatabaseHelper.instance.syncAndFillMissingData(user.uid);

          // Check if we missed a midnight reset
          String? nextResetStr = prefs.getString('next_midnight_reset');
          if (nextResetStr != null) {
            DateTime nextReset =
                DateTime.tryParse(nextResetStr) ?? DateTime.now();

            // If we're past the scheduled reset time
            if (now.isAfter(nextReset)) {
              // Force a reset
              await DatabaseHelper.instance.checkAndResetDailyUsage(user.uid);

              // Set up a new midnight reset timer
              _setupMidnightResetTimer(user.uid);

              developer.log(
                "App resume: performed missed midnight reset for user ${user.uid}",
              );
            }
          }
        }
      }

      // Force a consumption data update
      await _sendConsumptionData(user.uid);

      // Update the last active timestamp
      await prefs.setString(
        'app_last_active',
        DateTime.now().toIso8601String(),
      );

      developer.log("App resumed: refreshed data for user ${user.uid}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => LanguageProvider()),
      ],
      child: Consumer2<ThemeProvider, LanguageProvider>(
        builder: (context, themeProvider, languageProvider, child) {
          return MaterialApp(
            title: 'Energenius',
            theme: themeProvider.themeData,
            themeMode:
                themeProvider.isDarkTheme ? ThemeMode.dark : ThemeMode.light,
            darkTheme: ThemeProvider.darkTheme,
            themeAnimationDuration: const Duration(milliseconds: 400),
            themeAnimationCurve: Curves.easeInOut,
            locale: languageProvider.locale,
            supportedLocales: const [
              Locale('en', ''), // English
              Locale('ar', ''), // Arabic
              Locale('fr', ''), // French
            ],
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            initialRoute: '/login',
            routes: {
              '/login': (context) => LoginScreen(),
              '/main': (context) => const MainScreen(),
            },
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
