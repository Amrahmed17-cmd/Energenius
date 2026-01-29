import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DatabaseHelper._privateConstructor();

  // Fetch devices for a specific user
  Future<List<Map<String, dynamic>>> getDevices(String userId) async {
    try {
      QuerySnapshot snapshot =
          await _firestore
              .collection('devices')
              .where('is_user_added', isEqualTo: 1)
              .where('user_id', isEqualTo: userId)
              .get();

      return snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Include the document ID
        return data;
      }).toList();
    } catch (e) {
      developer.log("Error fetching devices for user $userId: $e");
      return [];
    }
  }

  // Alias for getDevices to maintain compatibility with code that used DatabaseAdapter
  Future<List<Map<String, dynamic>>> getUserDevices(String userId) async {
    return getDevices(userId);
  }

  // Fetch all categories
  Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      QuerySnapshot snapshot = await _firestore.collection('categories').get();
      return snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Include the document ID
        return data;
      }).toList();
    } catch (e) {
      developer.log("Error fetching categories: $e");
      return [];
    }
  }

  // Fetch preset devices (not user-added)
  Future<List<Map<String, dynamic>>> getPresetDevices() async {
    try {
      QuerySnapshot snapshot =
          await _firestore
              .collection('devices')
              .where('is_user_added', isEqualTo: 0)
              .get();

      List<Map<String, dynamic>> devices =
          snapshot.docs.map((doc) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id; // Include the document ID
            return data;
          }).toList();

      developer.log("Fetched ${devices.length} preset devices from Firebase");

      if (devices.isEmpty) {
        // If no devices found, log a warning
        developer.log(
          "Warning: No preset devices found in the Firebase collection",
        );
      }

      return devices;
    } catch (e) {
      developer.log("Error fetching preset devices: $e");
      return [];
    }
  }

  Future<void> addUserDevice({
    required String userId,
    required int categoryId,
    required String manufacturer,
    required String model,
    required double powerConsumption,
  }) async {
    try {
      // Get today's date in YYYY-MM-DD format
      String today = DateTime.now().toIso8601String().split('T')[0];

      // Check for an existing preset device with matching attributes
      QuerySnapshot presetSnapshot =
          await _firestore
              .collection('devices')
              .where('manufacturer', isEqualTo: manufacturer)
              .where('model', isEqualTo: model)
              .where('power_consumption', isEqualTo: powerConsumption)
              .where('is_user_added', isEqualTo: 0)
              .limit(1)
              .get();

      if (presetSnapshot.docs.isNotEmpty) {
        String existingDeviceId = presetSnapshot.docs.first.id;
        await _firestore.collection('devices').doc(existingDeviceId).update({
          'is_user_added': 1,
          'user_id': userId,
          'daily_uptime': 0.0,
          'total_uptime': 0.0,
          'daily_consumption': 0.0,
          'last_reset': today,
          'last_active': null,
        });
        await _updateConsumptionHistory(userId);
        developer.log(
          "Updated existing preset device ID $existingDeviceId for user $userId",
        );
      } else {
        await _firestore.collection('devices').add({
          'category_id': categoryId,
          'manufacturer': manufacturer,
          'model': model,
          'power_consumption': powerConsumption,
          'is_user_added': 1,
          'user_id': userId,
          'daily_uptime': 0.0,
          'total_uptime': 0.0,
          'daily_consumption': 0.0,
          'last_reset': today,
          'last_active': null,
        });
        await _updateConsumptionHistory(userId);
        developer.log("Added new user device: $model for user $userId");
      }
    } catch (e) {
      developer.log("Error adding device to Firestore: $e");
      rethrow;
    }
  }

  Future<void> updateUserDevice({
    required String deviceId,
    required String userId,
    required int categoryId,
    required String manufacturer,
    required String model,
    required double powerConsumption,
  }) async {
    try {
      // Get the existing device to preserve uptime data
      DocumentSnapshot deviceDoc =
          await _firestore.collection('devices').doc(deviceId).get();
      Map<String, dynamic> deviceData = {};

      if (deviceDoc.exists) {
        deviceData = deviceDoc.data() as Map<String, dynamic>;
      }

      await _firestore.collection('devices').doc(deviceId).update({
        'category_id': categoryId,
        'manufacturer': manufacturer,
        'model': model,
        'power_consumption': powerConsumption,
        'is_user_added': 1,
        'user_id': userId,
        // Preserve existing uptime data
        'daily_uptime': deviceData['daily_uptime'] ?? 0.0,
        'total_uptime': deviceData['total_uptime'] ?? 0.0,
        'daily_consumption': deviceData['daily_consumption'] ?? 0.0,
        'last_reset':
            deviceData['last_reset'] ??
            DateTime.now().toIso8601String().split('T')[0],
        'last_active': deviceData['last_active'],
      });
      await _updateConsumptionHistory(userId);
      developer.log("Updated device ID $deviceId in Firestore");
    } catch (e) {
      developer.log("Error updating device in Firestore: $e");
      rethrow;
    }
  }

  Future<void> deleteUserDevice(String deviceId, String userId) async {
    try {
      await _firestore.collection('devices').doc(deviceId).delete();
      await _updateConsumptionHistory(userId);
      developer.log("Deleted device ID $deviceId from Firestore");
    } catch (e) {
      developer.log("Error deleting device from Firestore: $e");
      rethrow;
    }
  }

  // Initialize consumption history for a new user
  Future<void> initializeUserConsumption(String userId) async {
    try {
      String today = DateTime.now().toIso8601String().split('T')[0];
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .doc(today)
          .set({
            'date': today,
            'total_consumption': 0.0,
            'timestamp': FieldValue.serverTimestamp(),
          });

      developer.log("Initialized consumption history for new user $userId");
    } catch (e) {
      developer.log("Error initializing consumption history: $e");
      rethrow;
    }
  }

  // Method to ensure historical data exists - only checks, doesn't generate fake data
  Future<void> ensureHistoricalData(String userId) async {
    try {
      // Check if we have historical data
      QuerySnapshot snapshot =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('consumption_history')
              .orderBy('date', descending: true)
              .limit(1)
              .get();

      if (snapshot.docs.isEmpty) {
        // No historical data, but we'll let it be empty rather than creating fake data
        developer.log("No historical consumption data found for user $userId");
      }
    } catch (e) {
      developer.log("Error checking historical data: $e");
    }
  }

  Future<void> _updateConsumptionHistory(String userId) async {
    try {
      // Get devices and their real-time consumption data
      List<Map<String, dynamic>> devices = await getDevices(userId);
      double totalDailyConsumption = 0.0;

      // Calculate total consumption based on tracked device uptime data
      for (var device in devices) {
        double dailyConsumption = device['daily_consumption'] ?? 0.0;
        totalDailyConsumption += dailyConsumption;
      }

      String today = DateTime.now().toIso8601String().split('T')[0];
      DocumentReference docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .doc(today);

      DocumentSnapshot doc = await docRef.get();

      if (!doc.exists) {
        // Create a new document for today if it doesn't exist
        await docRef.set({
          'date': today,
          'total_consumption': totalDailyConsumption,
          'timestamp': FieldValue.serverTimestamp(),
          'hourly_consumption': {},
          'devices_consumption': {},
        });
        developer.log(
          "Created new consumption document for $today: $totalDailyConsumption kWh",
        );
      } else {
        // Update the daily total consumption
        await docRef.update({
          'total_consumption': totalDailyConsumption,
          'last_updated': FieldValue.serverTimestamp(),
        });
        developer.log(
          "Updated consumption history for $today: $totalDailyConsumption kWh",
        );
      }

      // Record hourly consumption data with improved time-of-day based usage patterns
      await _recordHourlyConsumption(userId, totalDailyConsumption);

      // Refresh 7 days of history to ensure data consistency
      await _refreshRecentHistoryTotals(userId);

      developer.log(
        "Updated consumption history for $today: $totalDailyConsumption kWh for user $userId",
      );
    } catch (e) {
      developer.log("Error updating consumption history: $e");
    }
  }

  // New method to refresh recent history totals
  Future<void> _refreshRecentHistoryTotals(String userId) async {
    try {
      // Get the last 7 days of consumption history
      String today = DateTime.now().toIso8601String().split('T')[0];
      String sevenDaysAgo =
          DateTime.now()
              .subtract(const Duration(days: 7))
              .toIso8601String()
              .split('T')[0];

      QuerySnapshot snapshot =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('consumption_history')
              .where('date', isGreaterThanOrEqualTo: sevenDaysAgo)
              .where('date', isLessThanOrEqualTo: today)
              .get();

      // Update each document with recalculated totals based on hourly data
      for (var doc in snapshot.docs) {
        if (doc.id == today) {
          continue; // Skip today as it's already being updated
        }

        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        if (data.containsKey('hourly_consumption')) {
          Map<String, dynamic> hourlyData = Map<String, dynamic>.from(
            data['hourly_consumption'],
          );

          // Recalculate total consumption from hourly data
          double recalculatedTotal = 0.0;
          hourlyData.forEach((hour, value) {
            recalculatedTotal += (value as num).toDouble();
          });

          // Update the document with the recalculated total
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('consumption_history')
              .doc(doc.id)
              .update({
                'total_consumption': recalculatedTotal,
                'last_updated': FieldValue.serverTimestamp(),
              });

          developer.log(
            "Refreshed consumption total for ${doc.id}: $recalculatedTotal kWh",
          );
        }
      }
    } catch (e) {
      developer.log("Error refreshing history totals: $e");
    }
  }

  // Record hourly consumption data with improved time-of-day based usage patterns
  Future<void> _recordHourlyConsumption(
    String userId,
    double totalDailyConsumption,
  ) async {
    try {
      String today = DateTime.now().toIso8601String().split('T')[0];
      int currentHour = DateTime.now().hour;

      // Get the devices and calculate hourly consumption based on actual device usage
      List<Map<String, dynamic>> devices = await getDevices(userId);

      // If we have no devices, hourly consumption is zero
      if (devices.isEmpty) {
        return;
      }

      // Define usage patterns based on time of day
      // These coefficients represent typical home energy usage patterns
      Map<int, double> hourlyPatterns = {
        0: 0.4, // 12 AM - low usage (sleeping)
        1: 0.3, 2: 0.3, 3: 0.3, 4: 0.3,
        5: 0.5, // 5 AM - starting to wake up
        6: 0.8, // Morning routines begin
        7: 1.2, // Morning peak (breakfast, showers)
        8: 1.3,
        9: 1.0, // People leaving for work/school
        10: 0.8, 11: 0.7,
        12: 0.9, // Noon - lunch time
        13: 0.8, 14: 0.7, 15: 0.7, 16: 0.8,
        17: 1.2, // 5 PM - returning home
        18: 1.5, // Evening peak (dinner preparation)
        19: 1.8, // Peak evening usage
        20: 1.7, // High evening usage
        21: 1.4, // Starting to wind down
        22: 1.0, // Getting ready for bed
        23: 0.6, // Late night, reduced usage
      };

      // Get reference to the hourly consumption collection
      DocumentReference dailyDocRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .doc(today);

      // First get existing hourly data, if any
      DocumentSnapshot doc = await dailyDocRef.get();
      Map<String, dynamic> existingHourlyData = {};
      Map<String, dynamic> existingDevicesConsumption = {};

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('hourly_consumption')) {
          existingHourlyData = Map<String, dynamic>.from(
            data['hourly_consumption'],
          );
        }
        if (data.containsKey('devices_consumption')) {
          existingDevicesConsumption = Map<String, dynamic>.from(
            data['devices_consumption'],
          );
        }
      }

      // Calculate current hour's consumption
      double currentHourConsumption = 0.0;
      Map<String, double> deviceContributions = {};

      for (var device in devices) {
        double devicePower = device['power_consumption'] ?? 0.0;
        String deviceId = device['id'] ?? '';

        // Get the device's real-time status
        bool isActive = device['last_active'] != null;
        double dailyUptime = device['daily_uptime'] ?? 0.0;

        // Calculate device's contribution to current hour
        double deviceHourlyContribution = 0.0;

        // If the device is currently active, it's contributing power right now
        if (isActive) {
          // Apply the hourly pattern coefficient
          deviceHourlyContribution =
              devicePower * (hourlyPatterns[currentHour] ?? 1.0);
        }
        // Otherwise distribute its consumption based on recorded daily uptime and patterns
        else if (dailyUptime > 0) {
          // Spread the consumption across hours based on patterns
          // This assumes the device has been used according to typical usage patterns
          deviceHourlyContribution =
              (devicePower * dailyUptime / 24.0) *
              (hourlyPatterns[currentHour] ?? 1.0);
        }

        currentHourConsumption += deviceHourlyContribution;

        // Store the individual device contribution
        if (deviceId.isNotEmpty) {
          deviceContributions[deviceId] = deviceHourlyContribution;
        }
      }

      // Add current hour data to existing data
      existingHourlyData[currentHour.toString()] = currentHourConsumption;

      // Fill in missing hours with estimated data based on patterns and device usage
      // This ensures we have data for all hours, not just when the app is active
      for (int hour = 0; hour < 24; hour++) {
        // Skip the current hour as we've already calculated it
        if (hour == currentHour ||
            existingHourlyData.containsKey(hour.toString())) {
          continue;
        }

        // For past hours of today that have no data, estimate based on device usage patterns
        if (hour < currentHour) {
          double estimatedHourlyConsumption = 0.0;

          for (var device in devices) {
            double devicePower = device['power_consumption'] ?? 0.0;
            double dailyUptime = device['daily_uptime'] ?? 0.0;

            // Only estimate if the device has some recorded uptime today
            if (dailyUptime > 0) {
              // Calculate estimated hourly consumption based on patterns
              double hourlyFactor = hourlyPatterns[hour] ?? 1.0;
              double deviceEstimatedContribution =
                  (devicePower * dailyUptime / 24.0) * hourlyFactor;
              estimatedHourlyConsumption += deviceEstimatedContribution;
            }
          }

          // Add the estimated data
          existingHourlyData[hour.toString()] = estimatedHourlyConsumption;
        }
      }

      // Update device-specific consumption data
      deviceContributions.forEach((deviceId, consumption) {
        if (!existingDevicesConsumption.containsKey(deviceId)) {
          // If this is the first record for this device today, initialize its data
          var device = devices.firstWhere(
            (d) => d['id'] == deviceId,
            orElse: () => {},
          );
          existingDevicesConsumption[deviceId] = {
            'manufacturer': device['manufacturer'] ?? 'Unknown',
            'model': device['model'] ?? 'Device',
            'daily_consumption': device['daily_consumption'] ?? 0.0,
            'hourly_data': {currentHour.toString(): consumption},
          };
        } else {
          // Update existing device data
          Map<String, dynamic> deviceData = Map<String, dynamic>.from(
            existingDevicesConsumption[deviceId],
          );

          // Get the hourly data for this device
          Map<String, dynamic> hourlyData =
              deviceData.containsKey('hourly_data')
                  ? Map<String, dynamic>.from(deviceData['hourly_data'])
                  : {};

          // Update the current hour's consumption
          hourlyData[currentHour.toString()] = consumption;

          // Get the real-time daily consumption from the device record
          double deviceDailyConsumption =
              devices.firstWhere(
                (d) => d['id'] == deviceId,
                orElse: () => {'daily_consumption': 0.0},
              )['daily_consumption'] ??
              0.0;

          // Update the device data with new values
          deviceData['hourly_data'] = hourlyData;
          deviceData['daily_consumption'] = deviceDailyConsumption;

          existingDevicesConsumption[deviceId] = deviceData;
        }
      });

      // Calculate the total daily consumption based on recorded hourly data
      double calculatedDailyTotal = 0.0;
      existingHourlyData.forEach((hour, value) {
        calculatedDailyTotal += (value as num).toDouble();
      });

      // Update hourly consumption data in the daily document
      await dailyDocRef.set({
        'hourly_consumption': existingHourlyData,
        'devices_consumption': existingDevicesConsumption,
        'total_consumption': calculatedDailyTotal,
        'date': today,
        'last_updated': FieldValue.serverTimestamp(),
        'hours_recorded': existingHourlyData.keys.length,
      }, SetOptions(merge: true));

      developer.log(
        "Recorded hourly consumption for hour $currentHour: $currentHourConsumption kWh, total daily: $calculatedDailyTotal kWh, hours recorded: ${existingHourlyData.keys.length}",
      );
    } catch (e) {
      developer.log("Error recording hourly consumption: $e");
    }
  }

  // Get hourly consumption for a specific day with enhanced device breakdown
  Future<Map<String, dynamic>> getHourlyConsumptionEnhanced(
    String userId,
    String date,
  ) async {
    try {
      DocumentSnapshot doc =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('consumption_history')
              .doc(date)
              .get();

      Map<int, double> hourlyData = {};
      Map<String, dynamic> deviceData = {};
      double totalConsumption = 0.0;

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        totalConsumption = (data['total_consumption'] ?? 0.0).toDouble();

        if (data.containsKey('hourly_consumption')) {
          Map<String, dynamic> hourlyConsumption = data['hourly_consumption'];
          hourlyConsumption.forEach((hour, consumption) {
            hourlyData[int.parse(hour)] = consumption.toDouble();
          });
        }

        if (data.containsKey('devices_consumption')) {
          deviceData = Map<String, dynamic>.from(data['devices_consumption']);
        }
      }

      return {
        'hourly_data': hourlyData,
        'devices_data': deviceData,
        'total_consumption': totalConsumption,
        'date': date,
      };
    } catch (e) {
      developer.log("Error getting enhanced hourly consumption: $e");
      return {
        'hourly_data': <int, double>{},
        'devices_data': <String, dynamic>{},
        'total_consumption': 0.0,
        'date': date,
      };
    }
  }

  // Auto-send consumption data to the database periodically
  // This can be called from the app's background service
  Future<void> autoSendConsumptionData(String userId) async {
    try {
      await _updateConsumptionHistory(userId);
      developer.log("Auto-sent consumption data for user: $userId");
    } catch (e) {
      developer.log("Error auto-sending consumption data: $e");
    }
  }

  // Method to record device usage at regular intervals
  Future<void> recordDeviceUsage(String userId) async {
    try {
      // This method would be called by a background service or timer
      // to regularly update the consumption data
      await _updateConsumptionHistory(userId);
      developer.log("Recorded device usage for user: $userId");
    } catch (e) {
      developer.log("Error recording device usage: $e");
    }
  }

  // Get daily consumption data for a date range
  Future<List<Map<String, dynamic>>> getDailyConsumption(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      String startDateStr = startDate.toIso8601String().split('T')[0];
      String endDateStr = endDate.toIso8601String().split('T')[0];

      QuerySnapshot snapshot =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('consumption_history')
              .where('date', isGreaterThanOrEqualTo: startDateStr)
              .where('date', isLessThanOrEqualTo: endDateStr)
              .orderBy('date')
              .get();

      return snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      developer.log("Error getting daily consumption: $e");
      return [];
    }
  }

  // Get weekly consumption data
  Future<List<Map<String, dynamic>>> getWeeklyConsumption(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      // Get daily data first
      List<Map<String, dynamic>> dailyData = await getDailyConsumption(
        userId,
        startDate,
        endDate,
      );

      // Group by week
      Map<String, Map<String, dynamic>> weeklyAggregation = {};

      for (var dailyEntry in dailyData) {
        String dateStr = dailyEntry['date'];
        DateTime date = DateTime.parse(dateStr);

        // Calculate which week this belongs to
        DateTime firstDayOfYear = DateTime(date.year, 1, 1);
        int dayOfYear = date.difference(firstDayOfYear).inDays;
        int weekNum = (dayOfYear ~/ 7) + 1;
        String weekKey = "${date.year}-W$weekNum";

        if (!weeklyAggregation.containsKey(weekKey)) {
          // Initialize a new week
          DateTime weekStart = _getFirstDayOfWeek(date);
          DateTime weekEnd = _getLastDayOfWeek(date);

          weeklyAggregation[weekKey] = {
            'week': weekKey,
            'start_date': weekStart.toIso8601String().split('T')[0],
            'end_date': weekEnd.toIso8601String().split('T')[0],
            'total_consumption': 0.0,
            'days_count': 0,
          };
        }

        // Add consumption data
        double dailyConsumption =
            dailyEntry['total_consumption']?.toDouble() ?? 0.0;
        weeklyAggregation[weekKey]!['total_consumption'] += dailyConsumption;
        weeklyAggregation[weekKey]!['days_count'] += 1;
      }

      // Convert to list and sort
      List<Map<String, dynamic>> result = weeklyAggregation.values.toList();
      result.sort((a, b) => a['start_date'].compareTo(b['start_date']));

      developer.log(
        "Aggregated weekly data: ${result.length} weeks, "
        "Total: ${result.fold(0.0, (sumValue, item) => sumValue + (item['total_consumption'] ?? 0.0)).toStringAsFixed(2)} kWh",
      );

      return result;
    } catch (e) {
      developer.log("Error getting weekly consumption: $e");
      return [];
    }
  }

  // Get monthly consumption data
  Future<List<Map<String, dynamic>>> getMonthlyConsumption(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      // Get daily data first
      List<Map<String, dynamic>> dailyData = await getDailyConsumption(
        userId,
        startDate,
        endDate,
      );

      // Group by month
      Map<String, Map<String, dynamic>> monthlyAggregation = {};

      for (var dailyEntry in dailyData) {
        String dateStr = dailyEntry['date'];
        DateTime date = DateTime.parse(dateStr);

        // Format as year-month (e.g., "2023-05")
        String monthKey =
            "${date.year}-${date.month.toString().padLeft(2, '0')}";

        if (!monthlyAggregation.containsKey(monthKey)) {
          // Initialize a new month
          monthlyAggregation[monthKey] = {
            'month': monthKey,
            'month_name': _getMonthName(date.month),
            'year': date.year,
            'total_consumption': 0.0,
            'days_count': 0,
          };
        }

        // Add consumption data
        double dailyConsumption =
            dailyEntry['total_consumption']?.toDouble() ?? 0.0;
        monthlyAggregation[monthKey]!['total_consumption'] += dailyConsumption;
        monthlyAggregation[monthKey]!['days_count'] += 1;
      }

      // Convert to list and sort
      List<Map<String, dynamic>> result = monthlyAggregation.values.toList();
      result.sort((a, b) => a['month'].compareTo(b['month']));

      developer.log(
        "Aggregated monthly data: ${result.length} months, "
        "Total: ${result.fold(0.0, (sumValue, item) => sumValue + (item['total_consumption'] ?? 0.0)).toStringAsFixed(2)} kWh",
      );

      return result;
    } catch (e) {
      developer.log("Error getting monthly consumption: $e");
      return [];
    }
  }

  // Helper method to get the first day of a week containing the given date
  DateTime _getFirstDayOfWeek(DateTime date) {
    // DateTime uses 1 for Monday through 7 for Sunday
    int daysToSubtract = date.weekday - 1; // 0 for Monday, 6 for Sunday
    return DateTime(date.year, date.month, date.day - daysToSubtract);
  }

  // Helper method to get the last day of a week containing the given date
  DateTime _getLastDayOfWeek(DateTime date) {
    // DateTime uses 1 for Monday through 7 for Sunday
    int daysToAdd = 7 - date.weekday; // 6 for Monday, 0 for Sunday
    return DateTime(date.year, date.month, date.day + daysToAdd);
  }

  // Helper method to get month name from month number
  String _getMonthName(int month) {
    const List<String> monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    if (month >= 1 && month <= 12) {
      return monthNames[month - 1];
    }
    return '';
  }

  // Initialize for the current user (compatibility method)
  Future<void> initialize(String userId) async {
    try {
      // Ensure the user has consumption history
      await ensureHistoricalData(userId);

      // First check if categories exist
      List<Map<String, dynamic>> categories = await getCategories();
      if (categories.isEmpty) {
        // Create default categories
        await _createDefaultCategories();
      }

      // Check if preset devices exist
      List<Map<String, dynamic>> presetDevices = await getPresetDevices();
      if (presetDevices.isEmpty) {
        // Create sample preset devices
        await _createSamplePresetDevices();
      }

      // Initialize user's consumption data
      await initializeUserConsumption(userId);

      // Check and reset daily usage if needed
      await checkAndResetDailyUsage(userId);

      developer.log("Database initialization complete for user $userId");
    } catch (e) {
      developer.log("Error initializing database: $e");
    }
  }

  // Force migration stub (compatibility method)
  Future<bool> forceMigration(String userId) async {
    // No actual migration needed anymore
    return true;
  }

  // Get hourly consumption for a specific day (original method for backward compatibility)
  Future<Map<int, double>> getHourlyConsumption(
    String userId,
    String date,
  ) async {
    try {
      DocumentSnapshot doc =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('consumption_history')
              .doc(date)
              .get();

      Map<int, double> hourlyData = {};

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('hourly_consumption')) {
          Map<String, dynamic> hourlyConsumption = data['hourly_consumption'];
          hourlyConsumption.forEach((hour, consumption) {
            hourlyData[int.parse(hour)] = consumption.toDouble();
          });
        }
      }

      return hourlyData;
    } catch (e) {
      developer.log("Error getting hourly consumption: $e");
      return {};
    }
  }

  // Initialize database and add preset devices if they don't exist yet
  Future<void> initializeDatabase(String userId) async {
    try {
      // First check if categories exist
      List<Map<String, dynamic>> categories = await getCategories();
      if (categories.isEmpty) {
        // Create default categories
        await _createDefaultCategories();
      }

      // Check if preset devices exist
      List<Map<String, dynamic>> presetDevices = await getPresetDevices();
      if (presetDevices.isEmpty) {
        // Create sample preset devices
        await _createSamplePresetDevices();
      }

      // Initialize user's consumption data
      await initializeUserConsumption(userId);

      developer.log("Database initialization complete for user $userId");
    } catch (e) {
      developer.log("Error initializing database: $e");
      rethrow;
    }
  }

  Future<void> _createDefaultCategories() async {
    try {
      List<Map<String, String>> defaultCategories = [
        {'name': 'Air Conditioner'},
        {'name': 'TV'},
        {'name': 'Refrigerator'},
        {'name': 'Washing Machine'},
        {'name': 'Microwave'},
        {'name': 'Electric Oven'},
        {'name': 'Water Heater'},
        {'name': 'Lighting'},
        {'name': 'Computer'},
        {'name': 'Vacuum Cleaner'},
      ];

      for (var category in defaultCategories) {
        await _firestore.collection('categories').add(category);
      }

      developer.log("Created default categories");
    } catch (e) {
      developer.log("Error creating default categories: $e");
      rethrow;
    }
  }

  Future<void> _createSamplePresetDevices() async {
    try {
      // Get categories to use their IDs
      List<Map<String, dynamic>> categories = await getCategories();
      if (categories.isEmpty) {
        throw Exception("Categories not found, cannot create preset devices");
      }

      // Find category IDs
      String? acCategoryId = _findCategoryId(categories, 'Air Conditioner');
      String? tvCategoryId = _findCategoryId(categories, 'TV');
      String? refrigeratorCategoryId = _findCategoryId(
        categories,
        'Refrigerator',
      );
      String? washingMachineCategoryId = _findCategoryId(
        categories,
        'Washing Machine',
      );
      String? microwaveCategoryId = _findCategoryId(categories, 'Microwave');
      String? computerCategoryId = _findCategoryId(categories, 'Computer');

      // Sample preset devices with realistic data
      List<Map<String, dynamic>> presetDevices = [
        {
          'category_id': acCategoryId,
          'manufacturer': 'Samsung',
          'model': 'AR18',
          'power_consumption': 1.5,
          'is_user_added': 0,
        },
        {
          'category_id': acCategoryId,
          'manufacturer': 'LG',
          'model': 'Inverter V',
          'power_consumption': 1.8,
          'is_user_added': 0,
        },
        {
          'category_id': tvCategoryId,
          'manufacturer': 'Sony',
          'model': 'Bravia 55"',
          'power_consumption': 0.15,
          'is_user_added': 0,
        },
        {
          'category_id': tvCategoryId,
          'manufacturer': 'Samsung',
          'model': 'QLED 65"',
          'power_consumption': 0.17,
          'is_user_added': 0,
        },
        {
          'category_id': refrigeratorCategoryId,
          'manufacturer': 'LG',
          'model': 'Smart Refrigerator',
          'power_consumption': 0.2,
          'is_user_added': 0,
        },
        {
          'category_id': refrigeratorCategoryId,
          'manufacturer': 'Whirlpool',
          'model': 'Double Door',
          'power_consumption': 0.22,
          'is_user_added': 0,
        },
        {
          'category_id': washingMachineCategoryId,
          'manufacturer': 'Bosch',
          'model': 'Series 6',
          'power_consumption': 0.5,
          'is_user_added': 0,
        },
        {
          'category_id': microwaveCategoryId,
          'manufacturer': 'Panasonic',
          'model': 'NN-ST34',
          'power_consumption': 0.8,
          'is_user_added': 0,
        },
        {
          'category_id': computerCategoryId,
          'manufacturer': 'Dell',
          'model': 'XPS 15',
          'power_consumption': 0.08,
          'is_user_added': 0,
        },
        {
          'category_id': computerCategoryId,
          'manufacturer': 'Apple',
          'model': 'MacBook Pro',
          'power_consumption': 0.06,
          'is_user_added': 0,
        },
      ];

      // Add devices to Firebase
      for (var device in presetDevices) {
        if (device['category_id'] != null) {
          // Only add devices with valid category IDs
          await _firestore.collection('devices').add(device);
        }
      }

      developer.log("Created sample preset devices");
    } catch (e) {
      developer.log("Error creating sample preset devices: $e");
      rethrow;
    }
  }

  String? _findCategoryId(
    List<Map<String, dynamic>> categories,
    String categoryName,
  ) {
    final category = categories.firstWhere(
      (cat) => cat['name'] == categoryName,
      orElse: () => {'id': null},
    );
    return category['id']?.toString();
  }

  // Check and reset daily usage if needed
  Future<void> checkAndResetDailyUsage(String userId) async {
    try {
      // Get current date in YYYY-MM-DD format
      String today = DateTime.now().toIso8601String().split('T')[0];

      // Get all user devices
      List<Map<String, dynamic>> devices = await getUserDevices(userId);

      // Store last check time for midnight reset reliability
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'last_reset_check',
        DateTime.now().toIso8601String(),
      );

      for (var device in devices) {
        String deviceId = device['id'];
        String lastReset = device['last_reset'] ?? '';

        // If last reset is not today, reset daily counters
        if (lastReset.isNotEmpty && lastReset != today) {
          // Before resetting, capture the final consumption for the previous day
          if (lastReset.isNotEmpty && lastReset != today) {
            // Ensure the previous day's data is recorded in history
            await _ensureDailyConsumptionRecorded(
              userId,
              lastReset,
              deviceId,
              device,
            );
          }

          // Now reset the daily counters
          await _firestore.collection('devices').doc(deviceId).update({
            'daily_uptime': 0.0,
            'daily_consumption': 0.0,
            'last_reset': today,
          });
          developer.log(
            "Reset daily usage for device $deviceId from $lastReset to $today",
          );
        }
      }

      // After checking all devices, ensure today's document exists
      await _ensureDailyDocumentExists(userId, today);
    } catch (e) {
      developer.log("Error checking and resetting daily usage: $e");
    }
  }

  // Helper method to ensure the daily consumption is recorded for a device
  Future<void> _ensureDailyConsumptionRecorded(
    String userId,
    String date,
    String deviceId,
    Map<String, dynamic> device,
  ) async {
    try {
      DocumentReference docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .doc(date);

      DocumentSnapshot doc = await docRef.get();

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        Map<String, dynamic> devicesConsumption =
            data['devices_consumption'] as Map<String, dynamic>? ?? {};

        // Only update if the device isn't already recorded
        if (!devicesConsumption.containsKey(deviceId)) {
          devicesConsumption[deviceId] = {
            'manufacturer': device['manufacturer'] ?? 'Unknown',
            'model': device['model'] ?? 'Device',
            'daily_consumption': device['daily_consumption'] ?? 0.0,
            'daily_uptime': device['daily_uptime'] ?? 0.0,
          };

          await docRef.update({'devices_consumption': devicesConsumption});
          developer.log(
            "Recorded final consumption for device $deviceId on $date",
          );
        }
      } else {
        // Create the document if it doesn't exist
        Map<String, dynamic> devicesConsumption = {};
        devicesConsumption[deviceId] = {
          'manufacturer': device['manufacturer'] ?? 'Unknown',
          'model': device['model'] ?? 'Device',
          'daily_consumption': device['daily_consumption'] ?? 0.0,
          'daily_uptime': device['daily_uptime'] ?? 0.0,
        };

        await docRef.set({
          'date': date,
          'total_consumption': device['daily_consumption'] ?? 0.0,
          'timestamp': FieldValue.serverTimestamp(),
          'hourly_consumption': {},
          'devices_consumption': devicesConsumption,
        });
        developer.log(
          "Created missing document for $date with device $deviceId consumption",
        );
      }
    } catch (e) {
      developer.log("Error ensuring daily consumption recorded: $e");
    }
  }

  // Ensure today's document exists
  Future<void> _ensureDailyDocumentExists(String userId, String date) async {
    try {
      DocumentReference docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .doc(date);

      DocumentSnapshot doc = await docRef.get();

      if (!doc.exists) {
        await docRef.set({
          'date': date,
          'total_consumption': 0.0,
          'timestamp': FieldValue.serverTimestamp(),
          'hourly_consumption': {},
          'devices_consumption': {},
        });
        developer.log("Created document for today: $date");
      }
    } catch (e) {
      developer.log("Error ensuring daily document exists: $e");
    }
  }

  // Update device uptime and consumption
  Future<void> updateDeviceUptime({
    required String deviceId,
    required bool isActive,
    double? uptimeHours,
  }) async {
    try {
      DocumentSnapshot deviceDoc =
          await _firestore.collection('devices').doc(deviceId).get();

      if (!deviceDoc.exists) {
        throw Exception("Device $deviceId not found");
      }

      Map<String, dynamic> deviceData =
          deviceDoc.data() as Map<String, dynamic>;

      // Get current datetime
      DateTime now = DateTime.now();

      // Check if we need to reset daily usage
      await checkAndResetDailyUsage(deviceData['user_id']);

      double dailyUptime = deviceData['daily_uptime'] ?? 0.0;
      double totalUptime = deviceData['total_uptime'] ?? 0.0;
      double dailyConsumption = deviceData['daily_consumption'] ?? 0.0;
      double powerConsumption = deviceData['power_consumption'] ?? 0.0;
      DateTime? lastActive;

      if (deviceData['last_active'] != null) {
        lastActive = (deviceData['last_active'] as Timestamp).toDate();
      }

      // Store the last state of the device before updating
      final prefs = await SharedPreferences.getInstance();
      String deviceStateKey = 'device_state_$deviceId';
      if (isActive) {
        // Save the active state with timestamp for recovery if app closes
        await prefs.setString(deviceStateKey, now.toIso8601String());
      } else {
        // Clear the active state when device is turned off
        await prefs.remove(deviceStateKey);
      }

      // If an explicit uptime value is provided, use it
      if (uptimeHours != null) {
        // Add the provided uptime hours
        dailyUptime += uptimeHours;
        totalUptime += uptimeHours;
        dailyConsumption += (uptimeHours * powerConsumption);

        // Update the device with new values
        await _firestore.collection('devices').doc(deviceId).update({
          'daily_uptime': dailyUptime,
          'total_uptime': totalUptime,
          'daily_consumption': dailyConsumption,
          'last_active': isActive ? FieldValue.serverTimestamp() : null,
        });
      }
      // Otherwise calculate uptime based on last_active timestamp with improved precision
      else if (isActive && lastActive != null) {
        // Calculate time difference since last active timestamp in hours with more precision
        // This will track even seconds of usage
        double secondsSinceLastActive =
            now.difference(lastActive).inMilliseconds / 1000.0;
        double hoursSinceLastActive = secondsSinceLastActive / 3600.0;

        // Add to uptime counters
        dailyUptime += hoursSinceLastActive;
        totalUptime += hoursSinceLastActive;
        dailyConsumption += (hoursSinceLastActive * powerConsumption);

        // Update the device with new values with precision up to 6 decimal places
        await _firestore.collection('devices').doc(deviceId).update({
          'daily_uptime': double.parse(dailyUptime.toStringAsFixed(6)),
          'total_uptime': double.parse(totalUptime.toStringAsFixed(6)),
          'daily_consumption': double.parse(
            dailyConsumption.toStringAsFixed(6),
          ),
          'last_active': isActive ? FieldValue.serverTimestamp() : null,
        });

        developer.log(
          "Updated device uptime with high precision. Added ${hoursSinceLastActive.toStringAsFixed(6)} hours (${secondsSinceLastActive.toStringAsFixed(1)} seconds)",
        );
      }
      // If just turning on, set the last_active timestamp
      else if (isActive) {
        // Check if we need to recover from an app closure while device was active
        String? lastActiveStr = prefs.getString(deviceStateKey);
        if (lastActiveStr != null && lastActive == null) {
          // Device was active when app closed but database shows inactive
          DateTime lastActiveTime = DateTime.tryParse(lastActiveStr) ?? now;

          // Calculate time difference since last active timestamp
          double secondsSinceLastActive =
              now.difference(lastActiveTime).inMilliseconds / 1000.0;
          double hoursSinceLastActive = secondsSinceLastActive / 3600.0;

          // Only count time if it's reasonable (less than 24 hours)
          if (hoursSinceLastActive > 0 && hoursSinceLastActive < 24.0) {
            // Add to uptime counters
            dailyUptime += hoursSinceLastActive;
            totalUptime += hoursSinceLastActive;
            dailyConsumption += (hoursSinceLastActive * powerConsumption);

            developer.log(
              "Recovered ${hoursSinceLastActive.toStringAsFixed(2)} hours of missed uptime for device $deviceId",
            );
          }
        }

        await _firestore.collection('devices').doc(deviceId).update({
          'daily_uptime': dailyUptime,
          'total_uptime': totalUptime,
          'daily_consumption': dailyConsumption,
          'last_active': FieldValue.serverTimestamp(),
        });
      }
      // If turning off and was previously active
      else if (!isActive && lastActive != null) {
        // Calculate time difference since last active timestamp in hours with more precision
        double secondsSinceLastActive =
            now.difference(lastActive).inMilliseconds / 1000.0;
        double hoursSinceLastActive = secondsSinceLastActive / 3600.0;

        // Add to uptime counters
        dailyUptime += hoursSinceLastActive;
        totalUptime += hoursSinceLastActive;
        dailyConsumption += (hoursSinceLastActive * powerConsumption);

        // Update the device with new values and clear last_active
        await _firestore.collection('devices').doc(deviceId).update({
          'daily_uptime': double.parse(dailyUptime.toStringAsFixed(6)),
          'total_uptime': double.parse(totalUptime.toStringAsFixed(6)),
          'daily_consumption': double.parse(
            dailyConsumption.toStringAsFixed(6),
          ),
          'last_active': null,
        });

        developer.log(
          "Device turned off. Added ${hoursSinceLastActive.toStringAsFixed(6)} hours (${secondsSinceLastActive.toStringAsFixed(1)} seconds) to uptime",
        );
      }

      developer.log("Updated uptime for device $deviceId");
    } catch (e) {
      developer.log("Error updating device uptime: $e");
      rethrow;
    }
  }

  /// Call this on app launch or resume to fill in any missing days/hours and ensure data integrity
  Future<void> syncAndFillMissingData(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? lastSyncStr = prefs.getString('lastSync');
      DateTime now = DateTime.now();

      // If no last sync, use a reasonable fallback (24 hours ago)
      DateTime lastSync =
          lastSyncStr != null
              ? DateTime.tryParse(lastSyncStr) ??
                  now.subtract(const Duration(hours: 24))
              : now.subtract(const Duration(hours: 24));

      developer.log(
        "Syncing data from ${lastSync.toIso8601String()} to ${now.toIso8601String()}",
      );

      // Get all user devices to estimate their usage during offline period
      List<Map<String, dynamic>> devices = await getUserDevices(userId);

      // Check for devices that were active at last sync
      List<Map<String, dynamic>> activeDevices =
          devices.where((device) {
            if (device['last_active'] == null) return false;

            // Convert Timestamp to DateTime
            DateTime lastActive;
            if (device['last_active'] is Timestamp) {
              lastActive = (device['last_active'] as Timestamp).toDate();
            } else {
              return false;
            }

            // Device was active at or near last sync time
            return lastActive.isAfter(
              lastSync.subtract(const Duration(minutes: 10)),
            );
          }).toList();

      // Fill in missing days
      DateTime day = DateTime(lastSync.year, lastSync.month, lastSync.day);
      DateTime today = DateTime(now.year, now.month, now.day);

      while (day.isBefore(today)) {
        String dayStr = day.toIso8601String().split('T')[0];
        await _reconstructDayData(
          userId,
          dayStr,
          devices,
          activeDevices,
          lastSync,
          now,
        );
        day = day.add(const Duration(days: 1));
      }

      // Fill in missing hours for today
      await _reconstructTodayHours(
        userId,
        today,
        now.hour,
        devices,
        activeDevices,
      );

      // Update last sync time
      prefs.setString('lastSync', now.toIso8601String());

      // Check and reset daily usage if needed
      await checkAndResetDailyUsage(userId);

      developer.log("Completed data sync and reconstruction");
    } catch (e) {
      developer.log("Error in syncAndFillMissingData: $e");
    }
  }

  /// Reconstruct a full day's data based on known device patterns
  Future<void> _reconstructDayData(
    String userId,
    String dayStr,
    List<Map<String, dynamic>> allDevices,
    List<Map<String, dynamic>> activeDevices,
    DateTime lastSync,
    DateTime now,
  ) async {
    try {
      // Check if this day already has data
      DocumentReference docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .doc(dayStr);
      DocumentSnapshot doc = await docRef.get();

      if (doc.exists) {
        // Document exists, check if it has hourly data
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('hourly_consumption') &&
            (data['hourly_consumption'] as Map<String, dynamic>).isNotEmpty) {
          // Already has hourly data, no need to reconstruct
          return;
        }
      }

      // Need to create or update the document with reconstructed data
      Map<String, dynamic> hourlyConsumption = {};
      Map<String, dynamic> devicesConsumption = {};
      double totalDailyConsumption = 0.0;

      // Define usage patterns based on time of day
      Map<int, double> hourlyPatterns = {
        0: 0.4, // 12 AM - low usage (sleeping)
        1: 0.3, 2: 0.3, 3: 0.3, 4: 0.3,
        5: 0.5, // 5 AM - starting to wake up
        6: 0.8, // Morning routines begin
        7: 1.2, // Morning peak (breakfast, showers)
        8: 1.3,
        9: 1.0, // People leaving for work/school
        10: 0.8, 11: 0.7,
        12: 0.9, // Noon - lunch time
        13: 0.8, 14: 0.7, 15: 0.7, 16: 0.8,
        17: 1.2, // 5 PM - returning home
        18: 1.5, // Evening peak (dinner preparation)
        19: 1.8, // Peak evening usage
        20: 1.7, // High evening usage
        21: 1.4, // Starting to wind down
        22: 1.0, // Getting ready for bed
        23: 0.6, // Late night, reduced usage
      };

      // For each device, estimate its usage throughout the day
      for (var device in allDevices) {
        String deviceId = device['id'];
        double powerConsumption = device['power_consumption'] ?? 0.0;
        bool wasActive = activeDevices.any((d) => d['id'] == deviceId);

        // Estimate device's daily consumption based on typical patterns
        // If it was active at last sync, assume higher usage
        double estimatedDailyUptime = wasActive ? 8.0 : 2.0; // hours
        double deviceDailyConsumption = estimatedDailyUptime * powerConsumption;

        // Add to total consumption
        totalDailyConsumption += deviceDailyConsumption;

        // Record device consumption
        devicesConsumption[deviceId] = {
          'manufacturer': device['manufacturer'] ?? 'Unknown',
          'model': device['model'] ?? 'Device',
          'daily_consumption': deviceDailyConsumption,
          'daily_uptime': estimatedDailyUptime,
        };

        // Distribute consumption across hours based on patterns
        for (int hour = 0; hour < 24; hour++) {
          double hourlyFactor = hourlyPatterns[hour] ?? 1.0;
          double deviceHourlyConsumption =
              (deviceDailyConsumption / 24.0) * hourlyFactor;

          // Add to hourly total
          hourlyConsumption[hour.toString()] =
              (hourlyConsumption[hour.toString()] ?? 0.0) +
              deviceHourlyConsumption;
        }
      }

      // Create or update the document
      if (doc.exists) {
        await docRef.update({
          'total_consumption': totalDailyConsumption,
          'hourly_consumption': hourlyConsumption,
          'devices_consumption': devicesConsumption,
          'is_reconstructed': true, // Flag to indicate this is estimated data
          'last_updated': FieldValue.serverTimestamp(),
        });
      } else {
        await docRef.set({
          'date': dayStr,
          'total_consumption': totalDailyConsumption,
          'hourly_consumption': hourlyConsumption,
          'devices_consumption': devicesConsumption,
          'is_reconstructed': true, // Flag to indicate this is estimated data
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      developer.log(
        "Reconstructed data for $dayStr with ${allDevices.length} devices, total: $totalDailyConsumption kWh",
      );
    } catch (e) {
      developer.log("Error reconstructing day data for $dayStr: $e");
    }
  }

  /// Reconstruct hourly data for today up to the current hour
  Future<void> _reconstructTodayHours(
    String userId,
    DateTime today,
    int currentHour,
    List<Map<String, dynamic>> allDevices,
    List<Map<String, dynamic>> activeDevices,
  ) async {
    try {
      String todayStr = today.toIso8601String().split('T')[0];

      // Get today's document
      DocumentReference docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .doc(todayStr);
      DocumentSnapshot doc = await docRef.get();

      // Initialize data structures
      Map<String, dynamic> hourlyConsumption = {};
      Map<String, dynamic> devicesConsumption = {};
      double totalConsumption = 0.0;

      // If document exists, get existing data
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('hourly_consumption')) {
          hourlyConsumption = Map<String, dynamic>.from(
            data['hourly_consumption'],
          );
        }
        if (data.containsKey('devices_consumption')) {
          devicesConsumption = Map<String, dynamic>.from(
            data['devices_consumption'],
          );
        }
        totalConsumption = (data['total_consumption'] ?? 0.0).toDouble();
      }

      // Define usage patterns
      Map<int, double> hourlyPatterns = {
        0: 0.4,
        1: 0.3,
        2: 0.3,
        3: 0.3,
        4: 0.3,
        5: 0.5,
        6: 0.8,
        7: 1.2,
        8: 1.3,
        9: 1.0,
        10: 0.8,
        11: 0.7,
        12: 0.9,
        13: 0.8,
        14: 0.7,
        15: 0.7,
        16: 0.8,
        17: 1.2,
        18: 1.5,
        19: 1.8,
        20: 1.7,
        21: 1.4,
        22: 1.0,
        23: 0.6,
      };

      // For each missing hour, estimate consumption
      for (int hour = 0; hour < currentHour; hour++) {
        // Skip hours that already have data
        if (hourlyConsumption.containsKey(hour.toString())) {
          continue;
        }

        double hourlyTotal = 0.0;

        // For each device, estimate its contribution to this hour
        for (var device in allDevices) {
          String deviceId = device['id'];
          double powerConsumption = device['power_consumption'] ?? 0.0;
          bool wasActive = activeDevices.any((d) => d['id'] == deviceId);

          // Estimate hourly consumption based on patterns and active status
          double hourlyFactor = hourlyPatterns[hour] ?? 1.0;
          double baseHourlyConsumption =
              powerConsumption / 24.0; // Base hourly rate
          double deviceHourlyConsumption =
              baseHourlyConsumption * hourlyFactor * (wasActive ? 3.0 : 1.0);

          hourlyTotal += deviceHourlyConsumption;

          // Update device's consumption for today
          if (devicesConsumption.containsKey(deviceId)) {
            double existingConsumption =
                (devicesConsumption[deviceId]['daily_consumption'] ?? 0.0)
                    .toDouble();
            double existingUptime =
                (devicesConsumption[deviceId]['daily_uptime'] ?? 0.0)
                    .toDouble();

            devicesConsumption[deviceId]['daily_consumption'] =
                existingConsumption + deviceHourlyConsumption;
            devicesConsumption[deviceId]['daily_uptime'] =
                existingUptime + (deviceHourlyConsumption / powerConsumption);
          } else {
            devicesConsumption[deviceId] = {
              'manufacturer': device['manufacturer'] ?? 'Unknown',
              'model': device['model'] ?? 'Device',
              'daily_consumption': deviceHourlyConsumption,
              'daily_uptime': deviceHourlyConsumption / powerConsumption,
            };
          }
        }

        // Add to hourly data
        hourlyConsumption[hour.toString()] = hourlyTotal;
        totalConsumption += hourlyTotal;
      }

      // Update the document
      if (doc.exists) {
        await docRef.update({
          'total_consumption': totalConsumption,
          'hourly_consumption': hourlyConsumption,
          'devices_consumption': devicesConsumption,
          'last_updated': FieldValue.serverTimestamp(),
        });
      } else {
        await docRef.set({
          'date': todayStr,
          'total_consumption': totalConsumption,
          'hourly_consumption': hourlyConsumption,
          'devices_consumption': devicesConsumption,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      developer.log(
        "Reconstructed today's hourly data up to hour $currentHour, total: $totalConsumption kWh",
      );
    } catch (e) {
      developer.log("Error reconstructing today's hourly data: $e");
    }
  }
}
