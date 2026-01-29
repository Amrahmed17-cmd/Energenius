import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:energenius/database/database_helper.dart';
import 'package:energenius/screens/login_screen.dart';
import 'dart:developer';
import '../theme_provider.dart';
import '../utils/conversion_utilities.dart';
import '../localization/app_localizations.dart';
import 'package:fl_chart/fl_chart.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;

  User? user;
  String firstName = "User";
  String country = "Unknown";
  double totalDailyConsumption = 0.0;
  bool isLoading = true;
  String _currency = 'EGP';
  String _energyUnit = 'kWh';
  double _estimatedBill = 0.0;
  final double _pricePerUnit = 1.2; // Example price per kWh

  // Add futures for caching data
  Future<List<Map<String, dynamic>>>? dailyDataFuture;
  Future<List<Map<String, dynamic>>>? weeklyDataFuture;
  Future<List<Map<String, dynamic>>>? monthlyDataFuture;

  @override
  void initState() {
    super.initState();

    // Setup animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    // Initialize futures for data loading
    dailyDataFuture = _getDailyConsumptionData();
    weeklyDataFuture = _getWeeklyConsumptionData();
    monthlyDataFuture = _getMonthlyConsumptionData();

    // Load user data and settings
    _loadUserData();
    _loadSettings();
    _calculateEstimatedBill();

    // Don't call _refreshAllData() directly from initState, use Future.delayed to avoid setState during build
    Future.delayed(Duration.zero, () {
      if (mounted) {
        _refreshAllData();
      }
    });

    _animationController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Rebuild the UI when locale changes
    AppLocalizations.of(context);
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      user = _auth.currentUser;
      if (user == null) {
        log("No user logged in");
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
        return;
      }

      // Get user data from Firestore
      DocumentSnapshot userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user!.uid)
              .get();

      log("Fetching Firestore user data for UID: ${user!.uid}");

      if (userDoc.exists && userDoc.data() != null) {
        Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;

        // Debug the actual data received from Firestore
        log("User data from Firestore: $data");

        // Check if first_name and country fields exist and are not null or empty
        if (data.containsKey('first_name') &&
            data['first_name'] != null &&
            data['first_name'].toString().isNotEmpty) {
          setState(() {
            firstName = data['first_name'].toString();
          });
          log("First name loaded: $firstName");
        } else if (data.containsKey('firstName') &&
            data['firstName'] != null &&
            data['firstName'].toString().isNotEmpty) {
          // Try alternative field name
          setState(() {
            firstName = data['firstName'].toString();
          });
          log("First name loaded (from alternative field): $firstName");
        } else {
          setState(() {
            firstName = "User";
          });
          log("First name not found in user data, using default value");
        }

        if (data.containsKey('country') &&
            data['country'] != null &&
            data['country'].toString().isNotEmpty) {
          setState(() {
            country = data['country'].toString();
          });
          log("Country loaded: $country");
        } else {
          setState(() {
            country = "Unknown";
          });
          log("Country not found in user data, using default value");
        }

        log("User data loaded: firstName=$firstName, country=$country");
      } else {
        log("User document does not exist in Firestore for UID: ${user!.uid}");
        // Create a basic user document if one doesn't exist
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .set({
              'first_name': "User",
              'country': "Unknown",
              'uid': user!.uid,
              'email': user!.email,
              'created_at': FieldValue.serverTimestamp(),
            });
        log("Created user document for UID: ${user!.uid}");
      }

      // Calculate estimated bill based on real-time consumption data
      _calculateEstimatedBill();
    } catch (e) {
      log("Error loading user data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Error loading data: $e",
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _currency = prefs.getString('currency') ?? 'EGP';
        _energyUnit = prefs.getString('energyUnit') ?? 'kWh';
        _calculateEstimatedBill();
      });
    }
  }

  Future<void> _calculateEstimatedBill() async {
    try {
      if (_auth.currentUser == null) return;
      final String userId = _auth.currentUser!.uid;

      // Get consumption data for this month
      final DateTime today = DateTime.now();
      final DateTime startOfMonth = DateTime(today.year, today.month, 1);

      List<Map<String, dynamic>> monthlyData = await DatabaseHelper.instance
          .getMonthlyConsumption(userId, startOfMonth, today);

      // Calculate total consumption for the month
      double monthlyConsumption = 0.0;
      for (var day in monthlyData) {
        monthlyConsumption += (day['total_consumption'] ?? 0.0).toDouble();
      }

      // Calculate average daily consumption
      int daysInMonth = DateTime(today.year, today.month + 1, 0).day;
      int daysPassed = today.day;
      double avgDailyConsumption =
          daysPassed > 0 ? monthlyConsumption / daysPassed : 0.0;

      // Project remaining days
      double projectedMonthlyConsumption =
          monthlyConsumption +
          (avgDailyConsumption * (daysInMonth - daysPassed));

      // Calculate bill
      setState(() {
        _estimatedBill = projectedMonthlyConsumption * _pricePerUnit;
      });

      log(
        "Calculated estimated bill: $_estimatedBill $_currency based on projected monthly consumption: $projectedMonthlyConsumption kWh",
      );
    } catch (e) {
      log("Error calculating estimated bill: $e");
      setState(() {
        _estimatedBill = 0.0;
      });
    }
  }

  // Format the bill amount using the utility class
  String _getFormattedBill() {
    // Convert the bill amount from EGP to the selected currency
    double convertedAmount = _estimatedBill;
    if (_currency != 'EGP') {
      convertedAmount = ConversionUtilities.convertCurrency(
        _estimatedBill,
        'EGP',
        _currency,
      );
    }

    // Format with the appropriate currency symbol
    return "${convertedAmount.toStringAsFixed(2)} $_currency";
  }

  // Convert an energy value to the selected unit
  String _formatEnergyValue(double valueInKWh) {
    try {
      if (valueInKWh.isNaN || valueInKWh.isInfinite) {
        return "0.00 $_energyUnit";
      }

      double convertedValue = ConversionUtilities.convertEnergy(
        valueInKWh,
        'kWh',
        _energyUnit,
      );
      return "${convertedValue.toStringAsFixed(2)} $_energyUnit";
    } catch (e) {
      log("Error formatting energy value: $e");
      return "${valueInKWh.toStringAsFixed(2)} kWh";
    }
  }

  Future<void> _saveCurrency(String newCurrency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currency', newCurrency);
    setState(() {
      _currency = newCurrency;
      _calculateEstimatedBill(); // Recalculate with new currency
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Currency updated to $_currency!",
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  Future<void> _saveEnergyUnit(String newEnergyUnit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('energyUnit', newEnergyUnit);
    setState(() {
      _energyUnit = newEnergyUnit;
      _calculateEstimatedBill(); // Recalculate with new energy unit
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Energy unit updated to $_energyUnit!",
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  void _logout() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  void _showEnergyBillDetails() {
    try {
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      final bool isDarkTheme = themeProvider.isDarkTheme;

      // Pre-fetch data to avoid multiple identical future calls
      final Future<List<Map<String, dynamic>>> monthlyDataFuture =
          _getMonthlyConsumptionData();
      final Future<List<Map<String, dynamic>>> weeklyDataFuture =
          _getWeeklyConsumptionData();

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder:
            (context) => Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: BoxDecoration(
                color: isDarkTheme ? const Color(0xFF1A1F38) : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(25),
                  topRight: Radius.circular(25),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(51),
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Modal title with close button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "energy_bill_details".tr(context),
                            style: GoogleFonts.poppins(
                              color: isDarkTheme ? Colors.white : Colors.black,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              color:
                                  isDarkTheme ? Colors.white70 : Colors.black54,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Bill Summary Card - Restored from previous design
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors:
                                isDarkTheme
                                    ? [Colors.blue[800]!, Colors.blue[900]!]
                                    : [Colors.blue[400]!, Colors.blue[600]!],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withAlpha(77),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "estimated_monthly_bill".tr(context),
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(51),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    "Pending",
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _getFormattedBill(),
                              style: GoogleFonts.poppins(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            FutureBuilder<List<Map<String, dynamic>>>(
                              future: monthlyDataFuture,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const SizedBox(
                                    height: 14,
                                    child: Center(
                                      child: LinearProgressIndicator(
                                        backgroundColor: Colors.white24,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  );
                                }

                                double monthlyConsumption = 0.0;

                                if (snapshot.hasData) {
                                  // Sum all daily consumption for the month
                                  for (var day in snapshot.data!) {
                                    monthlyConsumption +=
                                        (day['total_consumption'] ?? 0.0)
                                            .toDouble();
                                  }
                                }

                                return Text(
                                  "based_on_monthly_usage".trParams(context, [
                                    _formatEnergyValue(monthlyConsumption),
                                  ]),
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Colors.white.withAlpha(230),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),

                      Text(
                        "monthly_consumption".tr(context),
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDarkTheme ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 15),
                      SizedBox(
                        height: 200,
                        child: _buildSimpleLineChart(isDarkTheme),
                      ),
                      const SizedBox(height: 30),

                      // Energy consumption details
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color:
                              isDarkTheme
                                  ? Colors.white.withAlpha(26)
                                  : Colors.grey[100],
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "consumption_details".tr(context),
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                color:
                                    isDarkTheme ? Colors.white : Colors.black,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 15),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "daily".tr(context),
                                  style: GoogleFonts.poppins(
                                    color:
                                        isDarkTheme
                                            ? Colors.white70
                                            : Colors.black87,
                                  ),
                                ),
                                Text(
                                  _formatEnergyValue(totalDailyConsumption),
                                  style: GoogleFonts.poppins(
                                    color:
                                        isDarkTheme
                                            ? Colors.white
                                            : Colors.black,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 25),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "weekly".tr(context),
                                  style: GoogleFonts.poppins(
                                    color:
                                        isDarkTheme
                                            ? Colors.white70
                                            : Colors.black87,
                                  ),
                                ),
                                FutureBuilder<List<Map<String, dynamic>>>(
                                  future: weeklyDataFuture,
                                  builder: (context, snapshot) {
                                    double weeklyConsumption = 0.0;

                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const SizedBox(
                                        height: 20,
                                        width: 30,
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      );
                                    }

                                    if (snapshot.hasData) {
                                      if (snapshot.data!.isNotEmpty) {
                                        log(
                                          "Weekly data: ${snapshot.data!.length} items",
                                        );

                                        // Sum weekly consumption correctly
                                        for (var week in snapshot.data!) {
                                          double value =
                                              (week['total_consumption'] ?? 0.0)
                                                  .toDouble();
                                          weeklyConsumption += value;
                                          log(
                                            "Week: ${week['week'] ?? 'unknown'}, Value: $value",
                                          );
                                        }
                                      }
                                    }

                                    return Text(
                                      _formatEnergyValue(weeklyConsumption),
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white
                                                : Colors.black,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const Divider(height: 25),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "monthly".tr(context),
                                  style: GoogleFonts.poppins(
                                    color:
                                        isDarkTheme
                                            ? Colors.white70
                                            : Colors.black87,
                                  ),
                                ),
                                FutureBuilder<List<Map<String, dynamic>>>(
                                  future: monthlyDataFuture,
                                  builder: (context, snapshot) {
                                    double monthlyConsumption = 0.0;

                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const SizedBox(
                                        height: 20,
                                        width: 30,
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      );
                                    }

                                    if (snapshot.hasData) {
                                      if (snapshot.data!.isNotEmpty) {
                                        log(
                                          "Monthly data: ${snapshot.data!.length} items",
                                        );

                                        // Sum monthly consumption correctly
                                        for (var month in snapshot.data!) {
                                          double value =
                                              (month['total_consumption'] ??
                                                      0.0)
                                                  .toDouble();
                                          monthlyConsumption += value;
                                          log(
                                            "Month: ${month['month'] ?? 'unknown'}, Value: $value",
                                          );
                                        }
                                      }
                                    }

                                    return Text(
                                      _formatEnergyValue(monthlyConsumption),
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white
                                                : Colors.black,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const Divider(height: 25),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "yearly".tr(context),
                                  style: GoogleFonts.poppins(
                                    color:
                                        isDarkTheme
                                            ? Colors.white70
                                            : Colors.black87,
                                  ),
                                ),
                                FutureBuilder<List<Map<String, dynamic>>>(
                                  future: monthlyDataFuture,
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const SizedBox(
                                        height: 20,
                                        width: 30,
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      );
                                    }

                                    double monthlyAvg = 0.0;

                                    if (snapshot.hasData &&
                                        snapshot.data!.isNotEmpty) {
                                      double totalMonthly = 0.0;
                                      for (var day in snapshot.data!) {
                                        totalMonthly +=
                                            (day['total_consumption'] ?? 0.0)
                                                .toDouble();
                                      }
                                      // Estimate yearly from monthly average
                                      monthlyAvg =
                                          snapshot.data!.isNotEmpty
                                              ? totalMonthly /
                                                  snapshot.data!.length
                                              : 0.0;
                                    }

                                    double yearlyEstimate = monthlyAvg * 12;

                                    return Text(
                                      _formatEnergyValue(yearlyEstimate),
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white
                                                : Colors.black,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),

                      // Current settings
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color:
                              isDarkTheme
                                  ? Colors.white.withAlpha(26)
                                  : Colors.grey[100],
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "settings".tr(context),
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                color:
                                    isDarkTheme ? Colors.white : Colors.black,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 15),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "energy_unit".tr(context),
                                  style: GoogleFonts.poppins(
                                    color:
                                        isDarkTheme
                                            ? Colors.white70
                                            : Colors.black87,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      _energyUnit,
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white
                                                : Colors.black,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.edit,
                                        size: 16,
                                        color: Colors.blueAccent,
                                      ),
                                      onPressed: () {
                                        Navigator.pop(context);
                                        showDialog(
                                          context: context,
                                          builder:
                                              (context) => AlertDialog(
                                                backgroundColor:
                                                    isDarkTheme
                                                        ? const Color(
                                                          0xFF1A1F38,
                                                        )
                                                        : Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(15),
                                                ),
                                                title: Text(
                                                  "select_energy_unit".tr(
                                                    context,
                                                  ),
                                                  style: GoogleFonts.poppins(
                                                    color:
                                                        isDarkTheme
                                                            ? Colors.white
                                                            : Colors.black,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                content: DropdownButton<String>(
                                                  value: _energyUnit,
                                                  dropdownColor:
                                                      isDarkTheme
                                                          ? const Color(
                                                            0xFF1A1F38,
                                                          )
                                                          : Colors.white,
                                                  style: GoogleFonts.poppins(
                                                    color:
                                                        isDarkTheme
                                                            ? Colors.white
                                                            : Colors.black,
                                                  ),
                                                  items:
                                                      ConversionUtilities
                                                          .energyConversions
                                                          .keys
                                                          .map<
                                                            DropdownMenuItem<
                                                              String
                                                            >
                                                          >((String value) {
                                                            return DropdownMenuItem<
                                                              String
                                                            >(
                                                              value: value,
                                                              child: Text(
                                                                value,
                                                              ),
                                                            );
                                                          })
                                                          .toList(),
                                                  onChanged: (
                                                    String? newValue,
                                                  ) {
                                                    if (newValue != null) {
                                                      _saveEnergyUnit(newValue);
                                                      Navigator.pop(context);
                                                      // Reopen the bill details after changing unit
                                                      _showEnergyBillDetails();
                                                    }
                                                  },
                                                ),
                                              ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(height: 25),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "currency".tr(context),
                                  style: GoogleFonts.poppins(
                                    color:
                                        isDarkTheme
                                            ? Colors.white70
                                            : Colors.black87,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      _currency,
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white
                                                : Colors.black,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.edit,
                                        size: 16,
                                        color: Colors.blueAccent,
                                      ),
                                      onPressed: () {
                                        Navigator.pop(context);
                                        showDialog(
                                          context: context,
                                          builder:
                                              (context) => AlertDialog(
                                                backgroundColor:
                                                    isDarkTheme
                                                        ? const Color(
                                                          0xFF1A1F38,
                                                        )
                                                        : Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(15),
                                                ),
                                                title: Text(
                                                  "select_currency".tr(context),
                                                  style: GoogleFonts.poppins(
                                                    color:
                                                        isDarkTheme
                                                            ? Colors.white
                                                            : Colors.black,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                content: DropdownButton<String>(
                                                  value: _currency,
                                                  dropdownColor:
                                                      isDarkTheme
                                                          ? const Color(
                                                            0xFF1A1F38,
                                                          )
                                                          : Colors.white,
                                                  style: GoogleFonts.poppins(
                                                    color:
                                                        isDarkTheme
                                                            ? Colors.white
                                                            : Colors.black,
                                                  ),
                                                  items:
                                                      ConversionUtilities
                                                          .currencyRates
                                                          .keys
                                                          .map<
                                                            DropdownMenuItem<
                                                              String
                                                            >
                                                          >((String value) {
                                                            return DropdownMenuItem<
                                                              String
                                                            >(
                                                              value: value,
                                                              child: Text(
                                                                "$value (${ConversionUtilities.currencySymbols[value] ?? value})",
                                                              ),
                                                            );
                                                          })
                                                          .toList(),
                                                  onChanged: (
                                                    String? newValue,
                                                  ) {
                                                    if (newValue != null) {
                                                      _saveCurrency(newValue);
                                                      Navigator.pop(context);
                                                      // Reopen the bill details after changing currency
                                                      _showEnergyBillDetails();
                                                    }
                                                  },
                                                ),
                                              ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),

                      // Coming Soon Notice
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:
                              isDarkTheme
                                  ? Colors.grey[800]!.withAlpha(77)
                                  : Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color:
                                isDarkTheme
                                    ? Colors.blue[700]!
                                    : Colors.blue[300]!,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color:
                                  isDarkTheme
                                      ? Colors.blue[300]
                                      : Colors.blue[700],
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Bill payment feature coming soon! Monitor your energy usage to reduce costs.",
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color:
                                      isDarkTheme
                                          ? Colors.white
                                          : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Add bottom padding
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
      );
    } catch (e) {
      log("Error showing energy bill details: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not display energy details. Please try again."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildSimpleLineChart(bool isDarkTheme) {
    try {
      // Handle case where consumption is zero or very small
      final double effectiveConsumption =
          totalDailyConsumption <= 0.1 ? 1.0 : totalDailyConsumption;

      // Sample data for demonstration
      final List<FlSpot> spots = [
        FlSpot(0, effectiveConsumption * 0.85),
        FlSpot(1, effectiveConsumption * 0.95),
        FlSpot(2, effectiveConsumption * 1.1),
        FlSpot(3, effectiveConsumption * 0.9),
        FlSpot(4, effectiveConsumption * 1.05),
        FlSpot(5, effectiveConsumption * 1.1),
        FlSpot(6, effectiveConsumption),
      ];

      return LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval:
                effectiveConsumption / 4 > 0 ? effectiveConsumption / 4 : 0.25,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: isDarkTheme ? Colors.grey[800]! : Colors.grey[300]!,
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  const days = [
                    'Mon',
                    'Tue',
                    'Wed',
                    'Thu',
                    'Fri',
                    'Sat',
                    'Sun',
                  ];
                  final int index = value.toInt();
                  if (index >= 0 && index < days.length) {
                    return Text(
                      days[index],
                      style: GoogleFonts.poppins(
                        color:
                            isDarkTheme ? Colors.grey[400] : Colors.grey[700],
                        fontSize: 12,
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  // Convert value to the selected energy unit for display
                  double convertedValue = 0.0;
                  try {
                    convertedValue = ConversionUtilities.convertEnergy(
                      value,
                      'kWh',
                      _energyUnit,
                    );
                  } catch (e) {
                    convertedValue = value;
                    log("Error converting energy value: $e");
                  }
                  return Text(
                    convertedValue.toStringAsFixed(1),
                    style: GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.grey[400] : Colors.grey[700],
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: 6,
          minY: 0,
          maxY: effectiveConsumption * 1.5,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: isDarkTheme ? Colors.blue[400] : Colors.blue[600],
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color:
                    isDarkTheme
                        ? Colors.blue[400]!.withAlpha(51)
                        : Colors.blue[200]!.withAlpha(77),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      log("Error building line chart: $e");
      // Return a fallback empty container if chart fails to build
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart,
              color: isDarkTheme ? Colors.grey[400] : Colors.grey[600],
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              "No consumption data to display",
              style: GoogleFonts.poppins(
                color: isDarkTheme ? Colors.grey[400] : Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDarkTheme = themeProvider.isDarkTheme;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        height: screenHeight,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors:
                isDarkTheme
                    ? [Colors.blueAccent.withAlpha(51), const Color(0xFF0D1117)]
                    : [Colors.white, Colors.grey[200]!],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child:
                isLoading
                    ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.blueAccent,
                      ),
                    )
                    : FadeTransition(
                      opacity: _fadeInAnimation,
                      child: RefreshIndicator(
                        onRefresh: _refreshAllData,
                        color: Colors.blueAccent,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight:
                                  screenHeight -
                                  MediaQuery.of(context).padding.top -
                                  MediaQuery.of(context).padding.bottom -
                                  32,
                              minWidth: screenWidth,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _getWelcomeText(),
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white
                                                : Colors.black,
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.logout,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: _logout,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      size: 16,
                                      color:
                                          isDarkTheme
                                              ? Colors.blue[300]
                                              : Colors.blue,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      country,
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white70
                                                : Colors.black87,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 30),
                                // Energy Overview Card
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color:
                                        isDarkTheme
                                            ? Colors.white.withAlpha(19)
                                            : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withAlpha(26),
                                        blurRadius: 15,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color:
                                                  isDarkTheme
                                                      ? Colors.blue.withAlpha(
                                                        51,
                                                      )
                                                      : Colors.blue.withAlpha(
                                                        26,
                                                      ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              Icons.electric_bolt,
                                              color: Colors.blue[600],
                                              size: 24,
                                            ),
                                          ),
                                          const SizedBox(width: 15),
                                          Text(
                                            "energy_overview".tr(context),
                                            style: GoogleFonts.poppins(
                                              color:
                                                  isDarkTheme
                                                      ? Colors.white
                                                      : Colors.black,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      _buildConsumptionInfo(isDarkTheme),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 30),
                                Text(
                                  "quick_actions".tr(context),
                                  style: GoogleFonts.poppins(
                                    color:
                                        isDarkTheme
                                            ? Colors.white
                                            : Colors.black,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 15),
                                GridView.count(
                                  crossAxisCount: 2,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  crossAxisSpacing: 15,
                                  mainAxisSpacing: 15,
                                  childAspectRatio: 1.5,
                                  children: [
                                    _buildActionCard(
                                      title: "energy_bill".tr(context),
                                      icon: Icons.receipt_long,
                                      color: Colors.deepPurple,
                                      isDarkTheme: isDarkTheme,
                                      onTap: _showEnergyBillDetails,
                                    ),
                                    _buildActionCard(
                                      title: "set_currency".tr(context),
                                      icon: Icons.attach_money,
                                      color: Colors.green,
                                      isDarkTheme: isDarkTheme,
                                      onTap: () {
                                        showDialog(
                                          context: context,
                                          builder:
                                              (context) => AlertDialog(
                                                backgroundColor:
                                                    isDarkTheme
                                                        ? const Color(
                                                          0xFF1A1F38,
                                                        )
                                                        : Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(15),
                                                ),
                                                title: Text(
                                                  "select_currency".tr(context),
                                                  style: GoogleFonts.poppins(
                                                    color:
                                                        isDarkTheme
                                                            ? Colors.white
                                                            : Colors.black,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                content: DropdownButton<String>(
                                                  value: _currency,
                                                  dropdownColor:
                                                      isDarkTheme
                                                          ? const Color(
                                                            0xFF1A1F38,
                                                          )
                                                          : Colors.white,
                                                  style: GoogleFonts.poppins(
                                                    color:
                                                        isDarkTheme
                                                            ? Colors.white
                                                            : Colors.black,
                                                  ),
                                                  items:
                                                      ConversionUtilities
                                                          .currencyRates
                                                          .keys
                                                          .map<
                                                            DropdownMenuItem<
                                                              String
                                                            >
                                                          >((String value) {
                                                            return DropdownMenuItem<
                                                              String
                                                            >(
                                                              value: value,
                                                              child: Text(
                                                                "$value (${ConversionUtilities.currencySymbols[value] ?? value})",
                                                              ),
                                                            );
                                                          })
                                                          .toList(),
                                                  onChanged: (
                                                    String? newValue,
                                                  ) {
                                                    if (newValue != null) {
                                                      _saveCurrency(newValue);
                                                      Navigator.pop(context);
                                                    }
                                                  },
                                                ),
                                              ),
                                        );
                                      },
                                    ),
                                    _buildActionCard(
                                      title: "energy_tips".tr(context),
                                      icon: Icons.lightbulb_outlined,
                                      color: Colors.orange,
                                      isDarkTheme: isDarkTheme,
                                      onTap: () {
                                        // Will be implemented later
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              "energy_tips_coming_soon".tr(
                                                context,
                                              ),
                                              style: GoogleFonts.poppins(
                                                color: Colors.white,
                                              ),
                                            ),
                                            backgroundColor: Colors.blue[800],
                                          ),
                                        );
                                      },
                                    ),
                                    _buildActionCard(
                                      title: "set_energy_unit".tr(context),
                                      icon: Icons.power,
                                      color: Colors.purple,
                                      isDarkTheme: isDarkTheme,
                                      onTap: () {
                                        showDialog(
                                          context: context,
                                          builder:
                                              (context) => AlertDialog(
                                                backgroundColor:
                                                    isDarkTheme
                                                        ? const Color(
                                                          0xFF1A1F38,
                                                        )
                                                        : Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(15),
                                                ),
                                                title: Text(
                                                  "select_energy_unit".tr(
                                                    context,
                                                  ),
                                                  style: GoogleFonts.poppins(
                                                    color:
                                                        isDarkTheme
                                                            ? Colors.white
                                                            : Colors.black,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                content: DropdownButton<String>(
                                                  value: _energyUnit,
                                                  dropdownColor:
                                                      isDarkTheme
                                                          ? const Color(
                                                            0xFF1A1F38,
                                                          )
                                                          : Colors.white,
                                                  style: GoogleFonts.poppins(
                                                    color:
                                                        isDarkTheme
                                                            ? Colors.white
                                                            : Colors.black,
                                                  ),
                                                  items:
                                                      ConversionUtilities
                                                          .energyConversions
                                                          .keys
                                                          .map<
                                                            DropdownMenuItem<
                                                              String
                                                            >
                                                          >((String value) {
                                                            return DropdownMenuItem<
                                                              String
                                                            >(
                                                              value: value,
                                                              child: Text(
                                                                value,
                                                              ),
                                                            );
                                                          })
                                                          .toList(),
                                                  onChanged: (
                                                    String? newValue,
                                                  ) {
                                                    if (newValue != null) {
                                                      _saveEnergyUnit(newValue);
                                                      Navigator.pop(context);
                                                    }
                                                  },
                                                ),
                                              ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                  height: 80,
                                ), // Padding for navigation bar
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required bool isDarkTheme,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDarkTheme ? Colors.white.withAlpha(13) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color:
                  isDarkTheme
                      ? Colors.black.withAlpha(51)
                      : Colors.grey.withAlpha(26),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withAlpha(isDarkTheme ? 51 : 26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConsumptionInfo(bool isDarkTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main consumption card - Shows daily consumption
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors:
                  isDarkTheme
                      ? [Colors.blue[700]!, Colors.blue[900]!]
                      : [Colors.blue[400]!, Colors.blue[600]!],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withAlpha(77),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "daily_consumption".tr(context),
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 15),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: dailyDataFuture ?? _getDailyConsumptionData(),
                builder: (context, snapshot) {
                  // Handle error and loading states
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: SizedBox(
                        height: 28,
                        width: 28,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    log("Error in daily consumption data: ${snapshot.error}");
                  }

                  double dailyConsumption = 0.0;

                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    // Get today's consumption from the database
                    final DateTime today = DateTime.now();
                    final String todayStr =
                        today.toIso8601String().split('T')[0];

                    // Find today's data
                    final todayData = snapshot.data!.firstWhere(
                      (item) => item['date'] == todayStr,
                      orElse: () => {'total_consumption': 0.0},
                    );

                    dailyConsumption =
                        (todayData['total_consumption'] ?? 0.0).toDouble();

                    // Update the class variable through post-frame callback to avoid setState during build
                    if (dailyConsumption != totalDailyConsumption) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            totalDailyConsumption = dailyConsumption;
                          });
                        }
                      });
                    }
                  }

                  return Text(
                    _formatEnergyValue(dailyConsumption),
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  );
                },
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${("estimated_bill".tr(context))}: ${_getFormattedBill()}",
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.white.withAlpha(230),
                    ),
                  ),
                  GestureDetector(
                    onTap: _showEnergyBillDetails,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(51),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Text(
                            "details".tr(context),
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.white,
                            size: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Energy statistics row with weekly and monthly
        Row(
          children: [
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: weeklyDataFuture ?? _getWeeklyConsumptionData(),
                builder: (context, snapshot) {
                  double weeklyConsumption = 0.0;

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _buildStatCard(
                      title: "weekly".tr(context),
                      value: "...",
                      iconData: Icons.calendar_view_week,
                      isDarkTheme: isDarkTheme,
                      isLoading: true,
                    );
                  }

                  if (snapshot.hasData) {
                    if (snapshot.data!.isNotEmpty) {
                      log("Weekly data: ${snapshot.data!.length} items");

                      // Sum weekly consumption correctly
                      for (var week in snapshot.data!) {
                        double value =
                            (week['total_consumption'] ?? 0.0).toDouble();
                        weeklyConsumption += value;
                        log(
                          "Week: ${week['week'] ?? 'unknown'}, Value: $value",
                        );
                      }
                    }
                  }

                  return _buildStatCard(
                    title: "weekly".tr(context),
                    value: _formatEnergyValue(weeklyConsumption),
                    iconData: Icons.calendar_view_week,
                    isDarkTheme: isDarkTheme,
                  );
                },
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: monthlyDataFuture ?? _getMonthlyConsumptionData(),
                builder: (context, snapshot) {
                  double monthlyConsumption = 0.0;

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _buildStatCard(
                      title: "monthly".tr(context),
                      value: "...",
                      iconData: Icons.calendar_month,
                      isDarkTheme: isDarkTheme,
                      isLoading: true,
                    );
                  }

                  if (snapshot.hasData) {
                    if (snapshot.data!.isNotEmpty) {
                      log("Monthly data: ${snapshot.data!.length} items");

                      // Sum monthly consumption correctly
                      for (var month in snapshot.data!) {
                        double value =
                            (month['total_consumption'] ?? 0.0).toDouble();
                        monthlyConsumption += value;
                        log(
                          "Month: ${month['month'] ?? 'unknown'}, Value: $value",
                        );
                      }
                    }
                  }

                  return _buildStatCard(
                    title: "monthly".tr(context),
                    value: _formatEnergyValue(monthlyConsumption),
                    iconData: Icons.calendar_month,
                    isDarkTheme: isDarkTheme,
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Get consumption data for today
  Future<List<Map<String, dynamic>>> _getDailyConsumptionData() async {
    if (_auth.currentUser == null) return [];
    final String userId = _auth.currentUser!.uid;

    try {
      // Get today's date
      final DateTime today = DateTime.now();
      final DateTime startOfDay = DateTime(today.year, today.month, today.day);

      return await DatabaseHelper.instance.getDailyConsumption(
        userId,
        startOfDay,
        today,
      );
    } catch (e) {
      log("Error loading daily consumption: $e");
      return [];
    }
  }

  // Get consumption data for the current week
  Future<List<Map<String, dynamic>>> _getWeeklyConsumptionData() async {
    if (_auth.currentUser == null) return [];
    final String userId = _auth.currentUser!.uid;

    try {
      // Get dates for the current week (starting from Sunday)
      final DateTime today = DateTime.now();
      final DateTime startOfWeek = today.subtract(
        Duration(days: today.weekday % 7),
      );
      final DateTime startOfDay = DateTime(
        startOfWeek.year,
        startOfWeek.month,
        startOfWeek.day,
      );

      // Modify to use improved weekly consumption calculation
      return await DatabaseHelper.instance.getWeeklyConsumption(
        userId,
        startOfDay,
        today,
      );
    } catch (e) {
      log("Error loading weekly consumption: $e");
      return [];
    }
  }

  // Get consumption data for the current month
  Future<List<Map<String, dynamic>>> _getMonthlyConsumptionData() async {
    if (_auth.currentUser == null) return [];
    final String userId = _auth.currentUser!.uid;

    try {
      // Get dates for the current month
      final DateTime today = DateTime.now();
      final DateTime startOfMonth = DateTime(today.year, today.month, 1);

      // Modify to use improved monthly consumption calculation
      return await DatabaseHelper.instance.getMonthlyConsumption(
        userId,
        startOfMonth,
        today,
      );
    } catch (e) {
      log("Error loading monthly consumption: $e");
      return [];
    }
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData iconData,
    required bool isDarkTheme,
    bool isLoading = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkTheme ? Colors.white.withAlpha(26) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                iconData,
                color: isDarkTheme ? Colors.white70 : Colors.black54,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: isDarkTheme ? Colors.white70 : Colors.black54,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (isLoading)
            const SizedBox(
              height: 14,
              child: Center(
                child: LinearProgressIndicator(
                  backgroundColor: Colors.white24,
                  color: Colors.white70,
                ),
              ),
            )
          else
            Text(
              value,
              style: GoogleFonts.poppins(
                color: isDarkTheme ? Colors.white : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _getWelcomeText() {
    // Implement the logic to return the welcome text based on the user's first name
    return "${("welcome".tr(context))}, $firstName!";
  }

  // Add a method to refresh all data
  Future<void> _refreshAllData() async {
    if (_auth.currentUser == null) return;
    final String userId = _auth.currentUser!.uid;

    try {
      // Force an immediate data update from the database
      await DatabaseHelper.instance.recordDeviceUsage(userId);

      // Clear cached futures to force new data loads
      setState(() {
        dailyDataFuture = _getDailyConsumptionData();
        weeklyDataFuture = _getWeeklyConsumptionData();
        monthlyDataFuture = _getMonthlyConsumptionData();
      });
    } catch (e) {
      log("Error refreshing data: $e");
    }
  }
}
