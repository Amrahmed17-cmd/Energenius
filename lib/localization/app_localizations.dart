import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLocalizations {
  final Locale locale;
  Map<String, String> _localizedStrings = {};
  static const String languageCode = 'languageCode';

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  Future<bool> load() async {
    // Load the language JSON file from the translations folder
    String jsonString = await rootBundle.loadString(
      'assets/translations/${locale.languageCode}.json',
    );
    Map<String, dynamic> jsonMap = json.decode(jsonString);

    _localizedStrings = jsonMap.map((key, value) {
      return MapEntry(key, value.toString());
    });

    return true;
  }

  // This method will be called from every widget which needs a localized text
  String translate(String key) {
    return _localizedStrings[key] ?? key;
  }

  // Utility method to replace placeholders in translation strings
  String translateWithParams(String key, List<String> params) {
    String translation = translate(key);
    for (int i = 0; i < params.length; i++) {
      translation = translation.replaceAll('{$i}', params[i]);
    }
    return translation;
  }

  // Get the saved language code
  static Future<Locale> getLocale() async {
    final prefs = await SharedPreferences.getInstance();
    String languageCodeValue = prefs.getString(languageCode) ?? 'en';
    return _getLocaleFromLanguageCode(languageCodeValue);
  }

  // Save selected language code to shared preferences
  static Future<void> setLocale(String languageCodeValue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(languageCode, languageCodeValue);
  }

  // Helper method to get locale from language code
  static Locale _getLocaleFromLanguageCode(String languageCode) {
    return Locale(languageCode);
  }
}

// Extension method on String for easier translation
extension LocalizationExtension on String {
  String tr(BuildContext context) {
    return AppLocalizations.of(context).translate(this);
  }

  String trParams(BuildContext context, List<String> params) {
    return AppLocalizations.of(context).translateWithParams(this, params);
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    // Include all supported language codes here
    return ['en', 'ar', 'fr'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    AppLocalizations localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
