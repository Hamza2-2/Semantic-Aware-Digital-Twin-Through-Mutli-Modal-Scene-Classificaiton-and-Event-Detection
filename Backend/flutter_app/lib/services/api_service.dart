// file header note
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';





class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  
  Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(
            Uri.parse(ApiConfig.health),
          )
          .timeout(ApiConfig.connectionTimeout);
      return response.statusCode == 200;
    } catch (e) {
      print('Health check failed: $e');
      return false;
    }
  }

  
  Future<Map<String, dynamic>> uploadMedia({
    required String filePath,
    required String mediaType,
    String? fileName,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiConfig.mediaUpload),
      );

      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      request.fields['mediaType'] = mediaType;
      if (fileName != null) {
        request.fields['fileName'] = fileName;
      }

      final streamedResponse =
          await request.send().timeout(ApiConfig.receiveTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception(
            'Upload failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Upload error: $e');
      rethrow;
    }
  }

  
  Future<Map<String, dynamic>> uploadAndClassifyVideo({
    required String videoPath,
    bool multiLabel = false,
    String? userId,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiConfig.videoUpload),
      );

      request.files.add(await http.MultipartFile.fromPath('video', videoPath));
      request.fields['multi_label'] = multiLabel.toString();
      if (userId != null) {
        request.fields['user_id'] = userId;
      }

      final streamedResponse =
          await request.send().timeout(ApiConfig.receiveTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      final body = json.decode(response.body);

      if (response.statusCode == 201) {
        return body;
      } else {
        throw Exception(body['error'] ?? 'Video classification failed');
      }
    } catch (e) {
      print('Video classification error: $e');
      rethrow;
    }
  }

  
  Future<List<dynamic>> getAllMedia({String? mediaType}) async {
    try {
      var url = ApiConfig.mediaList;
      if (mediaType != null) {
        url += '?mediaType=$mediaType';
      }

      final response = await http
          .get(
            Uri.parse(url),
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return body['data'] ?? [];
      } else {
        throw Exception('Failed to get media: ${response.statusCode}');
      }
    } catch (e) {
      print('Get media error: $e');
      rethrow;
    }
  }

  
  Future<Map<String, dynamic>> getMediaById(String id) async {
    try {
      final response = await http
          .get(
            Uri.parse(ApiConfig.mediaById(id)),
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return body['data'] ?? {};
      } else {
        throw Exception('Media not found');
      }
    } catch (e) {
      print('Get media by ID error: $e');
      rethrow;
    }
  }

  
  Future<List<dynamic>> getAllVideos() async {
    try {
      final response = await http
          .get(
            Uri.parse(ApiConfig.videoList),
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return body['videos'] ?? [];
      } else {
        throw Exception('Failed to get videos: ${response.statusCode}');
      }
    } catch (e) {
      print('Get videos error: $e');
      rethrow;
    }
  }

  
  Future<Map<String, dynamic>> getVideoById(String videoId) async {
    try {
      final response = await http
          .get(
            Uri.parse(ApiConfig.videoById(videoId)),
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return body['video'] ?? {};
      } else {
        throw Exception('Video not found');
      }
    } catch (e) {
      print('Get video by ID error: $e');
      rethrow;
    }
  }

  
  Future<List<dynamic>> getVideoTags(String videoId) async {
    try {
      final response = await http
          .get(
            Uri.parse(ApiConfig.videoTags(videoId)),
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return body['tags'] ?? [];
      } else {
        throw Exception('Failed to get tags');
      }
    } catch (e) {
      print('Get video tags error: $e');
      rethrow;
    }
  }

  
  Future<Map<String, dynamic>> createTag({
    required String tagName,
    required String fileType,
    required String mediaId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiConfig.tagsCreate),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'tagName': tagName,
              'fileType': fileType,
              'mediaId': mediaId,
            }),
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to create tag: ${response.statusCode}');
      }
    } catch (e) {
      print('Create tag error: $e');
      rethrow;
    }
  }

  
  Future<List<dynamic>> getAllTags({String? mediaId, String? fileType}) async {
    try {
      var url = ApiConfig.tagsList;
      final params = <String>[];
      if (mediaId != null) params.add('mediaId=$mediaId');
      if (fileType != null) params.add('fileType=$fileType');
      if (params.isNotEmpty) {
        url += '?${params.join('&')}';
      }

      final response = await http
          .get(
            Uri.parse(url),
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return body['data'] ?? [];
      } else {
        throw Exception('Failed to get tags: ${response.statusCode}');
      }
    } catch (e) {
      print('Get tags error: $e');
      rethrow;
    }
  }

  
  Future<List<dynamic>> getAllHistory({String? type, int limit = 100}) async {
    try {
      var url = ApiConfig.historyAll;
      final params = <String>[];
      if (type != null) params.add('type=$type');
      params.add('limit=$limit');
      url += '?${params.join('&')}';

      final response = await http
          .get(
            Uri.parse(url),
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return body['data'] ?? [];
      } else {
        throw Exception('Failed to get history: ${response.statusCode}');
      }
    } catch (e) {
      print('Get history error: $e');
      rethrow;
    }
  }

  
  Future<List<dynamic>> getHistoryByMedia(String mediaId,
      {String? type}) async {
    try {
      var url = ApiConfig.historyByMedia(mediaId);
      if (type != null) {
        url += '?type=$type';
      }

      final response = await http
          .get(
            Uri.parse(url),
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return body['data'] ?? [];
      } else {
        throw Exception('Failed to get history: ${response.statusCode}');
      }
    } catch (e) {
      print('Get history by media error: $e');
      rethrow;
    }
  }

  
  Future<Map<String, dynamic>> saveAudioHistory({
    required String mediaId,
    required String tagId,
    required double confidenceScore,
  }) async {
    return _saveHistory(
      url: ApiConfig.historyAudio,
      mediaId: mediaId,
      tagId: tagId,
      confidenceScore: confidenceScore,
    );
  }

  
  Future<Map<String, dynamic>> saveVideoHistory({
    required String mediaId,
    required String tagId,
    required double confidenceScore,
  }) async {
    return _saveHistory(
      url: ApiConfig.historyVideo,
      mediaId: mediaId,
      tagId: tagId,
      confidenceScore: confidenceScore,
    );
  }

  
  Future<Map<String, dynamic>> saveFusionHistory({
    required String mediaId,
    required String tagId,
    required double confidenceScore,
  }) async {
    return _saveHistory(
      url: ApiConfig.historyFusion,
      mediaId: mediaId,
      tagId: tagId,
      confidenceScore: confidenceScore,
    );
  }

  Future<Map<String, dynamic>> _saveHistory({
    required String url,
    required String mediaId,
    required String tagId,
    required double confidenceScore,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'mediaId': mediaId,
              'tagId': tagId,
              'confidenceScore': confidenceScore,
            }),
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to save history: ${response.statusCode}');
      }
    } catch (e) {
      print('Save history error: $e');
      rethrow;
    }
  }
}
