import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import 'dart:async';

class ImprovedDatabaseHelper {
  static final ImprovedDatabaseHelper instance =
      ImprovedDatabaseHelper._privateConstructor();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache for common data to reduce database reads
  final Map<String, List<Map<String, dynamic>>> _categoriesCache = {};
  final Map<String, List<Map<String, dynamic>>> _deviceCache = {};
  final Map<String, Map<String, dynamic>> _userCache = {};

  // Stream controllers for real-time updates
  final StreamController<List<Map<String, dynamic>>>
  _userDevicesStreamController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<Map<String, dynamic>> _consumptionStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<List<Map<String, dynamic>>> get userDevicesStream =>
      _userDevicesStreamController.stream;
  Stream<Map<String, dynamic>> get consumptionStream =>
      _consumptionStreamController.stream;

  ImprovedDatabaseHelper._privateConstructor();

  // Initialize the database connections and caches
  Future<void> initialize() async {
    try {
      // Pre-fetch categories as they rarely change
      await _fetchAndCacheCategories();
    } catch (e) {
      developer.log("Error initializing database: $e");
    }
  }

  // SECTION: USER MANAGEMENT

  // Create or update user profile
  Future<void> updateUserProfile(
    String userId,
    Map<String, dynamic> userData,
  ) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .set(userData, SetOptions(merge: true));

      // Update user cache
      _userCache[userId] = userData;

