import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/custom_dropdown.dart';
import 'package:energenius/screens/login_screen.dart';
import '../utils/page_transition.dart';
import '../widgets/theme_toggle_button.dart';
import '../localization/app_localizations.dart';
import '../localization/language_provider.dart';
import '../database/database_helper.dart';
import 'main_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  SignupScreenState createState() => SignupScreenState();
}

class SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

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

  late AnimationController _animationController;
  String _currentLanguage = '';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    _animationController.forward();
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

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "passwords_dont_match".tr(context),
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    // Check if country is selected
    if (_selectedCountry == null || _selectedCountry!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "all_fields_required".tr(context),
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      // Create user document in Firestore with proper data
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'dob': _dobController.text.trim(),
        'country': _selectedCountry,
        'uid': userCredential.user!.uid,
        'created_at': FieldValue.serverTimestamp(),
      });

      // Update user display name in Firebase Auth
      await userCredential.user!.updateProfile(
        displayName: _firstNameController.text.trim(),
      );

      // Initialize database and consumption history for the new user
      await DatabaseHelper.instance.initialize(userCredential.user!.uid);
      await DatabaseHelper.instance.initializeUserConsumption(
        userCredential.user!.uid,
      );

      if (!mounted) return;
      // Navigate to main screen instead of login screen
      replaceWithFade(context, MainScreen());

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Account created successfully!",
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString(), style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDarkTheme = themeProvider.isDarkTheme;

    return Scaffold(
      backgroundColor: isDarkTheme ? Colors.black : Colors.white,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors:
                isDarkTheme
                    ? [Colors.blueAccent.withAlpha(77), Colors.black]
                    : [Colors.white, Colors.white],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 30),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.arrow_back,
                            size: 24,
                            color: isDarkTheme ? Colors.white : Colors.black,
                          ),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        ThemeToggleButton(
                          width: 80.0,
                          height: 24.0,
                          iconSize: 18.0,
                          animationDuration: Duration(milliseconds: 200),
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                    Text(
                      "signup".tr(context),
                      style: GoogleFonts.poppins(
                        color: isDarkTheme ? Colors.white : Colors.black,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
                                sigmaX: isDarkTheme ? 10 : 0,
                                sigmaY: isDarkTheme ? 10 : 0,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: CustomTextFormField(
                                  controller: _firstNameController,
                                  labelText: "first_name".tr(context),
                                  prefixIcon: Icons.person,
                                  isDarkTheme: isDarkTheme,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return "first_name_required".tr(context);
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
                                sigmaX: isDarkTheme ? 10 : 0,
                                sigmaY: isDarkTheme ? 10 : 0,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: CustomTextFormField(
                                  controller: _lastNameController,
                                  labelText: "last_name".tr(context),
                                  prefixIcon: Icons.person,
                                  isDarkTheme: isDarkTheme,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return "last_name_required".tr(context);
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 15),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: isDarkTheme ? 10 : 0,
                          sigmaY: isDarkTheme ? 10 : 0,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: CustomTextFormField(
                            controller: _emailController,
                            labelText: "email".tr(context),
                            prefixIcon: Icons.email,
                            isDarkTheme: isDarkTheme,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return "email_required".tr(context);
                              }
                              if (!RegExp(
                                r"^[a-zA-Z0-9.a-zA-Z0-9._%-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$",
                              ).hasMatch(value)) {
                                return "enter_valid_email".tr(context);
                              }
                              return null;
                            },
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 15),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: isDarkTheme ? 10 : 0,
                          sigmaY: isDarkTheme ? 10 : 0,
                        ),
                        child: CustomTextFormField(
                          controller: _passwordController,
                          labelText: "password".tr(context),
                          prefixIcon: Icons.lock,
                          isDarkTheme: isDarkTheme,
                          obscureText: true,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return "password_required".tr(context);
                            }
                            if (value.length < 6) {
                              return "password_required".tr(context);
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: 15),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: isDarkTheme ? 10 : 0,
                          sigmaY: isDarkTheme ? 10 : 0,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: CustomTextFormField(
                            controller: _confirmPasswordController,
                            labelText: "confirm_password".tr(context),
                            prefixIcon: Icons.lock,
                            isDarkTheme: isDarkTheme,
                            obscureText: true,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return "confirm_password_required".tr(context);
                              }
                              if (value != _passwordController.text) {
                                return "passwords_dont_match".tr(context);
                              }
                              return null;
                            },
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 15),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: isDarkTheme ? 10 : 0,
                          sigmaY: isDarkTheme ? 10 : 0,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: CustomTextField(
                            controller: _dobController,
                            labelText: "date_of_birth".tr(context),
                            prefixIcon: Icons.cake,
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
                        ),
                      ),
                    ),
                    SizedBox(height: 15),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: isDarkTheme ? 10 : 0,
                          sigmaY: isDarkTheme ? 10 : 0,
                        ),
                        child: CustomDropdown<String>(
                          labelText: "country".tr(context),
                          prefixIcon: Icons.public,
                          value: _selectedCountry ?? _countries.first,
                          items: _countries,
                          isDarkTheme: isDarkTheme,
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedCountry = newValue;
                            });
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _signup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          padding: EdgeInsets.zero,
                          elevation: 5,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Ink(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              _isLoading ? 25 : 10,
                            ),
                            gradient: const LinearGradient(
                              colors: [Colors.blueAccent, Colors.purpleAccent],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Container(
                            alignment: Alignment.center,
                            child:
                                _isLoading
                                    ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : Text(
                                      "signup".tr(context),
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "already_have_account".tr(context),
                          style: GoogleFonts.poppins(
                            color:
                                isDarkTheme
                                    ? Colors.white70
                                    : Colors.black.withAlpha(200),
                          ),
                        ),
                        TextButton(
                          onPressed:
                              () => replaceWithFade(context, LoginScreen()),
                          child: Text(
                            "login".tr(context),
                            style: GoogleFonts.poppins(
                              color: Colors.blueAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
