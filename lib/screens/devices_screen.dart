import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import '../utils/conversion_utilities.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localization/app_localizations.dart';
import '../localization/language_provider.dart';
import '../database/database_helper.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _userDevices = [];
  String _energyUnit = 'kWh';
  String _currentLanguage = '';

  @override
  void initState() {
    super.initState();
    _fetchData();
    _loadSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageProvider = Provider.of<LanguageProvider>(context);
    if (_currentLanguage != languageProvider.locale.languageCode) {
      _currentLanguage = languageProvider.locale.languageCode;
      // Force rebuild when language changes
      setState(() {});
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _energyUnit = prefs.getString('energyUnit') ?? 'kWh';
      });
    }
  }

  Future<void> _fetchData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Add a small delay to ensure the UI updates properly
      await Future.delayed(const Duration(milliseconds: 100));

      // Fetch fresh data from Firestore directly
      final userId = FirebaseAuth.instance.currentUser!.uid;

      // Clear existing data first
      _categories = [];
      _userDevices = [];

      // Get categories
      _categories = await DatabaseHelper.instance.getCategories();
      debugPrint('Fetched categories: $_categories');

      // Direct Firestore query to ensure we get the latest data
      // Make sure we only get devices that are explicitly marked as user devices (is_user_added = 1)
      // and belong to the current user
      final devicesSnapshot =
          await FirebaseFirestore.instance
              .collection('devices')
              .where('user_id', isEqualTo: userId)
              .where(
                'is_user_added',
                isEqualTo: 1,
              ) // Add this to ensure only user devices are shown
              .get();

      // Transform the data
      for (var doc in devicesSnapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id; // Ensure the ID is included
        _userDevices.add(data);
      }

      debugPrint('Fetched user devices directly: ${_userDevices.length}');

      // Force a rebuild even if the lists appear the same
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Set default values in case of error to prevent UI issues
          _categories = _categories.isEmpty ? [] : _categories;
          _userDevices = _userDevices.isEmpty ? [] : _userDevices;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error fetching data: $e',
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  void _showAddDevicePopup() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissal by tapping outside
      builder:
          (context) => AddDeviceDialog(
            categories: _categories,
            onSave: () async {
              // Refresh data without showing loading indicator
              await _refreshDataWithoutLoading();
            },
          ),
    );
  }

  void _showCustomDevicePopup() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissal by tapping outside
      builder:
          (context) => CustomDeviceDialog(
            categories: _categories,
            onSave: () async {
              // Refresh data without showing loading indicator
              await _refreshDataWithoutLoading();
            },
          ),
    );
  }

  // Helper method to refresh data without showing loading indicator
  Future<void> _refreshDataWithoutLoading() async {
    if (!mounted) return;

    try {
      // Add a small delay to ensure UI has time to settle after dialog dismissal
      await Future.delayed(const Duration(milliseconds: 100));

      // Fetch fresh data from Firestore directly
      final userId = FirebaseAuth.instance.currentUser!.uid;

      // Get categories
      List<Map<String, dynamic>> freshCategories =
          await DatabaseHelper.instance.getCategories();

      // Direct Firestore query to ensure we get the latest data
      final devicesSnapshot =
          await FirebaseFirestore.instance
              .collection('devices')
              .where('user_id', isEqualTo: userId)
              .where(
                'is_user_added',
                isEqualTo: 1,
              ) // Add this to ensure only user devices are shown
              .get();

      // Transform the data
      List<Map<String, dynamic>> freshDevices = [];
      for (var doc in devicesSnapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id; // Ensure the ID is included
        freshDevices.add(data);
      }

      // Only update state if the component is still mounted
      if (mounted) {
        setState(() {
          _categories = freshCategories;
          _userDevices = freshDevices;
          _isLoading = false; // Ensure loading state is false
        });
      }

      debugPrint('Refreshed data silently: ${freshDevices.length} devices');
    } catch (e) {
      debugPrint('Error refreshing data: $e');
      // Set loading to false even on error
      if (mounted) {
        setState(() {
          _isLoading = false;

          // Show error message to help debugging
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.amber,
              content: Text(
                'Data refresh error. Please restart the app if issues persist.',
                style: const TextStyle(color: Colors.black),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        });
      }
    }
  }

  void _showEditDevicePopup(Map<String, dynamic> device) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder:
          (context) => EditDeviceDialog(
            categories: _categories,
            device: device,
            onSave: () async {
              // Refresh data without showing loading indicator
              await _refreshDataWithoutLoading();
            },
          ),
    );
  }

  // Method to delete a device from user's devices without permanently removing preset devices
  Future<void> _deleteDevice(String deviceId) async {
    try {
      // Get the device document to check if it was originally a preset device
      final deviceDoc =
          await FirebaseFirestore.instance
              .collection('devices')
              .doc(deviceId)
              .get();

      if (!deviceDoc.exists) {
        throw Exception("Device not found");
      }

      Map<String, dynamic> deviceData =
          deviceDoc.data() as Map<String, dynamic>;

      // Check if this device was a preset device (is_user_added == 0 originally)
      // Since preset devices in this app are identified by is_user_added == 0
      bool wasPresetDevice = false;

      // If the device has a flag indicating it was a preset device
      if (deviceData.containsKey('is_preset') &&
          deviceData['is_preset'] == true) {
        wasPresetDevice = true;
      }
      // Or if there's no specific flag but it's a known model from the presets
      else {
        // Get all preset devices to see if this is one of them
        QuerySnapshot presetSnapshot =
            await FirebaseFirestore.instance
                .collection('devices')
                .where('is_user_added', isEqualTo: 0)
                .where('manufacturer', isEqualTo: deviceData['manufacturer'])
                .where('model', isEqualTo: deviceData['model'])
                .limit(1)
                .get();

        wasPresetDevice = presetSnapshot.docs.isNotEmpty;
      }

      if (wasPresetDevice) {
        // It was a preset device, make it available for others by setting is_user_added to 0
        // and clearing user-specific data
        await FirebaseFirestore.instance
            .collection('devices')
            .doc(deviceId)
            .update({
              'is_user_added': 0,
              'user_id': null,
              'is_preset':
                  true, // Mark explicitly as a preset for future reference
              'daily_uptime': 0.0,
              'total_uptime': 0.0,
              'daily_consumption': 0.0,
              'last_reset': null,
              'last_active': null,
            });
        debugPrint(
          "Restored device ${deviceData['model']} to preset collection",
        );
      } else {
        // It was a custom device, delete it completely
        await FirebaseFirestore.instance
            .collection('devices')
            .doc(deviceId)
            .delete();
        debugPrint("Deleted custom device ${deviceData['model']}");
      }

      // Remove from local state for immediate UI update
      setState(() {
        _userDevices.removeWhere((device) => device['id'] == deviceId);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text(
            'device_deleted'.tr(context),
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Error deleting device: $e',
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  IconData _getCategoryIcon(dynamic categoryId) {
    // Handle both string and int types for categoryId
    String categoryIdStr = categoryId.toString();

    final category = _categories.firstWhere(
      (cat) => cat['id'].toString() == categoryIdStr,
      orElse: () => {'name': 'Unknown'},
    );

    switch (category['name'] as String) {
      case 'Air Conditioner':
        return Icons.ac_unit;
      case 'TV':
        return Icons.tv;
      case 'Refrigerator':
        return Icons.kitchen;
      case 'Washing Machine':
        return Icons.local_laundry_service;
      case 'Microwave':
        return Icons.microwave; // Updated icon for Microwave
      case 'Electric Oven':
        return Icons.local_dining;
      case 'Water Heater':
        return Icons.hot_tub;
      case 'Lighting':
        return Icons.lightbulb;
      case 'Computer':
        return Icons.computer;
      case 'Vacuum Cleaner':
        return Icons.cleaning_services;
      default:
        return Icons.device_unknown;
    }
  }

  String categoryName(dynamic categoryId) {
    // Handle both string and int types for categoryId
    String categoryIdStr = categoryId.toString();

    final category = _categories.firstWhere(
      (cat) => cat['id'].toString() == categoryIdStr,
      orElse: () => {'name': 'Unknown'},
    );

    return category['name'] as String? ?? 'Unknown';
  }

  String _formatEnergyValue(double valueInKWh) {
    try {
      double convertedValue = ConversionUtilities.convertEnergy(
        valueInKWh,
        'kWh',
        _energyUnit,
      );
      return "${convertedValue.toStringAsFixed(2)} $_energyUnit";
    } catch (e) {
      return "$valueInKWh kWh";
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDarkTheme = themeProvider.isDarkTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body:
          _isLoading
              ? Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors:
                        isDarkTheme
                            ? [Color.fromRGBO(68, 138, 255, 0.2), Colors.black]
                            : [Colors.white, Colors.grey[200]!],
                  ),
                ),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.blueAccent),
                ),
              )
              : AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: _buildDeviceList(isDarkTheme),
              ),
    );
  }

  Widget _buildDeviceList(bool isDarkTheme) {
    return Container(
      key: ValueKey<String>(
        'device-list-${_userDevices.length}-${DateTime.now().millisecondsSinceEpoch}',
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors:
              isDarkTheme
                  ? [Color.fromRGBO(68, 138, 255, 0.2), Colors.black]
                  : [Colors.white, Colors.grey[200]!],
        ),
      ),
      child: SafeArea(
        bottom:
            false, // Don't apply safe area at bottom to allow custom padding
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'devices'.tr(context),
                    style: GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.white : Colors.black,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    children: [
                      // Info button with tooltip
                      IconButton(
                        icon: Icon(
                          Icons.info_outline,
                          color: Colors.blueAccent,
                          size: 24,
                        ),
                        onPressed: () {
                          _showTrackingInfoDialog();
                        },
                        tooltip: 'How tracking works',
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _showAddDevicePopup,
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(),
                          backgroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.all(12),
                          elevation: 4,
                        ),
                        child: const Icon(Icons.add, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _showCustomDevicePopup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'custom'.tr(context),
                          style: GoogleFonts.poppins(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Active devices counter
              if (_userDevices.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10.0, bottom: 5.0),
                  child: Row(
                    children: [
                      Icon(Icons.power, size: 16, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        "${_userDevices.where((device) => device['last_active'] != null).length} active device(s)",
                        style: GoogleFonts.poppins(
                          color: isDarkTheme ? Colors.white70 : Colors.black54,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 10),
              Expanded(
                child:
                    _userDevices.isEmpty
                        ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.devices,
                                size: 100,
                                color:
                                    isDarkTheme
                                        ? Colors.white.withAlpha(179)
                                        : Colors.grey,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                "no_devices_added".tr(context),
                                style: GoogleFonts.poppins(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      isDarkTheme ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "tap_to_add_device".tr(context),
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color:
                                      isDarkTheme
                                          ? Colors.white70
                                          : Colors.black54,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                        : ListView.builder(
                          key: ValueKey('devices-list'),
                          physics: const AlwaysScrollableScrollPhysics(),
                          // Add extra bottom padding to ensure last device's controls are visible
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: _userDevices.length,
                          itemBuilder: (context, index) {
                            final device = _userDevices[index];
                            final power =
                                device['power_consumption'] as double? ?? 0.0;
                            final deviceId = device['id'] as String? ?? '';
                            final isActive = device['last_active'] != null;

                            return AnimatedBuilder(
                              animation: CurvedAnimation(
                                parent:
                                    ModalRoute.of(context)?.animation ??
                                    const AlwaysStoppedAnimation(1),
                                curve: Interval(
                                  0.0,
                                  1.0,
                                  curve: Curves.easeInOut,
                                ),
                              ),
                              builder: (context, child) {
                                return FadeTransition(
                                  opacity: Tween<double>(
                                    begin: 0.5,
                                    end: 1.0,
                                  ).animate(
                                    CurvedAnimation(
                                      parent:
                                          ModalRoute.of(context)?.animation ??
                                          const AlwaysStoppedAnimation(1),
                                      curve: Interval(
                                        (index / _userDevices.length) * 0.5,
                                        0.5 +
                                            (index / _userDevices.length) * 0.5,
                                        curve: Curves.easeInOut,
                                      ),
                                    ),
                                  ),
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.05, 0),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent:
                                            ModalRoute.of(context)?.animation ??
                                            const AlwaysStoppedAnimation(1),
                                        curve: Interval(
                                          (index / _userDevices.length) * 0.5,
                                          0.5 +
                                              (index / _userDevices.length) *
                                                  0.5,
                                          curve: Curves.easeInOut,
                                        ),
                                      ),
                                    ),
                                    child: child!,
                                  ),
                                );
                              },
                              child: Card(
                                color:
                                    isDarkTheme
                                        ? Colors.white.withAlpha(26)
                                        : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                    color:
                                        isDarkTheme
                                            ? Colors.blueAccent.withAlpha(40)
                                            : Colors.grey.withAlpha(40),
                                    width: 1,
                                  ),
                                ),
                                elevation: isDarkTheme ? 8 : 3,
                                shadowColor:
                                    isDarkTheme
                                        ? Colors.blue.withAlpha(60)
                                        : Colors.black26,
                                margin: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 2,
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  splashColor: Colors.blue.withAlpha(30),
                                  highlightColor: Colors.blue.withAlpha(15),
                                  onTap:
                                      () {}, // Optional: could show a detailed view
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Header with colored accent and device type icon
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withAlpha(
                                            isDarkTheme ? 40 : 20,
                                          ),
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(20),
                                            topRight: Radius.circular(20),
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            // Device icon with background
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color:
                                                    isDarkTheme
                                                        ? Colors.black12
                                                        : Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Icon(
                                                _getCategoryIcon(
                                                  device['category_id'],
                                                ),
                                                color: Colors.blueAccent,
                                                size: 24,
                                              ),
                                            ),
                                            const SizedBox(width: 12),

                                            // Device name and category
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${device['manufacturer'] ?? 'Unknown'} ${device['model'] ?? ''}',
                                                    style: GoogleFonts.poppins(
                                                      color:
                                                          isDarkTheme
                                                              ? Colors.white
                                                              : Colors.black87,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    'Category: ${categoryName(device['category_id'])}',
                                                    style: GoogleFonts.poppins(
                                                      color:
                                                          isDarkTheme
                                                              ? Colors.white70
                                                              : Colors.black54,
                                                      fontSize: 12,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Device active status switch
                                            Row(
                                              children: [
                                                Text(
                                                  isActive
                                                      ? 'Active'
                                                      : 'Inactive',
                                                  style: GoogleFonts.poppins(
                                                    color:
                                                        isActive
                                                            ? Colors.green
                                                            : (isDarkTheme
                                                                ? Colors.white70
                                                                : Colors
                                                                    .black54),
                                                    fontSize: 12,
                                                    fontWeight:
                                                        isActive
                                                            ? FontWeight.w600
                                                            : FontWeight.normal,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Switch(
                                                  value: isActive,
                                                  activeColor: Colors.green,
                                                  activeTrackColor: Colors.green
                                                      .withAlpha(128),
                                                  inactiveThumbColor:
                                                      isDarkTheme
                                                          ? Colors.grey[400]
                                                          : Colors.grey[300],
                                                  inactiveTrackColor:
                                                      isDarkTheme
                                                          ? Colors.grey[700]
                                                          : Colors.grey[200],
                                                  onChanged: (value) {
                                                    _toggleDeviceActive(
                                                      deviceId,
                                                      value,
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Power consumption details with icons
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        child: Column(
                                          children: [
                                            // Power consumption row
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.power,
                                                  size: 18,
                                                  color:
                                                      isDarkTheme
                                                          ? Colors.blue[300]
                                                          : Colors.blue[600],
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    "${'power_consumption'.tr(context)}: ${power.toStringAsFixed(2)} kW",
                                                    style: GoogleFonts.poppins(
                                                      color:
                                                          isDarkTheme
                                                              ? Colors.white70
                                                              : Colors.black87,
                                                      fontSize: 13,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),

                                            // Usage hours row
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.access_time,
                                                  size: 18,
                                                  color:
                                                      isDarkTheme
                                                          ? Colors.blue[300]
                                                          : Colors.blue[600],
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    "${'uptime'.tr(context)}: ${(device['daily_uptime'] ?? 0.0).toStringAsFixed(1)} hrs/day",
                                                    style: GoogleFonts.poppins(
                                                      color:
                                                          isDarkTheme
                                                              ? Colors.white70
                                                              : Colors.black87,
                                                      fontSize: 13,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),

                                            // Daily consumption row with highlight
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.bolt,
                                                  size: 18,
                                                  color:
                                                      isDarkTheme
                                                          ? Colors.amber[300]
                                                          : Colors.amber[700],
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    "${'daily_consumption'.tr(context)}: ${_formatEnergyValue(device['daily_consumption'] ?? 0.0)}",
                                                    style: GoogleFonts.poppins(
                                                      color:
                                                          isDarkTheme
                                                              ? Colors
                                                                  .amber[300]
                                                              : Colors
                                                                  .amber[700],
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Action buttons with subtle separator
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                          horizontal: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            top: BorderSide(
                                              color:
                                                  isDarkTheme
                                                      ? Colors.white12
                                                      : Colors.black12,
                                              width: 0.5,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            // Edit button
                                            TextButton.icon(
                                              onPressed:
                                                  () => _showEditDevicePopup(
                                                    device,
                                                  ),
                                              icon: Icon(
                                                Icons.edit_outlined,
                                                size: 18,
                                                color: Colors.blueAccent,
                                              ),
                                              label: Text(
                                                'edit'.tr(context),
                                                style: GoogleFonts.poppins(
                                                  color: Colors.blueAccent,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              style: TextButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                            ),

                                            // Delete button
                                            TextButton.icon(
                                              onPressed: () {
                                                // Show confirmation dialog before deletion
                                                showDialog(
                                                  context: context,
                                                  builder:
                                                      (context) => AlertDialog(
                                                        backgroundColor:
                                                            isDarkTheme
                                                                ? Colors
                                                                    .grey[900]
                                                                : Colors.white,
                                                        title: Text(
                                                          'delete_device_title'
                                                              .tr(context),
                                                          style: GoogleFonts.poppins(
                                                            color:
                                                                isDarkTheme
                                                                    ? Colors
                                                                        .white
                                                                    : Colors
                                                                        .black,
                                                            fontSize: 20,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        content: Text(
                                                          'delete_device_confirmation'
                                                              .tr(context),
                                                          style: GoogleFonts.poppins(
                                                            color:
                                                                isDarkTheme
                                                                    ? Colors
                                                                        .white70
                                                                    : Colors
                                                                        .black87,
                                                          ),
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed:
                                                                () =>
                                                                    Navigator.of(
                                                                      context,
                                                                    ).pop(),
                                                            child: Text(
                                                              'cancel'.tr(
                                                                context,
                                                              ),
                                                              style: GoogleFonts.poppins(
                                                                color:
                                                                    isDarkTheme
                                                                        ? Colors
                                                                            .white70
                                                                        : Colors
                                                                            .black54,
                                                              ),
                                                            ),
                                                          ),
                                                          ElevatedButton(
                                                            onPressed: () {
                                                              Navigator.of(
                                                                context,
                                                              ).pop(); // Close dialog
                                                              if (deviceId
                                                                  .isNotEmpty) {
                                                                _deleteDevice(
                                                                  deviceId,
                                                                ); // Delete the device
                                                              } else {
                                                                ScaffoldMessenger.of(
                                                                  context,
                                                                ).showSnackBar(
                                                                  SnackBar(
                                                                    backgroundColor:
                                                                        Colors
                                                                            .red,
                                                                    content: Text(
                                                                      'error_device_id'.tr(
                                                                        context,
                                                                      ),
                                                                      style: const TextStyle(
                                                                        color:
                                                                            Colors.white,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                );
                                                              }
                                                            },
                                                            style: ElevatedButton.styleFrom(
                                                              backgroundColor:
                                                                  Colors
                                                                      .redAccent,
                                                            ),
                                                            child: Text(
                                                              'delete'.tr(
                                                                context,
                                                              ),
                                                              style: GoogleFonts.poppins(
                                                                color:
                                                                    Colors
                                                                        .white,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                );
                                              },
                                              icon: Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                                color: Colors.redAccent,
                                              ),
                                              label: Text(
                                                'delete'.tr(context),
                                                style: GoogleFonts.poppins(
                                                  color: Colors.redAccent,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              style: TextButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Method to toggle device active status
  Future<void> _toggleDeviceActive(String deviceId, bool isActive) async {
    try {
      await DatabaseHelper.instance.updateDeviceUptime(
        deviceId: deviceId,
        isActive: isActive,
      );

      // Refresh data without showing loading indicator
      await _refreshDataWithoutLoading();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(
              isActive ? 'Device activated' : 'Device deactivated',
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Error changing device status: $e',
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  // Show info dialog about how tracking works
  void _showTrackingInfoDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final themeProvider = Provider.of<ThemeProvider>(context);
        final bool isDarkTheme = themeProvider.isDarkTheme;

        return AlertDialog(
          backgroundColor: isDarkTheme ? Colors.grey[900] : Colors.white,
          title: Text(
            'How Energy Tracking Works',
            style: GoogleFonts.poppins(
              color: isDarkTheme ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoItem(
                  isDarkTheme,
                  Icons.power,
                  'Active Devices',
                  'Toggle the switch to mark a device as active or inactive. Active devices will track real-time energy usage.',
                ),
                const SizedBox(height: 16),
                _infoItem(
                  isDarkTheme,
                  Icons.timer,
                  'Device Uptime',
                  'Shows how long your device has been active today. Resets at midnight.',
                ),
                const SizedBox(height: 16),
                _infoItem(
                  isDarkTheme,
                  Icons.bolt,
                  'Daily Consumption',
                  'Calculated from your device\'s power rating and its actual uptime.',
                ),
                const SizedBox(height: 16),
                _infoItem(
                  isDarkTheme,
                  Icons.notifications_active,
                  'Background Tracking',
                  'Your devices will continue tracking energy usage even when the app is closed.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Got it',
                style: GoogleFonts.poppins(
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Helper method to create info items
  Widget _infoItem(
    bool isDarkTheme,
    IconData icon,
    String title,
    String description,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withAlpha(isDarkTheme ? 40 : 20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.blueAccent, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: isDarkTheme ? Colors.white : Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: GoogleFonts.poppins(
                  color: isDarkTheme ? Colors.white70 : Colors.black54,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Dialog for adding a preset device
class AddDeviceDialog extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final VoidCallback onSave;

  const AddDeviceDialog({
    super.key,
    required this.categories,
    required this.onSave,
  });

  @override
  State<AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<AddDeviceDialog> {
  List<Map<String, dynamic>> _allDevices = [];

  // Selected values
  int? _selectedCategoryId;
  String? _selectedManufacturer;
  Map<String, dynamic>? _selectedModel;

  // Filtered lists
  List<String> _manufacturersList = [];
  List<Map<String, dynamic>> _modelsList = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPresetDevices();
  }

  Future<void> _fetchPresetDevices() async {
    setState(() => _isLoading = true);

    try {
      _allDevices = await DatabaseHelper.instance.getPresetDevices();
      debugPrint(
        'Fetched preset devices in dialog: ${_allDevices.length} devices',
      );
    } catch (e) {
      debugPrint('Error fetching preset devices: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Update manufacturers list when category is selected
  void _updateManufacturers() {
    if (_selectedCategoryId == null) {
      setState(() {
        _manufacturersList = [];
        _selectedManufacturer = null;
        _modelsList = [];
        _selectedModel = null;
      });
      return;
    }

    // Filter devices by selected category
    List<Map<String, dynamic>> categoryDevices =
        _allDevices.where((device) {
          if (device['category_id'] == null) return false;

          // Handle string or int type for category_id
          int deviceCategoryId;
          if (device['category_id'] is int) {
            deviceCategoryId = device['category_id'];
          } else {
            deviceCategoryId =
                int.tryParse(device['category_id'].toString()) ?? -1;
          }

          return deviceCategoryId == _selectedCategoryId;
        }).toList();

    // Extract unique manufacturers
    Set<String> manufacturersSet = {};
    for (var device in categoryDevices) {
      String manufacturer = device['manufacturer']?.toString() ?? 'Unknown';
      if (manufacturer.isNotEmpty) {
        manufacturersSet.add(manufacturer);
      }
    }

    setState(() {
      _manufacturersList = manufacturersSet.toList()..sort();
      _selectedManufacturer = null;
      _modelsList = [];
      _selectedModel = null;
    });
  }

  // Update models list when manufacturer is selected
  void _updateModels() {
    if (_selectedCategoryId == null || _selectedManufacturer == null) {
      _modelsList = [];
      _selectedModel = null;
      return;
    }

    // Filter devices by selected category and manufacturer
    _modelsList =
        _allDevices.where((device) {
          if (device['category_id'] == null || device['manufacturer'] == null) {
            return false;
          }

          // Handle string or int type for category_id
          int deviceCategoryId;
          if (device['category_id'] is int) {
            deviceCategoryId = device['category_id'];
          } else {
            deviceCategoryId =
                int.tryParse(device['category_id'].toString()) ?? -1;
          }

          String manufacturer = device['manufacturer']?.toString() ?? '';

          return deviceCategoryId == _selectedCategoryId &&
              manufacturer == _selectedManufacturer;
        }).toList();

    setState(() {
      _selectedModel = null;
    });
  }

  // Update selected model
  void _updateSelectedModel(String modelName) {
    if (_modelsList.isEmpty) return;

    _selectedModel = _modelsList.firstWhere(
      (model) => model['model'] == modelName,
      orElse: () => _modelsList.first,
    );

    setState(() {});
  }

  Future<void> _addDeviceToUser() async {
    if (_selectedCategoryId == null ||
        _selectedManufacturer == null ||
        _selectedModel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Please select all required fields',
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    // Set loading state to prevent multiple submissions
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;

      // Get today's date in YYYY-MM-DD format
      String today = DateTime.now().toIso8601String().split('T')[0];

      // Check if this device already exists as a preset
      QuerySnapshot existingPresetQuery =
          await FirebaseFirestore.instance
              .collection('devices')
              .where('manufacturer', isEqualTo: _selectedModel!['manufacturer'])
              .where('model', isEqualTo: _selectedModel!['model'])
              .where('is_user_added', isEqualTo: 0)
              .limit(1)
              .get();

      // First dismiss the dialog to prevent UI issues
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (existingPresetQuery.docs.isNotEmpty) {
        // This is a preset device - update the existing preset record
        String presetDeviceId = existingPresetQuery.docs.first.id;
        await FirebaseFirestore.instance
            .collection('devices')
            .doc(presetDeviceId)
            .update({
              'is_user_added': 1,
              'user_id': userId,
              'is_preset': true, // Mark explicitly as a preset
              'daily_uptime': 0.0,
              'total_uptime': 0.0,
              'daily_consumption': 0.0,
              'last_reset': today,
              'last_active': null,
            });
        debugPrint(
          "Added preset device ${_selectedModel!['model']} to user's collection",
        );
      } else {
        // Add as a brand new device
        await FirebaseFirestore.instance.collection('devices').add({
          'category_id': _selectedCategoryId,
          'manufacturer': _selectedModel!['manufacturer'] ?? '',
          'model': _selectedModel!['model'] ?? '',
          'power_consumption':
              (_selectedModel!['power_consumption'] is num)
                  ? _selectedModel!['power_consumption'].toDouble()
                  : double.parse(
                    _selectedModel!['power_consumption'].toString(),
                  ),
          'is_user_added': 1,
          'is_preset': false, // Mark as not a preset device
          'user_id': userId,
          'daily_uptime': 0.0,
          'total_uptime': 0.0,
          'daily_consumption': 0.0,
          'last_reset': today,
          'last_active': null,
        });
        debugPrint(
          "Added new device ${_selectedModel!['model']} to user's collection",
        );
      }

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(
              'device_added'.tr(context),
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }

      // Call onSave callback to refresh data
      widget.onSave();
    } catch (e) {
      debugPrint("Error adding device: $e");

      // Make sure dialog is closed even if there's an error
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Error adding device: $e',
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Still try to refresh data even after error to ensure UI is in a consistent state
      try {
        widget.onSave();
      } catch (refreshError) {
        debugPrint("Error refreshing after device add: $refreshError");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDarkTheme = themeProvider.isDarkTheme;

    return Dialog(
      backgroundColor: isDarkTheme ? Colors.grey[900] : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: const EdgeInsets.all(20.0),
        child:
            _isLoading
                ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.blueAccent),
                      const SizedBox(height: 16),
                      Text(
                        'Loading devices...',
                        style: GoogleFonts.poppins(
                          color: isDarkTheme ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                )
                : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Device',
                        style: GoogleFonts.poppins(
                          color: isDarkTheme ? Colors.white : Colors.black,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Category Dropdown
                      Text(
                        'Category',
                        style: GoogleFonts.poppins(
                          color: isDarkTheme ? Colors.white70 : Colors.black54,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        decoration: BoxDecoration(
                          color:
                              isDarkTheme
                                  ? Colors.white.withAlpha(20)
                                  : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonFormField<int>(
                          value: _selectedCategoryId,
                          hint: Text(
                            "Select Category",
                            style: GoogleFonts.poppins(
                              color:
                                  isDarkTheme ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          items:
                              widget.categories.map((category) {
                                return DropdownMenuItem<int>(
                                  value: int.parse(category['id'].toString()),
                                  child: Text(
                                    category['name'].toString(),
                                    style: GoogleFonts.poppins(
                                      color:
                                          isDarkTheme
                                              ? Colors.white
                                              : Colors.black,
                                    ),
                                  ),
                                );
                              }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedCategoryId = value;
                            });
                            _updateManufacturers();
                          },
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 8,
                            ),
                          ),
                          dropdownColor:
                              isDarkTheme ? Colors.grey[800] : Colors.grey[100],
                          icon: Icon(
                            Icons.arrow_drop_down,
                            color:
                                isDarkTheme ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Divider line
                      Container(
                        height: 1,
                        color:
                            isDarkTheme
                                ? Colors.white.withAlpha(15)
                                : Colors.grey.withAlpha(30),
                      ),
                      const SizedBox(height: 24),

                      // Manufacturer Dropdown
                      Text(
                        'Manufacturer',
                        style: GoogleFonts.poppins(
                          color:
                              isDarkTheme
                                  ? _selectedCategoryId == null
                                      ? Colors.grey
                                      : Colors.white70
                                  : _selectedCategoryId == null
                                  ? Colors.grey
                                  : Colors.black54,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        decoration: BoxDecoration(
                          color:
                              isDarkTheme
                                  ? _selectedCategoryId == null
                                      ? Colors.white.withAlpha(10)
                                      : Colors.white.withAlpha(20)
                                  : _selectedCategoryId == null
                                  ? Colors.grey[200]!.withAlpha(100)
                                  : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IgnorePointer(
                          ignoring: _selectedCategoryId == null,
                          child: DropdownButtonFormField<String>(
                            value: _selectedManufacturer,
                            hint: Text(
                              "Select Manufacturer",
                              style: GoogleFonts.poppins(
                                color:
                                    isDarkTheme
                                        ? Colors.white70
                                        : Colors.black54,
                              ),
                            ),
                            items:
                                _manufacturersList.map((manufacturer) {
                                  return DropdownMenuItem<String>(
                                    value: manufacturer,
                                    child: Text(
                                      manufacturer,
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white
                                                : Colors.black,
                                      ),
                                    ),
                                  );
                                }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedManufacturer = value;
                              });
                              _updateModels();
                            },
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                            dropdownColor:
                                isDarkTheme ? Colors.grey[800] : Colors.white,
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color:
                                  _selectedCategoryId == null
                                      ? Colors.grey
                                      : isDarkTheme
                                      ? Colors.white70
                                      : Colors.black54,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Divider line
                      Container(
                        height: 1,
                        color:
                            isDarkTheme
                                ? Colors.white.withAlpha(15)
                                : Colors.grey.withAlpha(30),
                      ),
                      const SizedBox(height: 24),

                      // Model Dropdown
                      Text(
                        'Model',
                        style: GoogleFonts.poppins(
                          color:
                              isDarkTheme
                                  ? _selectedManufacturer == null
                                      ? Colors.grey
                                      : Colors.white70
                                  : _selectedManufacturer == null
                                  ? Colors.grey
                                  : Colors.black54,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        decoration: BoxDecoration(
                          color:
                              isDarkTheme
                                  ? _selectedManufacturer == null
                                      ? Colors.white.withAlpha(10)
                                      : Colors.white.withAlpha(20)
                                  : _selectedManufacturer == null
                                  ? Colors.grey[200]!.withAlpha(100)
                                  : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IgnorePointer(
                          ignoring: _selectedManufacturer == null,
                          child: DropdownButtonFormField<String>(
                            value:
                                _selectedModel != null
                                    ? _selectedModel!['model']?.toString()
                                    : null,
                            hint: Text(
                              "Select Model",
                              style: GoogleFonts.poppins(
                                color:
                                    isDarkTheme
                                        ? Colors.white70
                                        : Colors.black54,
                              ),
                            ),
                            items:
                                _modelsList.map((model) {
                                  return DropdownMenuItem<String>(
                                    value: model['model']?.toString(),
                                    child: Text(
                                      model['model']?.toString() ?? 'Unknown',
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white
                                                : Colors.black,
                                      ),
                                    ),
                                  );
                                }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                _updateSelectedModel(value);
                              }
                            },
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                            dropdownColor:
                                isDarkTheme ? Colors.grey[800] : Colors.white,
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color:
                                  _selectedManufacturer == null
                                      ? Colors.grey
                                      : isDarkTheme
                                      ? Colors.white70
                                      : Colors.black54,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Divider line
                      Container(
                        height: 1,
                        color:
                            isDarkTheme
                                ? Colors.white.withAlpha(15)
                                : Colors.grey.withAlpha(30),
                      ),
                      const SizedBox(height: 24),

                      // Power Consumption Display
                      Text(
                        'Power Consumption: ${_selectedModel != null ? (_selectedModel!['power_consumption'] ?? "N/A") : "N/A"} kW',
                        style: GoogleFonts.poppins(
                          color: isDarkTheme ? Colors.white : Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.poppins(
                                color: Colors.redAccent,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          ElevatedButton(
                            onPressed:
                                _selectedModel != null
                                    ? _addDeviceToUser
                                    : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey,
                              disabledForegroundColor: Colors.white70,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 30,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: Text(
                              'Add Device',
                              style: GoogleFonts.poppins(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
      ),
    );
  }
}

// Dialog for adding a custom device
class CustomDeviceDialog extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final VoidCallback onSave;

  const CustomDeviceDialog({
    super.key,
    required this.categories,
    required this.onSave,
  });

  @override
  State<CustomDeviceDialog> createState() => _CustomDeviceDialogState();
}

class _CustomDeviceDialogState extends State<CustomDeviceDialog> {
  final _customFormKey = GlobalKey<FormState>();
  String? _customCategory;
  String? _customManufacturer;
  String? _customModel;
  double? _customPowerConsumption;
  final _customPowerController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDarkTheme = themeProvider.isDarkTheme;

    return AlertDialog(
      backgroundColor: isDarkTheme ? Colors.grey[900] : Colors.white,
      title: Text(
        'add_custom_device'.tr(context),
        style: GoogleFonts.poppins(
          color: isDarkTheme ? Colors.white : Colors.black,
          fontWeight: FontWeight.w600,
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child:
            _isLoading
                ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.blueAccent),
                      const SizedBox(height: 16),
                      Text(
                        'Adding device...',
                        style: GoogleFonts.poppins(
                          color: isDarkTheme ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                )
                : SingleChildScrollView(
                  child: Form(
                    key: _customFormKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          value: _customCategory,
                          hint: Text(
                            'Select Category',
                            style: GoogleFonts.poppins(
                              color:
                                  isDarkTheme ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          items:
                              widget.categories.map((category) {
                                return DropdownMenuItem<String>(
                                  value: category['id'] as String,
                                  child: Text(
                                    category['name'] as String,
                                    style: GoogleFonts.poppins(
                                      color:
                                          isDarkTheme
                                              ? Colors.white
                                              : Colors.black,
                                    ),
                                  ),
                                );
                              }).toList(),
                          onChanged:
                              (value) =>
                                  setState(() => _customCategory = value),
                          validator:
                              (value) =>
                                  value == null
                                      ? 'Please select a category'
                                      : null,
                          decoration: InputDecoration(
                            labelText: 'Category',
                            labelStyle: GoogleFonts.poppins(
                              color:
                                  isDarkTheme ? Colors.white70 : Colors.black54,
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color:
                                    isDarkTheme
                                        ? Colors.white70
                                        : Colors.black38,
                              ),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.blueAccent),
                            ),
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 8,
                            ),
                          ),
                          dropdownColor:
                              isDarkTheme ? Colors.grey[800] : Colors.grey[100],
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Manufacturer',
                            labelStyle: GoogleFonts.poppins(
                              color:
                                  isDarkTheme ? Colors.white70 : Colors.black54,
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color:
                                    isDarkTheme
                                        ? Colors.white70
                                        : Colors.black38,
                              ),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.blueAccent),
                            ),
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 8,
                            ),
                          ),
                          validator:
                              (value) =>
                                  value == null || value.isEmpty
                                      ? 'Enter manufacturer'
                                      : null,
                          onChanged: (value) => _customManufacturer = value,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Model',
                            labelStyle: GoogleFonts.poppins(
                              color:
                                  isDarkTheme ? Colors.white70 : Colors.black54,
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color:
                                    isDarkTheme
                                        ? Colors.white70
                                        : Colors.black38,
                              ),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.blueAccent),
                            ),
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 8,
                            ),
                          ),
                          validator:
                              (value) =>
                                  value == null || value.isEmpty
                                      ? 'Enter model'
                                      : null,
                          onChanged: (value) => _customModel = value,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _customPowerController,
                          keyboardType: TextInputType.number,
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Power Consumption (kW)',
                            labelStyle: GoogleFonts.poppins(
                              color:
                                  isDarkTheme ? Colors.white70 : Colors.black54,
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color:
                                    isDarkTheme
                                        ? Colors.white70
                                        : Colors.black38,
                              ),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.blueAccent),
                            ),
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 8,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Enter power consumption';
                            }
                            final power = double.tryParse(value);
                            if (power == null || power <= 0) {
                              return 'Power must be a positive number';
                            }
                            return null;
                          },
                          onChanged: (value) {
                            _customPowerConsumption =
                                double.tryParse(value) ?? 0.0;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'cancel'.tr(context),
            style: GoogleFonts.poppins(
              color: isDarkTheme ? Colors.white70 : Colors.black54,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _saveCustomDevice,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
          child: Text(
            'add_custom_device'.tr(context),
            style: GoogleFonts.poppins(color: Colors.white),
          ),
        ),
      ],
    );
  }

  Future<void> _saveCustomDevice() async {
    if (_customFormKey.currentState!.validate()) {
      // Set loading state to prevent multiple submissions
      setState(() {
        _isLoading = true;
      });

      try {
        final userId = FirebaseAuth.instance.currentUser!.uid;
        // Get today's date in YYYY-MM-DD format
        String today = DateTime.now().toIso8601String().split('T')[0];

        // First dismiss the dialog to prevent UI issues
        if (mounted) {
          Navigator.of(context).pop();
        }

        await FirebaseFirestore.instance.collection('devices').add({
          'category_id': _customCategory,
          'manufacturer': _customManufacturer,
          'model': _customModel,
          'power_consumption': _customPowerConsumption,
          'is_user_added': 1,
          'user_id': userId,
          'daily_uptime': 0.0,
          'total_uptime': 0.0,
          'daily_consumption': 0.0,
          'last_reset': today,
          'last_active': null,
        });

        // Call onSave callback
        widget.onSave();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green,
              content: Text(
                'custom_device_added'.tr(context),
                style: const TextStyle(color: Colors.white),
              ),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        debugPrint("Error saving custom device: $e");

        // Make sure dialog is closed even if there's an error
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red,
              content: Text(
                "${'error_save_custom'.tr(context)}: $e",
                style: const TextStyle(color: Colors.white),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }

        // Still try to refresh data even after error to ensure UI is in a consistent state
        try {
          widget.onSave();
        } catch (refreshError) {
          debugPrint("Error refreshing after custom device add: $refreshError");
        }
      }
    }
  }

  @override
  void dispose() {
    _customPowerController.dispose();
    super.dispose();
  }
}

class EditDeviceDialog extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final Map<String, dynamic> device;
  final VoidCallback onSave;

  const EditDeviceDialog({
    super.key,
    required this.categories,
    required this.device,
    required this.onSave,
  });

  @override
  State<EditDeviceDialog> createState() => _EditDeviceDialogState();
}

class _EditDeviceDialogState extends State<EditDeviceDialog> {
  late TextEditingController _manufacturerController;
  late TextEditingController _modelController;
  late TextEditingController _powerConsumptionController;
  int? _selectedCategoryId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _manufacturerController = TextEditingController(
      text: widget.device['manufacturer'],
    );
    _modelController = TextEditingController(text: widget.device['model']);
    _powerConsumptionController = TextEditingController(
      text: widget.device['power_consumption'].toString(),
    );

    if (widget.device['category_id'] != null) {
      if (widget.device['category_id'] is int) {
        _selectedCategoryId = widget.device['category_id'];
      } else {
        _selectedCategoryId = int.tryParse(
          widget.device['category_id'].toString(),
        );
      }
    }
  }

  @override
  void dispose() {
    _manufacturerController.dispose();
    _modelController.dispose();
    _powerConsumptionController.dispose();
    super.dispose();
  }

  Future<void> _updateDevice() async {
    if (_manufacturerController.text.isEmpty ||
        _modelController.text.isEmpty ||
        _powerConsumptionController.text.isEmpty ||
        _selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'all_fields_required'.tr(context),
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;

      // First dismiss dialog to prevent UI issues
      if (mounted) {
        Navigator.of(context).pop();
      }

      await DatabaseHelper.instance.updateUserDevice(
        deviceId: widget.device['id'],
        userId: userId,
        categoryId: _selectedCategoryId!,
        manufacturer: _manufacturerController.text,
        model: _modelController.text,
        powerConsumption: double.parse(_powerConsumptionController.text),
      );

      // Call onSave to refresh UI
      widget.onSave();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(
              'device_updated'.tr(context),
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating device: $e');

      // Make sure dialog is closed even if there's an error
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Error updating device: $e',
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Still try to refresh data even after error to maintain UI consistency
      try {
        widget.onSave();
      } catch (refreshError) {
        debugPrint("Error refreshing after device update: $refreshError");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDarkTheme = themeProvider.isDarkTheme;

    return AlertDialog(
      backgroundColor: isDarkTheme ? Colors.grey[900] : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      contentPadding: EdgeInsets.fromLTRB(24, 20, 24, 0),
      title: Text(
        'edit_device'.tr(context),
        style: GoogleFonts.poppins(
          color: isDarkTheme ? Colors.white : Colors.black,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: SingleChildScrollView(
          child: Form(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: _selectedCategoryId,
                  hint: Text(
                    'Select Category',
                    style: GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  items:
                      widget.categories.map((category) {
                        return DropdownMenuItem<int>(
                          value: int.parse(category['id'] as String),
                          child: Text(
                            category['name'] as String,
                            style: GoogleFonts.poppins(
                              color: isDarkTheme ? Colors.white : Colors.black,
                            ),
                          ),
                        );
                      }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategoryId = value;
                    });
                  },
                  validator:
                      (value) =>
                          value == null ? 'Please select a category' : null,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    labelStyle: GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.white70 : Colors.black54,
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: isDarkTheme ? Colors.white70 : Colors.black38,
                      ),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blueAccent),
                    ),
                    floatingLabelBehavior: FloatingLabelBehavior.auto,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 8,
                    ),
                  ),
                  dropdownColor:
                      isDarkTheme ? Colors.grey[800] : Colors.grey[100],
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _manufacturerController,
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Manufacturer',
                    labelStyle: GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.white70 : Colors.black54,
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: isDarkTheme ? Colors.white70 : Colors.black38,
                      ),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blueAccent),
                    ),
                    floatingLabelBehavior: FloatingLabelBehavior.auto,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 8,
                    ),
                  ),
                  validator:
                      (value) =>
                          value == null || value.isEmpty
                              ? 'Please enter manufacturer'
                              : null,
                  onChanged: (value) => _manufacturerController.text = value,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _modelController,
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Model',
                    labelStyle: GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.white70 : Colors.black54,
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: isDarkTheme ? Colors.white70 : Colors.black38,
                      ),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blueAccent),
                    ),
                    floatingLabelBehavior: FloatingLabelBehavior.auto,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 8,
                    ),
                  ),
                  validator:
                      (value) =>
                          value == null || value.isEmpty
                              ? 'Please enter model'
                              : null,
                  onChanged: (value) => _modelController.text = value,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _powerConsumptionController,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Power Consumption (kW)',
                    labelStyle: GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.white70 : Colors.black54,
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: isDarkTheme ? Colors.white70 : Colors.black38,
                      ),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blueAccent),
                    ),
                    floatingLabelBehavior: FloatingLabelBehavior.auto,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 8,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter power consumption';
                    }
                    final power = double.tryParse(value);
                    if (power == null || power <= 0) {
                      return 'Power must be a positive number';
                    }
                    return null;
                  },
                  onChanged: (value) {
                    _powerConsumptionController.text = value;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'cancel'.tr(context),
            style: GoogleFonts.poppins(
              color: isDarkTheme ? Colors.white70 : Colors.black54,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _updateDevice,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
          child:
              _isLoading
                  ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                  : Text(
                    'update_device_button'.tr(context),
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
        ),
      ],
    );
  }
}
