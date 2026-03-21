import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageService {
  static const String _key = 'app_language';
  static final LanguageService _instance = LanguageService._internal();
  factory LanguageService() => _instance;
  LanguageService._internal();

  Locale? _cachedLocale;

  Future<Locale> getLocale() async {
    if (_cachedLocale != null) return _cachedLocale!;
    
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key);
    
    if (code != null) {
      _cachedLocale = Locale(code);
      return _cachedLocale!;
    }
    
    return const Locale('en');
  }

  Future<void> setLocale(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, languageCode);
    _cachedLocale = Locale(languageCode);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    _cachedLocale = null;
  }
}