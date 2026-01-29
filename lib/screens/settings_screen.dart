import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'dart:developer' as developer;
import '../theme_provider.dart';
import '../utils/conversion_utilities.dart';
import '../localization/language_provider.dart';
import '../localization/app_localizations.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _realTimeSync = true;
  String _energyUnit = 'kWh';
  String _currency = 'EGP';
  bool _notificationsEnabled = true;
  String _exportFrequency = 'weekly';
  String _language = 'en';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      final languageCode =
          prefs.getString(AppLocalizations.languageCode) ?? 'en';

      setState(() {
        _realTimeSync = prefs.getBool('realTimeSync') ?? true;
        _energyUnit = prefs.getString('energyUnit') ?? 'kWh';
        _currency = prefs.getString('currency') ?? 'EGP';
        _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
        _exportFrequency = prefs.getString('exportFrequency') ?? 'weekly';
        _language = languageCode;
      });

      // Ensure the LanguageProvider is in sync with the loaded language
      final languageProvider = Provider.of<LanguageProvider>(
        context,
        listen: false,
      );
      if (languageProvider.locale.languageCode != languageCode) {
        languageProvider.changeLanguage(languageCode);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${"error_loading_settings".tr(context)}: $e",
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 1),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('realTimeSync', _realTimeSync);
      await prefs.setString('energyUnit', _energyUnit);
      await prefs.setString('currency', _currency);
      await prefs.setBool('notificationsEnabled', _notificationsEnabled);
      await prefs.setString('exportFrequency', _exportFrequency);

      // Save language through AppLocalizations to ensure consistency
      await AppLocalizations.setLocale(_language);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "settings_saved".tr(context),
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.blueAccent,
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${"error_saving_settings".tr(context)}: $e",
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${"error_logging_out".tr(context)}: $e",
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  // Helper method to show authentication dialog without using context across async gaps
  Future<bool> _showAuthenticationDialog(User user) {
    // Create a completer to handle the async result
    final completer = Completer<bool>();

    // Get translations now while context is valid
    final String authRequiredText = "authentication_required".tr(context);
    final String enterPasswordText = "enter_password_to_continue".tr(context);
    final String passwordText = "password".tr(context);
    final String cancelText = "cancel".tr(context);
    final String authenticateText = "authenticate".tr(context);
    final String authFailedText = "authentication_failed".tr(context);

    // Create password controller
    final passwordController = TextEditingController();

    // Show dialog synchronously - no await here
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor:
              Theme.of(dialogContext).brightness == Brightness.dark
                  ? Colors.grey[900]
                  : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Text(
            authRequiredText,
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(enterPasswordText, style: GoogleFonts.poppins()),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: passwordText,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                completer.complete(false);
              },
              child: Text(
                cancelText,
                style: GoogleFonts.poppins(color: Colors.blueAccent),
              ),
            ),
            TextButton(
              onPressed: () {
                // Extract the password
                final password = passwordController.text;

                // Close the dialog first
                Navigator.pop(dialogContext);

                // Then do the authentication asynchronously
                _performAuthentication(user, password, authFailedText)
                    .then((success) => completer.complete(success))
                    .catchError((_) => completer.complete(false));
              },
              child: Text(
                authenticateText,
                style: GoogleFonts.poppins(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    return completer.future;
  }

  // Separate method to perform the authentication
  Future<bool> _performAuthentication(
    User user,
    String password,
    String errorMessage,
  ) async {
    try {
      // Create credentials
      AuthCredential credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );

      // Reauthenticate user
      await user.reauthenticateWithCredential(credential);
      return true;
    } catch (e) {
      // Show error toast if still mounted
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  // Helper method to perform account deletion after authentication
  Future<void> _performAccountDeletion(User user) async {
    // Cache any needed translations before the async gap
    final String errorDeletingAccount =
        mounted
            ? "error_deleting_account".tr(context)
            : "Error deleting account";

    try {
      String userId = user.uid;

      // First, handle the user's devices - convert them back to preset devices instead of deleting them
      QuerySnapshot userDevices =
          await FirebaseFirestore.instance
              .collection('devices')
              .where('user_id', isEqualTo: userId)
              .where('is_user_added', isEqualTo: 1)
              .get();

      // Update devices batch to convert them back to preset devices
      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in userDevices.docs) {
        // Reset the device to a preset device and remove user-specific data
        batch.update(doc.reference, {
          'is_user_added': 0,
          'user_id': null,
          'daily_uptime': 0.0,
          'total_uptime': 0.0,
          'daily_consumption': 0.0,
          'last_active': null,
          'last_reset': null,
        });
      }
      await batch.commit();

      // Log the number of devices preserved
      developer.log(
        'Preserved ${userDevices.docs.length} devices while deleting account for user $userId',
      );

      // Delete user's consumption history collection
      final consumptionHistorySnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('consumption_history')
              .limit(
                100,
              ) // Use a limit to prevent processing too many documents at once
              .get();

      if (consumptionHistorySnapshot.docs.isNotEmpty) {
        WriteBatch historyBatch = FirebaseFirestore.instance.batch();
        for (var doc in consumptionHistorySnapshot.docs) {
          historyBatch.delete(doc.reference);
        }
        await historyBatch.commit();
      }

      // Delete the user's document
      await FirebaseFirestore.instance.collection('users').doc(userId).delete();

      // Delete Firebase Authentication account
      await user.delete();

      // Clear the cache without waiting for it to complete
      _clearCache().catchError((_) {});

      // Check if still mounted before using a new context for navigation
      if (!mounted) return;

      // Navigate to login screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
      );
    } catch (e) {
      // Check if still mounted before showing error
      if (!mounted) return;

      // Now use a synchronous context with pre-cached translation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "$errorDeletingAccount: $e",
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Main account deletion method
  Future<void> _deleteAccount() async {
    // Cache any needed translations before async gap
    final String errorDeletingAccount =
        mounted
            ? "error_deleting_account".tr(context)
            : "Error deleting account";

    try {
      // Get current user
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Show authentication dialog and wait for result
      final bool authSuccess = await _showAuthenticationDialog(user);

      // If auth succeeded, proceed with account deletion
      if (authSuccess) {
        await _performAccountDeletion(user);
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "$errorDeletingAccount: $e",
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _clearCache() async {
    try {
      // Store translation now, before async gap
      final String clearedMessage =
          mounted ? "cache_cleared".tr(context) : "Cache cleared";

      // Do async work
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Check if still mounted before proceeding
      if (!mounted) return;

      // Use the stored ScaffoldMessenger with pre-translated message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            clearedMessage,
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.blueAccent,
          duration: const Duration(seconds: 1),
        ),
      );

      // Reload default settings
      _loadSettings();
    } catch (e) {
      // Check if we're still mounted before showing error
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${"error_clearing_cache".tr(context)}: $e",
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDarkTheme = themeProvider.isDarkTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "settings".tr(context),
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isDarkTheme ? Colors.white : Colors.black,
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors:
                isDarkTheme
                    ? [Colors.blueAccent.withAlpha(77), Colors.black]
                    : [Colors.white, Colors.grey[300]!],
          ),
        ),
        child:
            _isLoading
                ? const Center(
                  child: CircularProgressIndicator(color: Colors.blueAccent),
                )
                : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 16.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Theme Settings
                        Text(
                          "theme".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SwitchListTile(
                          title: Text(
                            "dark_theme".tr(context),
                            style: GoogleFonts.poppins(
                              color:
                                  isDarkTheme ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          value: isDarkTheme,
                          onChanged: (value) {
                            themeProvider.toggleTheme(value);
                            _saveSettings();
                          },
                          activeColor: Colors.blueAccent,
                        ),
                        const SizedBox(height: 20),

                        // Data Sync Settings
                        Text(
                          "data_sync".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SwitchListTile(
                          title: Text(
                            "real_time_sync".tr(context),
                            style: GoogleFonts.poppins(
                              color:
                                  isDarkTheme ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          subtitle: Text(
                            "real_time_sync_description".tr(context),
                            style: GoogleFonts.poppins(
                              color:
                                  isDarkTheme ? Colors.white54 : Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                          value: _realTimeSync,
                          onChanged: (value) {
                            setState(() {
                              _realTimeSync = value;
                              _saveSettings();
                            });
                          },
                          activeColor: Colors.blueAccent,
                        ),
                        const SizedBox(height: 20),

                        // Energy Unit Settings
                        Text(
                          "energy_unit_title".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Card(
                          color:
                              isDarkTheme
                                  ? Colors.white.withAlpha(26)
                                  : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "select_energy_unit_text".tr(context),
                                  style: GoogleFonts.poppins(
                                    color:
                                        isDarkTheme
                                            ? Colors.white70
                                            : Colors.black87,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String>(
                                  value: _energyUnit,
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor:
                                        isDarkTheme
                                            ? Colors.white.withAlpha(26)
                                            : Colors.grey[200],
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  dropdownColor:
                                      isDarkTheme
                                          ? Colors.grey[900]
                                          : Colors.white,
                                  style: GoogleFonts.poppins(
                                    color:
                                        isDarkTheme
                                            ? Colors.white
                                            : Colors.black,
                                  ),
                                  items:
                                      ConversionUtilities.energyConversions.keys
                                          .map<DropdownMenuItem<String>>((
                                            String value,
                                          ) {
                                            return DropdownMenuItem<String>(
                                              value: value,
                                              child: Text(value),
                                            );
                                          })
                                          .toList(),
                                  onChanged: (String? newValue) {
                                    final BuildContext currentContext = context;
                                    setState(() {
                                      _energyUnit = newValue!;
                                      _saveSettings();
                                    });
                                    ScaffoldMessenger.of(
                                      currentContext,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          "energy_unit_updated".trParams(
                                            currentContext,
                                            [_energyUnit],
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        backgroundColor: Colors.blueAccent,
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "energy_unit_apply_note".tr(context),
                                  style: GoogleFonts.poppins(
                                    color: Colors.blueAccent,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Currency Settings
                        Text(
                          "currency_title".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Card(
                          color:
                              isDarkTheme
                                  ? Colors.white.withAlpha(26)
                                  : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "select_currency_text".tr(context),
                                  style: GoogleFonts.poppins(
                                    color:
                                        isDarkTheme
                                            ? Colors.white70
                                            : Colors.black87,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String>(
                                  value: _currency,
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor:
                                        isDarkTheme
                                            ? Colors.white.withAlpha(26)
                                            : Colors.grey[200],
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  dropdownColor:
                                      isDarkTheme
                                          ? Colors.grey[900]
                                          : Colors.white,
                                  style: GoogleFonts.poppins(
                                    color:
                                        isDarkTheme
                                            ? Colors.white
                                            : Colors.black,
                                  ),
                                  items:
                                      ConversionUtilities.currencyRates.keys.map<
                                        DropdownMenuItem<String>
                                      >((String value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(
                                            "$value (${ConversionUtilities.currencySymbols[value] ?? value})",
                                          ),
                                        );
                                      }).toList(),
                                  onChanged: (String? newValue) {
                                    if (newValue == null) return;

                                    // Store the new value
                                    final String currency = newValue;

                                    setState(() {
                                      _currency = currency;
                                    });

                                    // Save settings asynchronously
                                    _saveSettings();

                                    // Show snackbar synchronously
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          "currency_updated".trParams(context, [
                                            currency,
                                          ]),
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        backgroundColor: Colors.blueAccent,
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "currency_apply_note".tr(context),
                                  style: GoogleFonts.poppins(
                                    color: Colors.blueAccent,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Notification Settings
                        Text(
                          "notifications_title".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SwitchListTile(
                          title: Text(
                            "enable_notifications".tr(context),
                            style: GoogleFonts.poppins(
                              color:
                                  isDarkTheme ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          subtitle: Text(
                            "notifications_description".tr(context),
                            style: GoogleFonts.poppins(
                              color:
                                  isDarkTheme ? Colors.white54 : Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                          value: _notificationsEnabled,
                          onChanged: (value) {
                            setState(() {
                              _notificationsEnabled = value;
                              _saveSettings();
                            });
                          },
                          activeColor: Colors.blueAccent,
                        ),
                        const SizedBox(height: 20),

                        // Data Export Frequency
                        Text(
                          "data_export".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        DropdownButtonFormField<String>(
                          value: _exportFrequency,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor:
                                isDarkTheme
                                    ? Colors.white.withAlpha(26)
                                    : Colors.grey[200],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          dropdownColor:
                              isDarkTheme ? Colors.grey[900] : Colors.white,
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                          ),
                          items:
                              <String>[
                                'daily',
                                'weekly',
                                'monthly',
                              ].map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value.toUpperCase()),
                                );
                              }).toList(),
                          onChanged: (String? newValue) {
                            setState(() {
                              _exportFrequency = newValue!;
                              _saveSettings();
                            });
                          },
                        ),
                        const SizedBox(height: 20),

                        // Language Selection
                        Text(
                          "language".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        DropdownButtonFormField<String>(
                          value: _language,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor:
                                isDarkTheme
                                    ? Colors.white.withAlpha(26)
                                    : Colors.grey[200],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          dropdownColor:
                              isDarkTheme ? Colors.grey[900] : Colors.white,
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                          ),
                          items:
                              <Map<String, String>>[
                                {'code': 'en', 'name': 'English'},
                                {'code': 'ar', 'name': 'العربية'},
                                {'code': 'fr', 'name': 'Français'},
                              ].map<DropdownMenuItem<String>>((
                                Map<String, String> language,
                              ) {
                                return DropdownMenuItem<String>(
                                  value: language['code'],
                                  child: Text(language['name']!),
                                );
                              }).toList(),
                          onChanged: (String? newValue) {
                            if (newValue == null) return;

                            // Store the new value locally
                            final String languageCode = newValue;

                            // Update state and save synchronously
                            setState(() {
                              _language = languageCode;
                            });

                            // Update app language using the LanguageProvider
                            final languageProvider =
                                Provider.of<LanguageProvider>(
                                  context,
                                  listen: false,
                                );
                            languageProvider.changeLanguage(languageCode);

                            // Save settings asynchronously
                            _saveSettings();

                            // Show UI feedback synchronously
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  "language_updated".tr(context),
                                  style: const TextStyle(color: Colors.white),
                                ),
                                backgroundColor: Colors.blueAccent,
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),

                        // Account Management
                        Text(
                          "profile".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ListTile(
                          title: Text(
                            "view_profile".tr(context),
                            style: GoogleFonts.poppins(
                              color: Colors.blueAccent,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.person,
                            color: Colors.blueAccent,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ProfileScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        ListTile(
                          title: Text(
                            "logout_title".tr(context),
                            style: GoogleFonts.poppins(color: Colors.redAccent),
                          ),
                          trailing: const Icon(
                            Icons.logout,
                            color: Colors.redAccent,
                          ),
                          onTap: () {
                            showDialog(
                              context: context,
                              builder:
                                  (context) => AlertDialog(
                                    backgroundColor:
                                        isDarkTheme
                                            ? Colors.grey[900]
                                            : Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    title: Text(
                                      "logout_title".tr(context),
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white
                                                : Colors.black,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    content: Text(
                                      "logout_confirmation".tr(context),
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white70
                                                : Colors.black87,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text(
                                          "cancel".tr(context),
                                          style: GoogleFonts.poppins(
                                            color: Colors.blueAccent,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _logout();
                                        },
                                        child: Text(
                                          "logout".tr(context),
                                          style: GoogleFonts.poppins(
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                            );
                          },
                        ),
                        ListTile(
                          title: Text(
                            "delete_account_title".tr(context),
                            style: GoogleFonts.poppins(color: Colors.redAccent),
                          ),
                          trailing: const Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                          ),
                          onTap: () {
                            showDialog(
                              context: context,
                              builder:
                                  (context) => AlertDialog(
                                    backgroundColor:
                                        isDarkTheme
                                            ? Colors.grey[900]
                                            : Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    title: Text(
                                      "delete_account_title".tr(context),
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white
                                                : Colors.black,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    content: Text(
                                      "delete_account_confirmation".tr(context),
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white70
                                                : Colors.black87,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text(
                                          "cancel".tr(context),
                                          style: GoogleFonts.poppins(
                                            color: Colors.blueAccent,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _deleteAccount();
                                        },
                                        child: Text(
                                          "delete".tr(context),
                                          style: GoogleFonts.poppins(
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),

                        // Clear Cache/Data
                        Text(
                          "maintenance".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ListTile(
                          title: Text(
                            "clear_cache".tr(context),
                            style: GoogleFonts.poppins(
                              color:
                                  isDarkTheme ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.delete_sweep,
                            color: Colors.blueAccent,
                          ),
                          onTap: () {
                            showDialog(
                              context: context,
                              builder:
                                  (context) => AlertDialog(
                                    backgroundColor:
                                        isDarkTheme
                                            ? Colors.grey[900]
                                            : Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    title: Text(
                                      "clear_cache_title".tr(context),
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white
                                                : Colors.black,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    content: Text(
                                      "clear_cache_confirmation".tr(context),
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white70
                                                : Colors.black87,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text(
                                          "cancel".tr(context),
                                          style: GoogleFonts.poppins(
                                            color: Colors.blueAccent,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _clearCache();
                                        },
                                        child: Text(
                                          "clear".tr(context),
                                          style: GoogleFonts.poppins(
                                            color: Colors.blueAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                            );
                          },
                        ),
                        // Add bottom padding for navigation bar
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }
}
