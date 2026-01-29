import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // Generated when you set up Firebase in your Flutter project
import 'dart:developer' as developer;

void main() async {
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final firestore = FirebaseFirestore.instance;

  // List of categories with realistic IDs and names
  final categories = [
    {"id": "1", "name": "Air Conditioner"},
    {"id": "2", "name": "TV"},
    {"id": "3", "name": "Refrigerator"},
    {"id": "4", "name": "Washing Machine"},
    {"id": "5", "name": "Microwave"},
    {"id": "6", "name": "Electric Oven"},
    {"id": "7", "name": "Water Heater"},
    {"id": "8", "name": "Lighting"},
    {"id": "9", "name": "Computer"},
    {"id": "10", "name": "Vacuum Cleaner"},
  ];

  // Add categories to Firestore, skipping duplicates based on id
  await addCategories(firestore, categories);
  developer.log("Categories added successfully");

  // Add preset devices to Firestore
  await addPresetDevices(firestore);
  developer.log("Preset devices added successfully");

  // Add consumption history for testing
  await addConsumptionHistory(firestore);
  developer.log("Consumption history added successfully");
}

Future<void> addConsumptionHistory(FirebaseFirestore firestore) async {
  try {
    // Get all users
    QuerySnapshot usersSnapshot = await firestore.collection('users').get();
    
    for (var userDoc in usersSnapshot.docs) {
      String userId = userDoc.id;
      developer.log("Adding consumption history for user: $userId");

      // Get user's devices
      QuerySnapshot devicesSnapshot = await firestore
          .collection('devices')
          .where('user_id', isEqualTo: userId)
          .get();

      // Calculate total consumption from user's devices
      double totalConsumption = 0.0;
      for (var device in devicesSnapshot.docs) {
        Map<String, dynamic> deviceData = device.data() as Map<String, dynamic>;
        totalConsumption += (deviceData['power_consumption'] ?? 0) * (deviceData['usage_hours_per_day'] ?? 0);
      }

      // Add consumption history for the last 30 days
      DateTime now = DateTime.now();
      for (int i = 0; i < 30; i++) {
        DateTime date = now.subtract(Duration(days: i));
        String dateStr = date.toIso8601String().split('T')[0];

        // Add some random variation to the consumption (-10% to +10%)
        double randomFactor = 0.9 + (DateTime.now().millisecondsSinceEpoch % 200) / 1000; // Between 0.9 and 1.1
        double dailyConsumption = totalConsumption * randomFactor;

        await firestore
            .collection('users')
            .doc(userId)
            .collection('consumption_history')
            .doc(dateStr)
            .set({
          'date': dateStr,
          'total_consumption': dailyConsumption,
          'timestamp': FieldValue.serverTimestamp(),
        });

        developer.log("Added consumption history for date $dateStr: $dailyConsumption kWh");
      }

      developer.log("Completed adding consumption history for user: $userId");
    }
  } catch (e) {
    developer.log("Error adding consumption history: $e");
    rethrow;
  }
}

// Function to add categories with duplicate check based on id
Future<void> addCategories(FirebaseFirestore firestore, List<Map<String, dynamic>> categories) async {
  for (var category in categories) {
    final docRef = firestore.collection('categories').doc(category['id'] as String);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) {
      await docRef.set(category);
      developer.log('Added category: ${category['name']}');
    } else {
      developer.log('Skipped duplicate category: ${category['name']}');
    }
  }
}

// Function to add preset devices with duplicate check based on manufacturer and model
Future<void> addPresetDevices(FirebaseFirestore firestore) async {
  // List of preset devices
  final presetDevices = [
    {
      "id": "1",
      "category_id": "1",
      "manufacturer": "Samsung",
      "model": "AC-5000",
      "power_consumption": 1.5,
      "usage_hours_per_day": 4.0,
      "is_user_added": 0,
      "user_id": null,
    },
    {
      "id": "2",
      "category_id": "1",
      "manufacturer": "LG",
      "model": "AC-6000",
      "power_consumption": 1.8,
      "usage_hours_per_day": 3.0,
      "is_user_added": 0,
      "user_id": null,
    },
    // Add more preset devices as needed
  ];

  for (var device in presetDevices) {
    // Query to check if a device with the same manufacturer and model already exists
    final querySnapshot = await firestore
        .collection('devices')
        .where('manufacturer', isEqualTo: device['manufacturer'])
        .where('model', isEqualTo: device['model'])
        .get();

    if (querySnapshot.docs.isEmpty) {
      // If no duplicate is found, add the device using its provided id
      final docRef = firestore.collection('devices').doc(device['id'] as String);
      await docRef.set(device);
      developer.log('Added device: ${device['manufacturer']} ${device['model']}');
    } else {
      developer.log('Skipped duplicate device: ${device['manufacturer']} ${device['model']}');
    }
  }
}