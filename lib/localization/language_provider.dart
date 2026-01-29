import 'package:flutter/material.dart';
import 'app_localizations.dart';

class LanguageProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  LanguageProvider() {
    _loadSavedLanguage();
  }

  void _loadSavedLanguage() async {
    final savedLocale = await AppLocalizations.getLocale();
    _locale = savedLocale;
    notifyListeners();
  }

  Future<void> changeLanguage(String languageCode) async {
    if (_locale.languageCode == languageCode) return;
    
    _locale = Locale(languageCode);
    await AppLocalizations.setLocale(languageCode);
    notifyListeners();
  }

  // Returns whether the current language is RTL (right-to-left)
  bool get isRtl => _locale.languageCode == 'ar';
} 