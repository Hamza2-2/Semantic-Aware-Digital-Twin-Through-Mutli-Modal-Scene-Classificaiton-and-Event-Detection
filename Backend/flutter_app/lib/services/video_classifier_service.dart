// file header note
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'ip_address_service.dart';

class VideoClassifierService {
  static const List<String> classNames = [
    'airport',
    'bus',
    'metro(underground)',
    'metro_station(underground)',
    'park',
    'public_square',
    'shopping_mall',
    'street_pedestrian',
    'street_traffic',
    'tram',
  ];

  String _apiBaseUrl = 'http://localhost:5000';
  String _backendUrl = 'http://localhost:3000';
  final ApiService _apiService = ApiService();
  bool _saveToBackend = true;

  bool get saveToBackend => _saveToBackend;
  set saveToBackend(bool value) => _saveToBackend = value;

  String get backendUrl => _backendUrl;

  void setApiUrl(String url) {
    _apiBaseUrl = url;
  }

  void setBackendUrl(String url) {
    _backendUrl = url;
  }

  void setSaveToBackend(bool save) {
    _saveToBackend = save;
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _apiBaseUrl = prefs.getString('ml_server_url') ?? _apiBaseUrl;
    _backendUrl = prefs.getString('backend_url') ?? _backendUrl;
    _saveToBackend = prefs.getBool('save_to_backend') ?? _saveToBackend;
  }

  Future<bool> isBackendAvailable() async {
    return await _apiService.checkHealth();
  }

  Future<Map<String, dynamic>> classifyVideoWithBackend(
    String videoPath, {
    bool multiLabel = false,
    String? userId,
  }) async {
    try {
      final result = await _apiService.uploadAndClassifyVideo(
        videoPath: videoPath,
        multiLabel: multiLabel,
        userId: userId,
      );
      return result;
    } catch (e) {
      print('Backend not available, falling back to direct inference: $e');
      return classifyVideo(videoPath, multiLabel: multiLabel);
    }
  }

  Future<List<dynamic>> getClassificationHistory() async {
    try {
      return await _apiService.getAllVideos();
    } catch (e) {
      print('Failed to get classification history: $e');
      return [];
    }
  }

  Future<List<dynamic>> getHistory({String? type}) async {
    try {
      return await _apiService.getAllHistory(type: type);
    } catch (e) {
      print('Failed to get history: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> classifyVideo(
    String videoPath, {
    bool multiLabel = false,
  }) async {
    try {
      final file = File(videoPath);
      if (!await file.exists()) {
        throw Exception('Video file not found: $videoPath');
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_apiBaseUrl/predict/video'),
      );

      request.files.add(await http.MultipartFile.fromPath('video', videoPath));

      if (multiLabel) {
        request.fields['multi_label'] = 'true';
      }

      final streamedResponse = await request.send().timeout(
            const Duration(seconds: 120),
          );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('Video classification failed: $e');

      final mock = multiLabel
          ? _getMockMultiLabelPrediction()
          : _getMockPrediction('video');
      mock['isDemo'] = true;
      mock['connectionError'] = e.toString();
      return mock;
    }
  }

  Future<Map<String, dynamic>> classifyVideoMultiLabel(String videoPath) async {
    return classifyVideo(videoPath, multiLabel: true);
  }

  Future<Map<String, dynamic>> classifyAudio(String audioPath) async {
    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        throw Exception('Audio file not found: $audioPath');
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_apiBaseUrl/predict/audio'),
      );

      request.files.add(await http.MultipartFile.fromPath('audio', audioPath));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('Audio classification failed: $e');
      final mock = _getMockPrediction('audio');
      mock['isDemo'] = true;
      mock['connectionError'] = e.toString();
      return mock;
    }
  }

