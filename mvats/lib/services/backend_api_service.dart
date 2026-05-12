// Backend REST API helper service
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class BackendConfig {
  static String _baseUrl = 'http://localhost:3000';

  static String get baseUrl => _baseUrl;

  static void setBaseUrl(String url) {
    _baseUrl = url;
  }

  static Future<bool> isAvailable() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}

class BackendApiService {
  Future<Map<String, dynamic>> getApiInfo() async {
    try {
      final response = await http
          .get(Uri.parse('${BackendConfig.baseUrl}/api'))
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to get API info');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> getAllHistory({String? type}) async {
    try {
      String url = '${BackendConfig.baseUrl}/history';
      if (type != null) {
        url += '?type=$type';
      }

      final response =
          await http.get(Uri.parse(url)).timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return body['data'] ?? [];
      } else {
        throw Exception('Failed to get history');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> getAllMedia({String? mediaType}) async {
    try {
      String url = '${BackendConfig.baseUrl}/media';
      if (mediaType != null) {
        url += '?mediaType=$mediaType';
      }

      final response =
          await http.get(Uri.parse(url)).timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return body['data'] ?? [];
      } else {
        throw Exception('Failed to get media');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> getAllVideos() async {
    try {
      final response = await http
          .get(Uri.parse('${BackendConfig.baseUrl}/video'))
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return body['videos'] ?? [];
      } else {
        throw Exception('Failed to get videos');
      }
    } catch (e) {
      rethrow;
    }
  }
}
