// Admin auth service for login and logout
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _roleKey = 'user_role';
  static const String _usernameKey = 'auth_username';
  static const String _userIdKey = 'auth_user_id';

  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(ApiConfig.connectionTimeout);

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, data['token']);
      await prefs.setString(_roleKey, data['user']['role']);
      await prefs.setString(_usernameKey, data['user']['username']);
      await prefs.setString(_userIdKey, data['user']['id']);
      return data;
    }
    throw Exception(data['error'] ?? 'Login failed');
  }

  // reset admin password
  static Future<void> resetPassword(
      String username, String newPassword, String adminKey) async {
    final response = await http
        .put(
          Uri.parse('${ApiConfig.baseUrl}/auth/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': username,
            'newPassword': newPassword,
            'adminKey': adminKey
          }),
        )
        .timeout(ApiConfig.connectionTimeout);

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['error'] ?? 'Password reset failed');
    }
  }

  // logout and clear token
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_userIdKey);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roleKey);
  }

  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_usernameKey);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  static Future<
      Future<http.Response> Function(Uri,
          {Map<String, String>? headers,
          Object? body})> authenticatedPut() async {
    final token = await getToken();
    return (Uri url, {Map<String, String>? headers, Object? body}) {
      final authHeaders = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        ...?headers,
      };
      return http.put(url, headers: authHeaders, body: body);
    };
  }

  static Future<Map<String, dynamic>> neutralizeEvent(String eventId) async {
    final userId = await getUserId();
    final response = await http
        .put(
          Uri.parse('${ApiConfig.baseUrl}/events/$eventId/neutralize'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'userId': userId}),
        )
        .timeout(ApiConfig.connectionTimeout);

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to neutralize event');
  }
}