  Future<Map<String, dynamic>> classifyMultimodal({
    String? videoPath,
    String? audioPath,
  }) async {
    try {
      if (videoPath == null && audioPath == null) {
        throw Exception('No video or audio file provided');
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_apiBaseUrl/predict/multimodal'),
      );

      if (videoPath != null) {
        request.files.add(
          await http.MultipartFile.fromPath('video', videoPath),
        );
      }
      if (audioPath != null) {
        request.files.add(
          await http.MultipartFile.fromPath('audio', audioPath),
        );
      }

      final streamedResponse = await request.send().timeout(
            const Duration(seconds: 180),
          );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        if (result.containsKey('error')) {
          throw Exception(result['error']);
        }
        return result;
      } else {
        String serverMsg = response.body;
        try {
          final body = json.decode(response.body) as Map<String, dynamic>;
          serverMsg = body['error']?.toString() ?? response.body;
        } catch (_) {}
        throw Exception('Server error ${response.statusCode}: $serverMsg');
      }
    } catch (e) {
      print('Multimodal request failed: $e');

      try {
        Map<String, dynamic>? videoResult;
        Map<String, dynamic>? audioResult;

        if (videoPath != null) {
          videoResult = await classifyVideo(videoPath);
        }
        if (audioPath != null) {
          audioResult = await classifyAudio(audioPath);
        }

        final videoLive = videoResult != null &&
            videoResult['isDemo'] != true &&
            videoResult['error'] != true;
        final audioLive = audioResult != null &&
            audioResult['isDemo'] != true &&
            audioResult['error'] != true;

        if (videoLive && audioLive) {
          final videoConfidence =
              (videoResult!['confidence'] as num?)?.toDouble() ?? 0.0;
          final audioConfidence =
              (audioResult!['confidence'] as num?)?.toDouble() ?? 0.0;

          final totalWeight = videoConfidence + audioConfidence;
          final videoWeight =
              totalWeight > 0 ? videoConfidence / totalWeight : 0.5;
          final audioWeight =
              totalWeight > 0 ? audioConfidence / totalWeight : 0.5;

          final predictedClass = videoConfidence >= audioConfidence
              ? videoResult['predictedClass']
              : audioResult['predictedClass'];
          final finalConfidence = videoConfidence * 0.6 + audioConfidence * 0.4;

          final videoPreds = {
            for (final p in (videoResult['topPredictions'] as List? ?? []))
              p['class'].toString():
                  ((p['confidence'] as num?)?.toDouble() ?? 0.0)
          };
          final audioPreds = {
            for (final p in (audioResult['topPredictions'] as List? ?? []))
              p['class'].toString():
                  ((p['confidence'] as num?)?.toDouble() ?? 0.0)
          };

          final fused = <String, double>{};
          final allClasses = {...videoPreds.keys, ...audioPreds.keys};
          for (final cls in allClasses) {
            fused[cls] = (videoPreds[cls] ?? 0.0) * videoWeight +
                (audioPreds[cls] ?? 0.0) * audioWeight;
          }

          final sorted = fused.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final topPredictions = sorted.take(5).map((e) {
            return {'class': e.key, 'confidence': e.value};
          }).toList();

          return {
            'predictedClass': predictedClass,
            'confidence': finalConfidence,
            'topPredictions': topPredictions,
            'type': 'multimodal',
            'videoResult': videoResult,
            'audioResult': audioResult,
            'fusionMethod': 'late_fusion_weighted_client',
          };
        }

        if (videoLive) {
          return {
            ...videoResult!,
            'type': 'multimodal',
          };
        }
        if (audioLive) {
          return {
            ...audioResult!,
            'type': 'multimodal',
          };
        }
      } catch (_) {}

      final mock = _getMockFusionPrediction();
      mock['isDemo'] = true;
      mock['connectionError'] = e.toString();
      return mock;
    }
  }

  Future<Map<String, dynamic>> classifyFusion(
    String videoPath, {
    String fusionMethod = 'confidence',
    bool multiScene = false,
  }) async {
    try {
      final file = File(videoPath);
      if (!await file.exists()) {
        throw Exception('Video file not found: $videoPath');
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_apiBaseUrl/predict/fusion'),
      );

      request.files.add(await http.MultipartFile.fromPath('video', videoPath));
      request.fields['fusion_method'] = fusionMethod;
      if (multiScene) {
        request.fields['multi_scene'] = 'true';
      }

      final streamedResponse = await request.send().timeout(
            const Duration(seconds: 180),
          );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        if (result.containsKey('error')) {
          throw Exception(result['error']);
        }
        return result;
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('Fusion request failed: $e');
      final mock = multiScene
          ? _getMockMultiSceneFusionPrediction()
          : _getMockFusionPrediction();
      mock['isDemo'] = true;
      mock['error'] = false;
      mock['connectionError'] = e.toString();
      mock['message'] =
          'Demo result - Inference server not connected at $_apiBaseUrl. '
          'Start the Python inference server for real predictions.';
      return mock;
    }
  }

  Map<String, dynamic> _getMockMultiSceneFusionPrediction() {
    return {
      'type': 'fusion_multiscene',
      'isMultiscene': true,
      'fusionMethod': 'confidence',
      'predictedClass': 'street_traffic',
      'confidence': 0.91,
      'totalSegments': 4,
      'topPredictions': [
        {'class': 'street_traffic', 'confidence': 0.91},
        {'class': 'bus', 'confidence': 0.85},
        {'class': 'tram', 'confidence': 0.78},
      ],
      'detectedScenes': [
        {
          'class': 'street_traffic',
          'maxConfidence': 0.91,
          'occurrences': 2,
          'percentageOfVideo': 50.0,
          'fusionAgreement': true,
        },
        {
          'class': 'bus',
          'maxConfidence': 0.85,
          'occurrences': 1,
          'percentageOfVideo': 25.0,
          'fusionAgreement': true,
        },
        {
          'class': 'tram',
          'maxConfidence': 0.78,
          'occurrences': 1,
          'percentageOfVideo': 25.0,
          'fusionAgreement': false,
        },
      ],
      'segmentPredictions': [
        {
          'segment': 0,
          'startTime': 0.0,
          'endTime': 5.0,
          'fusedClass': 'street_traffic',
          'fusedConfidence': 0.91,
          'videoClass': 'street_traffic',
          'videoConfidence': 0.89,
          'audioClass': 'street_traffic',
          'audioConfidence': 0.88,
          'agreement': true,
        },
        {
          'segment': 1,
          'startTime': 5.0,
          'endTime': 10.0,
          'fusedClass': 'bus',
          'fusedConfidence': 0.85,
          'videoClass': 'bus',
          'videoConfidence': 0.82,
          'audioClass': 'bus',
          'audioConfidence': 0.80,
          'agreement': true,
        },
        {
          'segment': 2,
          'startTime': 10.0,
          'endTime': 15.0,
          'fusedClass': 'street_traffic',
          'fusedConfidence': 0.87,
          'videoClass': 'street_traffic',
          'videoConfidence': 0.85,
          'audioClass': 'street_traffic',
          'audioConfidence': 0.83,
          'agreement': true,
        },
        {
          'segment': 3,
          'startTime': 15.0,
          'endTime': 20.0,
          'fusedClass': 'tram',
          'fusedConfidence': 0.78,
          'videoClass': 'tram',
          'videoConfidence': 0.80,
          'audioClass': 'bus',
          'audioConfidence': 0.72,
          'agreement': false,
        },
      ],
      'videoResult': {
        'predictedClass': 'street_traffic',
        'confidence': 0.89,
      },
      'audioResult': {
        'predictedClass': 'street_traffic',
        'confidence': 0.88,
      },
      'fusionAnalysis': {
        'modalityAgreement': true,
        'agreementScore': 0.82,
        'videoWeight': 0.5028,
        'audioWeight': 0.4972,
        'sceneTransitions': 3,
      },
      'summary': 'Detected 3 scene(s): street_traffic, bus, tram',
    };
  }

  Map<String, dynamic> _getMockFusionPrediction() {
    return {
      'type': 'fusion',
      'fusionMethod': 'confidence',
      'predictedClass': 'street_traffic',
      'confidence': 0.91,
      'topPredictions': [
        {'class': 'street_traffic', 'confidence': 0.91},
        {'class': 'street_pedestrian', 'confidence': 0.04},
        {'class': 'bus', 'confidence': 0.03},
        {'class': 'park', 'confidence': 0.01},
        {'class': 'tram', 'confidence': 0.01},
      ],
      'videoResult': {
        'predictedClass': 'street_traffic',
        'confidence': 0.89,
        'topPredictions': [
          {'class': 'street_traffic', 'confidence': 0.89},
          {'class': 'street_pedestrian', 'confidence': 0.06},
          {'class': 'bus', 'confidence': 0.03},
          {'class': 'park', 'confidence': 0.01},
          {'class': 'tram', 'confidence': 0.01},
        ],
      },
      'audioResult': {
        'predictedClass': 'street_traffic',
        'confidence': 0.88,
        'topPredictions': [
          {'class': 'street_traffic', 'confidence': 0.88},
          {'class': 'bus', 'confidence': 0.05},
          {'class': 'street_pedestrian', 'confidence': 0.04},
          {'class': 'tram', 'confidence': 0.02},
          {'class': 'park', 'confidence': 0.01},
        ],
      },
      'fusionAnalysis': {
        'modalityAgreement': true,
        'agreementScore': 0.82,
        'videoWeight': 0.5028,
        'audioWeight': 0.4972,
      },
      'isDemo': true,
      'message': 'Demo result - Backend server not connected. '
          'Run the Python inference server with /predict/fusion endpoint for real predictions.',
    };
  }

  Future<Map<String, dynamic>> classifyStream(
    String streamUrl, {
    int durationSeconds = 5,
    bool multiLabel = false,
  }) async {
    try {
      streamUrl = StreamUrlFormatter.normalize(streamUrl);
      final uri = Uri.tryParse(streamUrl);
      if (uri == null || !uri.hasScheme) {
        throw Exception('Invalid stream URL');
      }

      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/predict/stream'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'stream_url': streamUrl,
              'duration_seconds': durationSeconds,
              'multi_label': multiLabel,
            }),
          )
          .timeout(Duration(seconds: durationSeconds + 30));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      return multiLabel
          ? _getMockStreamMultiLabelPrediction(streamUrl)
          : _getMockStreamPrediction(streamUrl);
    }
  }

  Future<Map<String, dynamic>> classifyAudioStream(
    String streamUrl, {
    int durationSeconds = 10,
  }) async {
    try {
      streamUrl = StreamUrlFormatter.normalizeAudio(streamUrl);
      final uri = Uri.tryParse(streamUrl);
      if (uri == null || !uri.hasScheme) {
        throw Exception('Invalid stream URL');
      }

      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/predict/audio/stream'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'stream_url': streamUrl,
              'duration_seconds': durationSeconds,
            }),
          )
          .timeout(Duration(seconds: durationSeconds + 60));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        String serverMsg = '';
        try {
          final body = json.decode(response.body);
          serverMsg = body['error']?.toString() ?? response.body;
        } catch (_) {
          serverMsg = response.body;
        }
        throw Exception('Server error ${response.statusCode}: $serverMsg');
      }
    } catch (e) {
      print('[VideoClassifier] classifyAudioStream failed: $e');
      final errStr = e.toString();

      final isServerDown = errStr.contains('SocketException') ||
          errStr.contains('Connection refused') ||
          errStr.contains('No route to host') ||
          errStr.contains('Connection reset') ||
          errStr.contains('Failed host lookup');
      return {
        'predictedClass': 'unknown',
        'confidence': 0.0,
        'topPredictions': <Map<String, dynamic>>[],
        'type': 'audio_stream',
        'streamUrl': streamUrl,
        'isDemo': true,
        'error': true,
        'connectionError': errStr,
        'message': isServerDown
            ? 'Inference server not reachable at $_apiBaseUrl. '
                'Start the Python inference server: python inference_server.py'
            : 'Audio classification failed: $errStr',
      };
    }
  }

  Future<Map<String, dynamic>> classifyFusionStream(
    String videoUrl, {
    String? audioUrl,
    int durationSeconds = 10,
    String fusionMethod = 'confidence',
  }) async {
    try {
      videoUrl = StreamUrlFormatter.normalize(videoUrl);
      audioUrl =
          audioUrl != null ? StreamUrlFormatter.normalizeAudio(audioUrl) : null;

      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/predict/fusion/stream'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'video_url': videoUrl,
              if (audioUrl != null) 'audio_url': audioUrl,
              'duration': durationSeconds,
              'fusion_method': fusionMethod,
            }),
          )
          .timeout(Duration(seconds: durationSeconds + 90));

      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        if (result.containsKey('error')) {
          throw Exception(result['error']);
        }
        return result;
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('[VideoClassifier] classifyFusionStream failed: $e');
      return {
        'type': 'fusion_stream',
        'fusionMethod': fusionMethod,
        'predictedClass': 'street_traffic',
        'confidence': 0.90,
        'topPredictions': [
          {'class': 'street_traffic', 'confidence': 0.90},
          {'class': 'bus', 'confidence': 0.05},
          {'class': 'park', 'confidence': 0.03},
        ],
        'videoResult': {
          'predictedClass': 'street_traffic',
          'confidence': 0.88,
          'streamUrl': videoUrl,
        },
        'audioResult': {
          'predictedClass': 'street_traffic',
          'confidence': 0.85,
          'streamUrl': audioUrl ?? videoUrl,
        },
        'fusionAnalysis': {
          'modalityAgreement': true,
          'agreementScore': 0.82,
          'videoWeight': 0.51,
          'audioWeight': 0.49,
        },
        'isDemo': true,
        'message': 'Demo result - Inference server not connected at $_apiBaseUrl. '
            'Run the Python inference server with /predict/fusion/stream endpoint for real predictions.',
      };
    }
  }

  Future<Map<String, dynamic>> classifyAudioLocal({
    int durationSeconds = 10,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/predict/audio/local'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'duration_seconds': durationSeconds}),
          )
          .timeout(Duration(seconds: durationSeconds + 60));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('[VideoClassifier] classifyAudioLocal failed: $e');
      final mock = _getMockPrediction('audio');
      mock['isDemo'] = true;
      mock['connectionError'] = e.toString();
      return mock;
    }
  }

  Future<Map<String, dynamic>> classifyVideoLocal({
    int durationSeconds = 5,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/predict/video/local'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'duration_seconds': durationSeconds}),
          )
          .timeout(Duration(seconds: durationSeconds + 60));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('[VideoClassifier] classifyVideoLocal failed: $e');
      final mock = _getMockPrediction('video');
      mock['isDemo'] = true;
      mock['connectionError'] = e.toString();
      return mock;
    }
  }

  Map<String, dynamic> _getMockStreamPrediction(String streamUrl) {
    return {
      'predictedClass': 'street_traffic',
      'confidence': 0.89,
      'topPredictions': [
        {'class': 'street_traffic', 'confidence': 0.89},
        {'class': 'street_pedestrian', 'confidence': 0.06},
        {'class': 'bus', 'confidence': 0.03},
        {'class': 'tram', 'confidence': 0.01},
        {'class': 'park', 'confidence': 0.01},
      ],
      'type': 'stream',
      'streamUrl': streamUrl,
      'isDemo': true,
      'message': 'Demo result - Backend server not connected. '
          'Run the Python inference server with /predict/stream endpoint for real predictions.',
    };
  }

  Map<String, dynamic> _getMockStreamMultiLabelPrediction(String streamUrl) {
    return {
      'type': 'stream_multilabel',
      'isMultilabel': true,
      'streamUrl': streamUrl,
      'capturedSeconds': 5.0,
      'totalSegments': 5,
      'predictedClass': 'street_traffic',
      'confidence': 0.91,
      'detectedClasses': [
        {
          'class': 'street_traffic',
          'maxConfidence': 0.91,
          'occurrences': 3,
          'percentageOfVideo': 60.0,
          'firstDetectedAt': 0.0,
          'lastDetectedAt': 3.0,
        },
        {
          'class': 'bus',
          'maxConfidence': 0.88,
          'occurrences': 2,
          'percentageOfVideo': 40.0,
          'firstDetectedAt': 2.0,
          'lastDetectedAt': 4.0,
        },
      ],
      'topPredictions': [
        {'class': 'street_traffic', 'confidence': 0.91},
        {'class': 'bus', 'confidence': 0.88},
      ],
      'summary': 'Detected 2 scene(s): street_traffic, bus',
      'isDemo': true,
      'message': 'Demo result - Backend server not connected.',
    };
  }

  Map<String, dynamic> _getMockPrediction(String type) {
    return {
      'predictedClass': 'street_traffic',
      'confidence': 0.87,
      'topPredictions': [
        {'class': 'street_traffic', 'confidence': 0.87},
        {'class': 'street_pedestrian', 'confidence': 0.08},
        {'class': 'bus', 'confidence': 0.03},
        {'class': 'park', 'confidence': 0.01},
        {'class': 'public_square', 'confidence': 0.01},
      ],
      'type': type,
      'isDemo': true,
      'message': 'Demo result - Backend server not connected. '
          'Run the Python inference server for real predictions.',
    };
  }

  Map<String, dynamic> _getMockMultiLabelPrediction() {
    return {
      'type': 'video_multilabel',
      'isMultilabel': true,
      'durationSeconds': 30.0,
      'totalSegments': 6,
      'segmentDuration': 5,
      'predictedClass': 'bus',
      'confidence': 0.98,
      'detectedClasses': [
        {
          'class': 'bus',
          'maxConfidence': 0.98,
          'occurrences': 3,
          'percentageOfVideo': 50.0,
          'firstDetectedAt': 0.0,
          'lastDetectedAt': 15.0,
        },
        {
          'class': 'tram',
          'maxConfidence': 0.92,
          'occurrences': 2,
          'percentageOfVideo': 33.3,
          'firstDetectedAt': 5.0,
          'lastDetectedAt': 12.5,
        },
        {
          'class': 'street_traffic',
          'maxConfidence': 0.87,
          'occurrences': 1,
          'percentageOfVideo': 16.7,
          'firstDetectedAt': 12.5,
          'lastDetectedAt': 17.5,
        },
      ],
      'secondaryClasses': [
        {'class': 'tram', 'maxConfidence': 0.92},
        {'class': 'street_traffic', 'maxConfidence': 0.87},
      ],
      'topPredictions': [
        {'class': 'bus', 'confidence': 0.98},
        {'class': 'tram', 'confidence': 0.92},
        {'class': 'street_traffic', 'confidence': 0.87},
      ],
      'segmentPredictions': [
        {
          'segment': 0,
          'startTime': 0.0,
          'endTime': 5.0,
          'predictedClass': 'bus',
          'confidence': 0.98,
        },
        {
          'segment': 1,
          'startTime': 2.5,
          'endTime': 7.5,
          'predictedClass': 'bus',
          'confidence': 0.95,
        },
        {
          'segment': 2,
          'startTime': 5.0,
          'endTime': 10.0,
          'predictedClass': 'tram',
          'confidence': 0.92,
        },
        {
          'segment': 3,
          'startTime': 7.5,
          'endTime': 12.5,
          'predictedClass': 'tram',
          'confidence': 0.88,
        },
        {
          'segment': 4,
          'startTime': 10.0,
          'endTime': 15.0,
          'predictedClass': 'bus',
          'confidence': 0.91,
        },
        {
          'segment': 5,
          'startTime': 12.5,
          'endTime': 17.5,
          'predictedClass': 'street_traffic',
          'confidence': 0.87,
        },
      ],
      'summary': 'Detected 3 scene(s): bus, tram, street_traffic',
      'isDemo': true,
      'message': 'Demo result - Backend server not connected.',
    };
  }

  Future<Map<String, dynamic>> detectAnomalies(String videoPath) async {
    try {
      final file = File(videoPath);
      if (!await file.exists()) {
        throw Exception('Video file not found: $videoPath');
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_apiBaseUrl/detect/anomalies'),
      );

      request.files.add(await http.MultipartFile.fromPath('video', videoPath));

      final streamedResponse = await request.send().timeout(
            const Duration(seconds: 120),
          );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      return _getMockAnomalyDetection();
    }
  }

  Map<String, dynamic> _getMockAnomalyDetection() {
    return {
      'eventDetected': true,
      'alertLevel': 'CRITICAL',
      'maxConfidence': 0.85,
      'totalDetections': 3,
      'videoInfo': {
        'width': 1920,
        'height': 1080,
        'fps': 30.0,
        'durationSeconds': 10.0,
        'totalFrames': 300,
      },
      'primaryDetection': {
        'timestamp': 2.5,
        'boundingBoxes': [
          {
            'x': 450,
            'y': 200,
            'width': 300,
            'height': 250,
            'confidence': 0.85,
            'area': 75000,
            'brightness': 220.5,
          },
        ],
      },
      'emergencyAction': {
        'recommended': true,
        'action': 'CALL_911',
        'message': 'Event detected! Emergency response recommended.',
      },
      'sceneClassification': {
        'predictedClass': 'street_traffic',
        'confidence': 0.87,
        'probabilities': {},
      },
      'isDemo': true,
      'message': 'Demo result - Backend server not connected.',
    };
  }

  Future<Map<String, dynamic>> detectAnomalyStream(
    String streamUrl, {
    int durationSeconds = 5,
  }) async {
    try {
      streamUrl = StreamUrlFormatter.normalize(streamUrl);
      final uri = Uri.tryParse(streamUrl);
      if (uri == null || !uri.hasScheme) {
        throw Exception('Invalid stream URL');
      }

      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/detect/anomalies/stream'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'stream_url': streamUrl,
              'duration': durationSeconds,
            }),
          )
          .timeout(Duration(seconds: durationSeconds + 60));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(
          errorBody['error'] ?? 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      return _getMockAnomalyStreamDetection(streamUrl, durationSeconds);
    }
  }

  Map<String, dynamic> _getMockAnomalyStreamDetection(
    String streamUrl,
    int duration,
  ) {
    return {
      'eventDetected': true,
      'alertLevel': 'CRITICAL',
      'maxConfidence': 0.82,
      'totalDetections': 2,
      'videoInfo': {
        'width': 1280,
        'height': 720,
        'fps': 15.0,
        'durationSeconds': duration.toDouble(),
        'totalFrames': (15 * duration),
      },
      'primaryDetection': {
        'timestamp': 1.8,
        'boundingBoxes': [
          {
            'x': 320,
            'y': 150,
            'width': 280,
            'height': 220,
            'confidence': 0.82,
            'area': 61600,
            'brightness': 215.0,
          },
        ],
      },
      'emergencyAction': {
        'recommended': true,
        'action': 'CALL_911',
        'message': 'Event detected! Emergency response recommended.',
      },
      'sceneClassification': {
        'predictedClass': 'bus',
        'confidence': 0.91,
        'probabilities': {},
      },
      'streamInfo': {
        'url': streamUrl,
        'capturedFrames': 15 * duration,
        'capturedDuration': duration.toDouble(),
      },
      'isDemo': true,
      'message': 'Demo result - Backend server not connected.',
    };
  }
}