      developer.log("User profile updated: $userId");
    } catch (e) {
      developer.log("Error updating user profile: $e");
      rethrow;
    }
  }

  // Get user profile with caching
  Future<Map<String, dynamic>> getUserProfile(String userId) async {
    try {
      // Try cache first
      if (_userCache.containsKey(userId)) {
        return _userCache[userId]!;
      }

      // Fetch from database
      DocumentSnapshot doc =
          await _firestore.collection('users').doc(userId).get();

      if (doc.exists) {
        Map<String, dynamic> userData = doc.data() as Map<String, dynamic>;
        _userCache[userId] = userData; // Cache the result
        return userData;
      }

      return {};
    } catch (e) {
      developer.log("Error fetching user profile: $e");
      return {};
    }
  }

  // SECTION: CATEGORIES MANAGEMENT

  // Fetch and cache all categories
  Future<void> _fetchAndCacheCategories() async {
    try {
      QuerySnapshot snapshot = await _firestore.collection('categories').get();

      List<Map<String, dynamic>> categories =
          snapshot.docs.map((doc) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id;
            return data;
          }).toList();

      _categoriesCache['all'] = categories;
    } catch (e) {
      developer.log("Error caching categories: $e");
    }
  }

  // Get categories with caching
  Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      // Use cache if available
      if (_categoriesCache.containsKey('all')) {
        return _categoriesCache['all']!;
      }

      // Otherwise fetch and cache
      await _fetchAndCacheCategories();
      return _categoriesCache['all'] ?? [];
    } catch (e) {
      developer.log("Error fetching categories: $e");
      return [];
    }
  }

  // SECTION: DEVICE MANAGEMENT

  // Get user devices with real-time updates support
  Stream<List<Map<String, dynamic>>> watchUserDevices(String userId) {
    try {
      // Create a stream from Firestore
      Stream<QuerySnapshot> deviceStream =
          _firestore
              .collection('devices')
              .where('is_user_added', isEqualTo: 1)
              .where('user_id', isEqualTo: userId)
              .snapshots();

      // Transform snapshot to our device list format
      deviceStream.listen((snapshot) {
        List<Map<String, dynamic>> devices =
            snapshot.docs.map((doc) {
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
              data['id'] = doc.id;
              return data;
            }).toList();

        // Update device cache
        _deviceCache[userId] = devices;

        // Broadcast the update
        _userDevicesStreamController.add(devices);
      });

      return userDevicesStream;
    } catch (e) {
      developer.log("Error watching user devices: $e");
      return Stream.value([]);
    }
  }

  // Get user devices (one-time fetch)
  Future<List<Map<String, dynamic>>> getUserDevices(String userId) async {
    try {
      // Use cache if available
      if (_deviceCache.containsKey(userId)) {
        return _deviceCache[userId]!;
      }

      // Fetch from database
      QuerySnapshot snapshot =
          await _firestore
              .collection('devices')
              .where('is_user_added', isEqualTo: 1)
              .where('user_id', isEqualTo: userId)
              .get();

      List<Map<String, dynamic>> devices =
          snapshot.docs.map((doc) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id;
            return data;
          }).toList();

      // Cache the result
      _deviceCache[userId] = devices;

      return devices;
    } catch (e) {
      developer.log("Error fetching user devices: $e");
      return [];
    }
  }

  // Fetch preset devices (template devices)
  Future<List<Map<String, dynamic>>> getPresetDevices({int? categoryId}) async {
    try {
      // Build query
      Query query = _firestore
          .collection('devices')
          .where('is_user_added', isEqualTo: 0);

      // Add category filter if provided
      if (categoryId != null) {
        query = query.where('category_id', isEqualTo: categoryId);
      }

      // Execute query
      QuerySnapshot snapshot = await query.get();

      return snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      developer.log("Error fetching preset devices: $e");
      return [];
    }
  }

  // Add a user device (optimized transaction)
  Future<String?> addUserDevice({
    required String userId,
    required int categoryId,
    required String manufacturer,
    required String model,
    required double powerConsumption,
    double usageHoursPerDay = 0,
  }) async {
    try {
      String? deviceId;

      // Use a transaction to ensure consistency
      await _firestore.runTransaction((transaction) async {
        // Check for existing preset device
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
          // Update existing preset device
          String existingId = presetSnapshot.docs.first.id;
          transaction.update(_firestore.collection('devices').doc(existingId), {
            'is_user_added': 1,
            'user_id': userId,
            'usage_hours_per_day': usageHoursPerDay,
            'last_updated': FieldValue.serverTimestamp(),
          });
          deviceId = existingId;
        } else {
          // Create a new device document
          DocumentReference newDeviceRef =
              _firestore.collection('devices').doc();
          transaction.set(newDeviceRef, {
            'category_id': categoryId,
            'manufacturer': manufacturer,
            'model': model,
            'power_consumption': powerConsumption,
            'usage_hours_per_day': usageHoursPerDay,
            'is_user_added': 1,
            'user_id': userId,
            'created_at': FieldValue.serverTimestamp(),
            'last_updated': FieldValue.serverTimestamp(),
          });
          deviceId = newDeviceRef.id;
        }
      });

      // Update consumption history (outside transaction for performance)
      await updateConsumptionHistory(userId);

      // Invalidate cache
      _deviceCache.remove(userId);

      developer.log("Device added successfully: $deviceId");
      return deviceId;
    } catch (e) {
      developer.log("Error adding device: $e");
      rethrow;
    }
  }

  // Update a user device
  Future<void> updateUserDevice({
    required String deviceId,
    required String userId,
    required int categoryId,
    required String manufacturer,
    required String model,
    required double powerConsumption,
    required double usageHoursPerDay,
  }) async {
    try {
      await _firestore.collection('devices').doc(deviceId).update({
        'category_id': categoryId,
        'manufacturer': manufacturer,
        'model': model,
        'power_consumption': powerConsumption,
        'usage_hours_per_day': usageHoursPerDay,
        'is_user_added': 1,
        'user_id': userId,
        'last_updated': FieldValue.serverTimestamp(),
      });

      // Update consumption data
      await updateConsumptionHistory(userId);

      // Invalidate cache
      _deviceCache.remove(userId);

      developer.log("Device updated: $deviceId");
    } catch (e) {
      developer.log("Error updating device: $e");
      rethrow;
    }
  }

  // Delete a user device
  Future<void> deleteUserDevice(String deviceId, String userId) async {
    try {
      await _firestore.collection('devices').doc(deviceId).delete();

      // Update consumption data
      await updateConsumptionHistory(userId);

      // Invalidate cache
      _deviceCache.remove(userId);

      developer.log("Device deleted: $deviceId");
    } catch (e) {
      developer.log("Error deleting device: $e");
      rethrow;
    }
  }

  // SECTION: CONSUMPTION HISTORY MANAGEMENT

  // Update consumption history
  Future<void> updateConsumptionHistory(String userId) async {
    try {
      // Calculate total consumption
      List<Map<String, dynamic>> devices = await getUserDevices(userId);
      double totalConsumption = 0.0;

      for (var device in devices) {
        totalConsumption +=
            (device['power_consumption'] ?? 0) *
            (device['usage_hours_per_day'] ?? 0);
      }

      // Get today's date
      String today = DateTime.now().toIso8601String().split('T')[0];

      // Reference to today's document
      DocumentReference dailyRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .doc(today);

      // Get current document if exists
      DocumentSnapshot doc = await dailyRef.get();

      if (!doc.exists) {
        // Create new document
        await dailyRef.set({
          'date': today,
          'total_consumption': totalConsumption,
          'timestamp': FieldValue.serverTimestamp(),
          'hourly_consumption': {},
          'devices_consumption': _buildDevicesConsumption(devices),
        });
      } else {
        // Update existing document
        await dailyRef.update({
          'total_consumption': totalConsumption,
          'devices_consumption': _buildDevicesConsumption(devices),
          'last_updated': FieldValue.serverTimestamp(),
        });
      }

      // Record hourly data
      await recordHourlyConsumption(userId, totalConsumption);

      developer.log(
        "Consumption history updated for user $userId: $totalConsumption kWh",
      );
    } catch (e) {
      developer.log("Error updating consumption history: $e");
    }
  }

  // Helper to build device-specific consumption data
  Map<String, dynamic> _buildDevicesConsumption(
    List<Map<String, dynamic>> devices,
  ) {
    Map<String, dynamic> result = {};

    for (var device in devices) {
      String deviceId = device['id'];
      double dailyConsumption =
          (device['power_consumption'] ?? 0) *
          (device['usage_hours_per_day'] ?? 0);

      result[deviceId] = {
        'manufacturer': device['manufacturer'],
        'model': device['model'],
        'daily_consumption': dailyConsumption,
      };
    }

    return result;
  }

  // Record hourly consumption with a more accurate usage pattern
  Future<void> recordHourlyConsumption(
    String userId,
    double totalDailyConsumption,
  ) async {
    try {
      // Current date and hour
      String today = DateTime.now().toIso8601String().split('T')[0];
      int currentHour = DateTime.now().hour;

      // Get devices
      List<Map<String, dynamic>> devices = await getUserDevices(userId);

      if (devices.isEmpty) return;

      // Reference to today's document
      DocumentReference dailyRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .doc(today);

      // Get current data
      DocumentSnapshot doc = await dailyRef.get();
      Map<String, dynamic> existingHourlyData = {};

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('hourly_consumption')) {
          existingHourlyData = Map<String, dynamic>.from(
            data['hourly_consumption'],
          );
        }
      }

      // Calculate hourly consumption with a more realistic pattern
      double hourlyConsumption = _calculateHourlyConsumption(
        devices,
        currentHour,
      );

      // Update hourly data
      existingHourlyData[currentHour.toString()] = hourlyConsumption;

      // Calculate total based on recorded hours
      double calculatedTotal = existingHourlyData.entries.fold(
        0.0,
        (sumValue, entry) => sumValue + (entry.value as num).toDouble(),
      );

      // Update document
      await dailyRef.set({
        'hourly_consumption': existingHourlyData,
        'total_consumption': calculatedTotal,
        'date': today,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      developer.log(
        "Recorded hourly consumption for hour $currentHour: $hourlyConsumption kWh",
      );
    } catch (e) {
      developer.log("Error recording hourly consumption: $e");
    }
  }

  // Calculate hourly consumption with usage patterns
  double _calculateHourlyConsumption(
    List<Map<String, dynamic>> devices,
    int currentHour,
  ) {
    double hourlyTotal = 0.0;

    // Define time-of-day usage patterns
    final Map<int, Map<String, dynamic>> usagePatterns = {
      // Morning peak (7-9 AM)
      7: {
        'adjustment': 1.5,
        'categories': <int, double>{4: 1.8, 5: 2.0, 8: 1.2},
      },
      8: {
        'adjustment': 1.6,
        'categories': <int, double>{4: 1.9, 5: 2.2, 8: 1.3},
      },
      9: {
        'adjustment': 1.3,
        'categories': <int, double>{4: 1.5, 5: 1.8, 8: 1.2},
      },

      // Mid-day (10-16)
      10: {
        'adjustment': 0.9,
        'categories': <int, double>{2: 0.6, 9: 1.5},
      },
      11: {
        'adjustment': 0.8,
        'categories': <int, double>{2: 0.5, 9: 1.5},
      },
      12: {
        'adjustment': 1.0,
        'categories': <int, double>{2: 0.6, 5: 1.5, 9: 1.4},
      },
      13: {
        'adjustment': 1.1,
        'categories': <int, double>{2: 0.7, 5: 1.6, 9: 1.4},
      },
      14: {
        'adjustment': 0.9,
        'categories': <int, double>{2: 0.7, 9: 1.3},
      },
      15: {
        'adjustment': 0.8,
        'categories': <int, double>{2: 0.8, 9: 1.2},
      },
      16: {
        'adjustment': 0.9,
        'categories': <int, double>{2: 1.0, 9: 1.0},
      },

      // Evening peak (17-22)
      17: {
        'adjustment': 1.2,
        'categories': <int, double>{1: 1.5, 2: 1.5, 5: 1.4},
      },
      18: {
        'adjustment': 1.5,
        'categories': <int, double>{1: 1.8, 2: 1.7, 5: 1.8, 6: 1.9},
      },
      19: {
        'adjustment': 1.7,
        'categories': <int, double>{1: 1.9, 2: 2.0, 5: 1.5, 6: 2.0},
      },
      20: {
        'adjustment': 1.8,
        'categories': <int, double>{1: 2.0, 2: 2.1, 8: 1.5},
      },
      21: {
        'adjustment': 1.6,
        'categories': <int, double>{1: 1.8, 2: 2.0, 8: 1.7},
      },
      22: {
        'adjustment': 1.2,
        'categories': <int, double>{1: 1.3, 2: 1.5, 8: 1.8},
      },

      // Night (23-6)
      23: {
        'adjustment': 0.7,
        'categories': <int, double>{2: 0.8, 8: 0.5},
      },
      0: {
        'adjustment': 0.4,
        'categories': <int, double>{2: 0.3, 8: 0.2},
      },
      1: {
        'adjustment': 0.3,
        'categories': <int, double>{8: 0.1},
      },
      2: {
        'adjustment': 0.2,
        'categories': <int, double>{8: 0.1},
      },
      3: {
        'adjustment': 0.2,
        'categories': <int, double>{8: 0.1},
      },
      4: {
        'adjustment': 0.3,
        'categories': <int, double>{8: 0.2},
      },
      5: {
        'adjustment': 0.5,
        'categories': <int, double>{8: 0.3},
      },
      6: {
        'adjustment': 0.8,
        'categories': <int, double>{4: 1.2, 5: 1.5, 8: 0.8},
      },
    };

    // Get pattern for current hour
    Map<String, dynamic> hourPattern =
        usagePatterns[currentHour] ??
        {'adjustment': 1.0, 'categories': <int, double>{}};

    double defaultAdjustment = hourPattern['adjustment'] as double;
    Map<int, double> categoryAdjustments =
        hourPattern['categories'] as Map<int, double>;

    // Calculate hourly consumption for each device
    for (var device in devices) {
      int categoryId = device['category_id'] ?? 0;
      double devicePower = device['power_consumption'] ?? 0.0;
      double hoursPerDay = device['usage_hours_per_day'] ?? 0.0;

      if (hoursPerDay <= 0) continue;

      // Get the appropriate adjustment factor for this device category
      double adjustmentFactor =
          categoryAdjustments[categoryId] ?? defaultAdjustment;

      // Calculate hourly consumption with adjustment
      double baseHourlyRate = devicePower * (hoursPerDay / 24);
      double adjustedHourlyRate = baseHourlyRate * adjustmentFactor;

      hourlyTotal += adjustedHourlyRate;
    }

    return hourlyTotal;
  }

  // Get hourly consumption for a specific date
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
      developer.log("Error fetching hourly consumption: $e");
      return {};
    }
  }

  // Get daily consumption for a date range
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
      developer.log("Error fetching daily consumption: $e");
      return [];
    }
  }

  // SECTION: AGGREGATED DATA AND ANALYTICS

  // Get weekly consumption aggregated data
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

        // Format as year-weekNumber (e.g., "2023-W12")
        int weekNumber = _getWeekNumber(date);
        String weekKey = "${date.year}-W$weekNumber";

        if (!weeklyAggregation.containsKey(weekKey)) {
          weeklyAggregation[weekKey] = {
            'week': weekKey,
            'start_date':
                _getFirstDayOfWeek(date).toIso8601String().split('T')[0],
            'end_date': _getLastDayOfWeek(date).toIso8601String().split('T')[0],
            'total_consumption': 0.0,
            'days_count': 0,
          };
        }

        // Add consumption data
        double dailyConsumption = dailyEntry['total_consumption'] ?? 0.0;
        weeklyAggregation[weekKey]!['total_consumption'] += dailyConsumption;
        weeklyAggregation[weekKey]!['days_count'] += 1;
      }

      // Convert to list and sort
      List<Map<String, dynamic>> result = weeklyAggregation.values.toList();
      result.sort((a, b) => a['start_date'].compareTo(b['start_date']));

      return result;
    } catch (e) {
      developer.log("Error calculating weekly consumption: $e");
      return [];
    }
  }

  // Get monthly consumption aggregated data
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
          monthlyAggregation[monthKey] = {
            'month': monthKey,
            'month_name': _getMonthName(date.month),
            'year': date.year,
            'total_consumption': 0.0,
            'days_count': 0,
          };
        }

        // Add consumption data
        double dailyConsumption = dailyEntry['total_consumption'] ?? 0.0;
        monthlyAggregation[monthKey]!['total_consumption'] += dailyConsumption;
        monthlyAggregation[monthKey]!['days_count'] += 1;
      }

      // Convert to list and sort
      List<Map<String, dynamic>> result = monthlyAggregation.values.toList();
      result.sort((a, b) => a['month'].compareTo(b['month']));

      return result;
    } catch (e) {
      developer.log("Error calculating monthly consumption: $e");
      return [];
    }
  }

  // SECTION: UTILITY METHODS

  // Get week number for a date
  int _getWeekNumber(DateTime date) {
    // Calculate the day of the year
    int dayOfYear =
        int.parse(
          DateTime(
            date.year,
            date.month,
            date.day,
          ).difference(DateTime(date.year, 1, 1)).inDays.toString(),
        ) +
        1;

    // Calculate the day of the week (1 = Monday, 7 = Sunday)
    int dayOfWeek = date.weekday;

    // Calculate the week number
    return ((dayOfYear - dayOfWeek + 10) / 7).floor();
  }

  // Get first day of the week containing the given date
  DateTime _getFirstDayOfWeek(DateTime date) {
    // DateTime uses 1 for Monday, 7 for Sunday
    int daysToSubtract = date.weekday - 1; // 0 for Monday, 6 for Sunday
    return DateTime(date.year, date.month, date.day - daysToSubtract);
  }

  // Get last day of the week containing the given date
  DateTime _getLastDayOfWeek(DateTime date) {
    // DateTime uses 1 for Monday, 7 for Sunday
    int daysToAdd = 7 - date.weekday; // 6 for Monday, 0 for Sunday
    return DateTime(date.year, date.month, date.day + daysToAdd);
  }

  // Get month name from month number
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

  // Cleanup resources
  void dispose() {
    _userDevicesStreamController.close();
    _consumptionStreamController.close();
  }
}
