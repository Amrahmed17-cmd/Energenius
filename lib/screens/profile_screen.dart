import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/custom_dropdown.dart';
import '../localization/app_localizations.dart';
import '../localization/language_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  ProfileScreenState createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String? _selectedCountry;
  final List<String> _countries = [
    "Egypt",
    "USA",
    "UK",
    "Canada",
    "Germany",
    "France",
    "India",
  ];

  User? user;
  bool _isLoading = false;
  String _currentLanguage = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
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

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      user = _auth.currentUser;
      if (user != null) {
        DocumentSnapshot userData =
            await _firestore.collection('users').doc(user!.uid).get();

        if (userData.exists && userData.data() != null) {
          final data = userData.data() as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              _firstNameController.text = data['first_name'] ?? "";
              _lastNameController.text = data['last_name'] ?? "";
              _dobController.text = data['dob'] ?? "";
              _selectedCountry = data['country'] ?? _countries.first;
            });
          }
        } else {
          // Initialize with default values if user document doesn't exist
          if (mounted) {
            setState(() {
              _firstNameController.text = "";
              _lastNameController.text = "";
              _dobController.text = "";
              _selectedCountry = _countries.first;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateProfile() async {
    try {
      // Store context and translations before async operations
      final BuildContext currentContext = context;
      final String successMessage = "success".tr(currentContext);

      await _firestore.collection('users').doc(user!.uid).update({
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'dob': _dobController.text.trim(),
        'country': _selectedCountry,
      });

      await user!.updateDisplayName(_firstNameController.text.trim());

      if (!mounted) return;
      _showSuccess(successMessage);
    } catch (e) {
      if (!mounted) return;
      // Using string interpolation instead of concatenation
      _showError("${context.mounted ? "error".tr(context) : "Error"}: $e");
    }
  }

  Future<void> _changePassword() async {
    // Get translation strings and context before async operations
    final BuildContext currentContext = context;
    final String passwordsDontMatchMsg = "passwords_dont_match".tr(
      currentContext,
    );
    final String successMsg = "success".tr(currentContext);
    final String errorMsg = "error".tr(currentContext);

    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showError(passwordsDontMatchMsg);
      return;
    }

    try {
      AuthCredential credential = EmailAuthProvider.credential(
        email: user!.email!,
        password: _oldPasswordController.text.trim(),
      );

      await user!.reauthenticateWithCredential(credential);
      await user!.updatePassword(_newPasswordController.text.trim());

      if (!mounted) return;
      _showSuccess(successMsg);
    } catch (e) {
      if (!mounted) return;
      // Using string interpolation instead of concatenation
      _showError("$errorMsg: $e");
    }
  }

  Future<void> _forceDatabaseMigration() async {
    if (user == null) return;

    try {
      // Store context and translations before async operations
      final BuildContext currentContext = context;
      final String successMsg = "db_already_migrated".tr(currentContext);

      setState(() => _isLoading = true);

      // Simulate some async work
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      _showSuccess(successMsg);
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      // Using string interpolation
      _showError("Error: $e");
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _launchURL(String url) async {
    // This method would use url_launcher package to open the URL
    // For now, we'll just show a snackbar as a demonstration
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening $url'),
        duration: const Duration(seconds: 1),
      ),
    );

    // To actually implement URL launching, you would:
    // 1. Add url_launcher package to pubspec.yaml
    // 2. Import it with: import 'package:url_launcher/url_launcher.dart';
    // 3. Launch with: await launchUrl(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDarkTheme = themeProvider.isDarkTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.blue,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "profile".tr(context),
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body:
          _isLoading
              ? Center(child: CircularProgressIndicator())
              : Container(
                color: isDarkTheme ? Colors.black : Colors.white,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
                    ),
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: [
                        Text(
                          "${context.mounted ? "update".tr(context) : "Update"} ${context.mounted ? "profile".tr(context) : "Profile"}",
                          style: GoogleFonts.poppins(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: isDarkTheme ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: CustomTextField(
                                labelText: "first_name".tr(context),
                                prefixIcon: Icons.person,
                                controller: _firstNameController,
                                isDarkTheme: isDarkTheme,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: CustomTextField(
                                labelText: "last_name".tr(context),
                                prefixIcon: Icons.person,
                                controller: _lastNameController,
                                isDarkTheme: isDarkTheme,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        CustomTextField(
                          labelText: "date_of_birth".tr(context),
                          prefixIcon: Icons.cake,
                          controller: _dobController,
                          isDarkTheme: isDarkTheme,
                          isReadOnly: true,
                          onTap: () async {
                            DateTime? pickedDate = await showDatePicker(
                              context: context,
                              initialDate: DateTime(2000),
                              firstDate: DateTime(1950),
                              lastDate: DateTime.now(),
                              builder: (context, child) {
                                return Theme(
                                  data: ThemeData.dark().copyWith(
                                    colorScheme: const ColorScheme.dark(
                                      primary: Colors.blue,
                                    ),
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (pickedDate != null) {
                              setState(() {
                                _dobController.text =
                                    "${pickedDate.day}/${pickedDate.month}/${pickedDate.year}";
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 15),
                        CustomDropdown<String>(
                          labelText: "country".tr(context),
                          prefixIcon: Icons.public,
                          value: _selectedCountry ?? _countries.first,
                          items: _countries,
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedCountry = newValue;
                            });
                          },
                          isDarkTheme: isDarkTheme,
                        ),
                        const SizedBox(height: 25),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _updateProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              "${context.mounted ? 'update'.tr(context) : 'Update'} ${context.mounted ? 'profile'.tr(context) : 'Profile'}",
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          "reset_password".tr(context),
                          style: GoogleFonts.poppins(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: isDarkTheme ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 20),
                        CustomTextField(
                          labelText: "password".tr(context),
                          prefixIcon: Icons.lock,
                          controller: _oldPasswordController,
                          obscureText: true,
                          isDarkTheme: isDarkTheme,
                        ),
                        const SizedBox(height: 15),
                        CustomTextField(
                          labelText: "new_password".tr(context),
                          prefixIcon: Icons.lock,
                          controller: _newPasswordController,
                          obscureText: true,
                          isDarkTheme: isDarkTheme,
                        ),
                        const SizedBox(height: 15),
                        CustomTextField(
                          labelText: "confirm_password".tr(context),
                          prefixIcon: Icons.lock,
                          controller: _confirmPasswordController,
                          obscureText: true,
                          isDarkTheme: isDarkTheme,
                        ),
                        const SizedBox(height: 25),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _changePassword,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              context.mounted
                                  ? "reset_password".tr(context)
                                  : "Reset Password",
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color:
                                isDarkTheme
                                    ? Colors.black.withAlpha(77)
                                    : Colors.grey[100],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.copyright,
                                    color:
                                        isDarkTheme
                                            ? Colors.white
                                            : Colors.black,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    "2025 ${context.mounted ? "app_name".tr(context) : "ENERGENIUS"}",
                                    style: GoogleFonts.poppins(
                                      color:
                                          isDarkTheme
                                              ? Colors.white
                                              : Colors.black,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      _launchURL(
                                        'https://energenius.com/terms',
                                      );
                                    },
                                    child: Text(
                                      "terms_of_service".tr(context),
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white.withAlpha(179)
                                                : Colors.black.withAlpha(179),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    "|",
                                    style: GoogleFonts.poppins(
                                      color:
                                          isDarkTheme
                                              ? Colors.white.withAlpha(179)
                                              : Colors.black.withAlpha(179),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      _launchURL(
                                        'https://energenius.com/privacy',
                                      );
                                    },
                                    child: Text(
                                      "privacy_policy".tr(context),
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDarkTheme
                                                ? Colors.white.withAlpha(179)
                                                : Colors.black.withAlpha(179),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: ElevatedButton.icon(
                            onPressed: _forceDatabaseMigration,
                            icon: Icon(Icons.storage, color: Colors.white),
                            label: Text(
                              "optimize_database".tr(context),
                              style: GoogleFonts.poppins(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _dobController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
