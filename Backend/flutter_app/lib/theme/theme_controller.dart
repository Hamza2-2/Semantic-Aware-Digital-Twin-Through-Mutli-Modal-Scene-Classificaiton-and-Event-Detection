import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  static const _key = "mvats_theme_dark";

  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  ThemeController._();

  static final ThemeController _instance = ThemeController._();
  static ThemeController get instance => _instance;

  static ThemeController of(BuildContext context) => instance;

  Future<void> loadTheme() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool(_key) ?? false;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, _isDarkMode);
    notifyListeners();
  }
}
