// file header note
import 'dart:developer' as dev;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';



class PredictionHistoryService {
  static const String _backendUrlKey = 'backend_url';
  static const String _defaultBackendUrl = 'http://localhost:3000';
  static const String _localCacheKey = 'predictions_cache';

  static final PredictionHistoryService _instance =
      PredictionHistoryService._internal();

  factory PredictionHistoryService() => _instance;
  PredictionHistoryService._internal();

  String? _cachedBackendUrl;

  
  Future<String> get _backendUrl async {
    if (_cachedBackendUrl != null) return _cachedBackendUrl!;

    final prefs = await SharedPreferences.getInstance();
    _cachedBackendUrl = prefs.getString(_backendUrlKey) ?? _defaultBackendUrl;
    return _cachedBackendUrl!;
  }

  
  Future<void> setBackendUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendUrlKey, url);
    _cachedBackendUrl = url;
  }

  
  
  Future<String?> saveToHistory({
    required String type,
    required String fileName,
    required Map<String, dynamic> result,
    String? filePath,
    String? source,
    String? streamUrl,
    String? deviceName,
    int? streamDuration,
    String? fusionMethod,
    bool? multiScene,
    String? eventType,
    bool? eventDetectionEnabled,
  }) async {
    
    final resolvedSource =
        source ?? (type.contains('stream') ? 'stream' : 'file');
    final resolvedEventType = eventType ?? _extractEventType(result);

    try {
      final url = await _backendUrl;

      
      final predictedClass = _extractPrediction(result) ?? 'unknown';
      final confidence = _extractConfidence(result) ?? 0.0;
      final topPredictions = _extractTopPredictions(result);

      final body = {
        'type': type,
        'fileName': fileName,
        'filePath': filePath,
        'predictedClass': predictedClass,
        'confidence': confidence,
        'topPredictions': topPredictions,
        'result': result,
        'isDemo': result['isDemo'] ?? false,
        'isMultilabel': result['isMultilabel'] ?? false,
        'detectedClasses': result['detectedClasses'],
        'source': resolvedSource,
        'streamUrl': streamUrl,
        'deviceName': deviceName,
        'streamDuration': streamDuration,
        'fusionMethod': fusionMethod,
        'multiScene': multiScene ?? false,
        'eventType': resolvedEventType,
        'eventDetectionEnabled': eventDetectionEnabled ?? false,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final response = await http
          .post(
            Uri.parse('$url/predictions'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 201) {
        throw Exception('Failed to save: ${response.statusCode}');
      }

      
      try {
        final respData = jsonDecode(response.body);
        if (respData['success'] == true && respData['data'] != null) {
          return respData['data']['id'] as String?;
        }
      } catch (_) {}
      return null;
    } catch (e) {
      dev.log('Save to backend failed, using local cache: $e',
          name: 'PredictionHistory');
      
      await _saveToLocalCache(
        type: type,
        fileName: fileName,
        result: result,
        filePath: filePath,
        eventType: resolvedEventType,
        eventDetectionEnabled: eventDetectionEnabled ?? false,
      );
      return null;
    }
  }

  
  Future<List<Map<String, dynamic>>> getHistory() async {
    try {
      final url = await _backendUrl;

      
      final response = await http.get(
        Uri.parse('$url/predictions?limit=200'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final List<dynamic> predictions = data['data'];
          return predictions
              .map((p) => _transformPrediction(_castMap(p)))
              .toList();
        }
      }
      throw Exception('Failed to fetch: ${response.statusCode}');
    } catch (e) {
      dev.log('Fetch predictions failed: $e', name: 'PredictionHistory');
      
      return await _getLocalCache();
    }
  }

  
  Future<List<Map<String, dynamic>>> getHistoryByType(String type) async {
    try {
      final url = await _backendUrl;

      
      final response = await http.get(
        Uri.parse('$url/predictions?type=$type&limit=200'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final List<dynamic> predictions = data['data'];
          return predictions
              .map((p) => _transformPrediction(_castMap(p)))
              .toList();
        }
      }
      throw Exception('Failed to fetch: ${response.statusCode}');
    } catch (e) {
      dev.log('Fetch by type failed: $e', name: 'PredictionHistory');
      final all = await _getLocalCache();
      return all.where((entry) => entry['type'] == type).toList();
    }
  }

  
  Future<void> clearHistory() async {
    try {
      final url = await _backendUrl;

      final response = await http.delete(
        Uri.parse('$url/predictions'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Failed to clear: ${response.statusCode}');
      }
    } catch (e) {
      dev.log('Clear predictions failed: $e', name: 'PredictionHistory');
    }

    
    await _clearLocalCache();
  }

  
  Future<void> deleteEntry(String id) async {
    try {
      final url = await _backendUrl;

      final response = await http.delete(
        Uri.parse('$url/predictions/$id'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Failed to delete: ${response.statusCode}');
      }
    } catch (e) {
      dev.log('Delete prediction failed: $e', name: 'PredictionHistory');
      
      await _deleteFromLocalCache(id);
    }
  }

  
  Future<int> getHistoryCount() async {
    try {
      final url = await _backendUrl;

      final response = await http.get(
        Uri.parse('$url/predictions/stats'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return data['data']['total'] ?? 0;
        }
      }
      throw Exception('Failed to get count');
    } catch (e) {
      final cache = await _getLocalCache();
      return cache.length;
    }
  }

  
  Future<Map<String, dynamic>> getStats() async {
    try {
      final url = await _backendUrl;

      final response = await http.get(
        Uri.parse('$url/predictions/stats'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'] ?? {};
        }
      }
      throw Exception('Failed to get stats');
    } catch (e) {
      return {'total': 0, 'byType': [], 'topClasses': []};
    }
  }

  
  Map<String, dynamic> _castMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, val) {
        if (val is Map) {
          return MapEntry(key.toString(), _castMap(val));
        } else if (val is List) {
          return MapEntry(key.toString(), _castList(val));
        }
        return MapEntry(key.toString(), val);
      });
    }
    return {};
  }

  
  List<dynamic> _castList(List<dynamic> list) {
    return list.map((item) {
      if (item is Map) {
        return _castMap(item);
      } else if (item is List) {
        return _castList(item);
      }
      return item;
    }).toList();
  }

  
  Map<String, dynamic> _transformPrediction(Map<String, dynamic> p) {
    return {
      'id': p['_id'] ?? p['id'],
      'type': p['type'],
      'fileName': p['fileName'],
      'filePath': p['filePath'],
      'timestamp': p['timestamp'] ?? p['createdAt'],
      'result': p['result'] is Map ? _castMap(p['result']) : {},
      'prediction': p['predictedClass'],
      'confidence': p['confidence'],
      'probabilities': _topPredictionsToMap(p['topPredictions']),
      'tags': (p['topPredictions'] as List?)?.length,
      'isDemo': p['isDemo'],
      'isMultilabel': p['isMultilabel'],
      'detectedClasses':
          p['detectedClasses'] is List ? p['detectedClasses'] : null,
      
      'topPredictions': p['topPredictions'] is List
          ? _castList(p['topPredictions'])
          : p['topPredictions'],
      
      'source': p['source'],
      'streamUrl': p['streamUrl'],
      'deviceName': p['deviceName'],
      'streamDuration': p['streamDuration'],
      'fusionMethod': p['fusionMethod'],
      'multiScene': p['multiScene'],
      
      'eventType': p['eventType'],
      'eventDetectionEnabled': p['eventDetectionEnabled'] ?? false,
    };
  }

  
  Map<String, double>? _topPredictionsToMap(List<dynamic>? topPredictions) {
    if (topPredictions == null || topPredictions.isEmpty) return null;

    final Map<String, double> probMap = {};
    for (final pred in topPredictions) {
      if (pred is Map) {
        final label = pred['class'];
        final conf = pred['confidence'];
        if (label != null && conf != null) {
          probMap[label.toString()] = (conf as num).toDouble();
        }
      }
    }
    return probMap.isNotEmpty ? probMap : null;
  }

  
  List<Map<String, dynamic>> _extractTopPredictions(
      Map<String, dynamic> result) {
    
    if (result.containsKey('topPredictions') &&
        result['topPredictions'] is List) {
      return (result['topPredictions'] as List)
          .map((p) {
            if (p is Map) {
              return {
                'class': p['class'] ?? p['label'] ?? 'unknown',
                'confidence':
                    (p['confidence'] ?? p['probability'] ?? 0).toDouble(),
              };
            }
            return {'class': 'unknown', 'confidence': 0.0};
          })
          .toList()
          .cast<Map<String, dynamic>>();
    }

    
    if (result.containsKey('top_predictions') &&
        result['top_predictions'] is List) {
      return (result['top_predictions'] as List)
          .map((p) {
            if (p is Map) {
              return {
                'class': p['class'] ?? p['label'] ?? 'unknown',
                'confidence':
                    (p['confidence'] ?? p['probability'] ?? 0).toDouble(),
              };
            }
            return {'class': 'unknown', 'confidence': 0.0};
          })
          .toList()
          .cast<Map<String, dynamic>>();
    }

    
    if (result.containsKey('probabilities') && result['probabilities'] is Map) {
      final probs = result['probabilities'] as Map;
      final list = probs.entries
          .map((e) => {
                'class': e.key.toString(),
                'confidence': (e.value as num).toDouble(),
              })
          .toList();
      list.sort((a, b) =>
          (b['confidence'] as double).compareTo(a['confidence'] as double));
      return list.take(5).toList().cast<Map<String, dynamic>>();
    }

    return [];
  }

  

  Future<void> _saveToLocalCache({
    required String type,
    required String fileName,
    required Map<String, dynamic> result,
    String? filePath,
    String? eventType,
    bool eventDetectionEnabled = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheList = prefs.getStringList(_localCacheKey) ?? [];

      final entry = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'type': type,
        'fileName': fileName,
        'filePath': filePath,
        'timestamp': DateTime.now().toIso8601String(),
        'result': result,
        'prediction': _extractPrediction(result),
        'confidence': _extractConfidence(result),
        'probabilities': _extractProbabilities(result),
        'tags': _extractTags(result),
        'eventType': eventType,
        'eventDetectionEnabled': eventDetectionEnabled,
      };

      cacheList.add(jsonEncode(entry));
      await prefs.setStringList(_localCacheKey, cacheList);
    } catch (e) {
      dev.log('Local cache save failed: $e', name: 'PredictionHistory');
    }
  }

  Future<List<Map<String, dynamic>>> _getLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheList = prefs.getStringList(_localCacheKey) ?? [];

      return cacheList
          .map((e) => jsonDecode(e) as Map<String, dynamic>)
          .toList()
          .reversed
          .toList();
    } catch (e) {
      dev.log('Local cache load failed: $e', name: 'PredictionHistory');
      return [];
    }
  }

  Future<void> _clearLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localCacheKey);
  }

  Future<void> _deleteFromLocalCache(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheList = prefs.getStringList(_localCacheKey) ?? [];

    final filtered = cacheList.where((e) {
      final decoded = jsonDecode(e) as Map<String, dynamic>;
      return decoded['id'] != id;
    }).toList();

    await prefs.setStringList(_localCacheKey, filtered);
  }

  

  String? _extractPrediction(Map<String, dynamic> result) {
    if (result.containsKey('predictedClass')) {
      return result['predictedClass']?.toString();
    }
    if (result.containsKey('prediction')) {
      return result['prediction']?.toString();
    }
    if (result.containsKey('predicted_class')) {
      return result['predicted_class']?.toString();
    }
    if (result.containsKey('class')) {
      return result['class']?.toString();
    }
    if (result.containsKey('labels') && result['labels'] is List) {
      final labels = result['labels'] as List;
      if (labels.isNotEmpty) {
        return labels.first.toString();
      }
    }
    return null;
  }

  double? _extractConfidence(Map<String, dynamic> result) {
    if (result.containsKey('confidence')) {
      final conf = result['confidence'];
      if (conf is num) return conf.toDouble();
    }
    if (result.containsKey('probability')) {
      final prob = result['probability'];
      if (prob is num) return prob.toDouble();
    }
    if (result.containsKey('probabilities') && result['probabilities'] is Map) {
      final probs = result['probabilities'] as Map;
      if (probs.isNotEmpty) {
        final values = probs.values.whereType<num>();
        if (values.isNotEmpty) {
          return values.reduce((a, b) => a > b ? a : b).toDouble();
        }
      }
    }
    return null;
  }

  Map<String, double>? _extractProbabilities(Map<String, dynamic> result) {
    if (result.containsKey('probabilities') && result['probabilities'] is Map) {
      final probs = result['probabilities'] as Map;
      final Map<String, double> probMap = {};
      probs.forEach((key, value) {
        if (value is num) {
          probMap[key.toString()] = value.toDouble();
        }
      });
      if (probMap.isNotEmpty) return probMap;
    }

    if (result.containsKey('topPredictions') &&
        result['topPredictions'] is List) {
      final preds = result['topPredictions'] as List;
      final Map<String, double> probMap = {};
      for (final pred in preds) {
        if (pred is Map) {
          final label = pred['class'] ?? pred['label'] ?? pred['name'];
          final prob =
              pred['probability'] ?? pred['confidence'] ?? pred['score'];
          if (label != null && prob is num) {
            probMap[label.toString()] = prob.toDouble();
          }
        }
      }
      if (probMap.isNotEmpty) return probMap;
    }

    return null;
  }

  int? _extractTags(Map<String, dynamic> result) {
    final probs = _extractProbabilities(result);
    if (probs != null) return probs.length;

    if (result.containsKey('labels') && result['labels'] is List) {
      return (result['labels'] as List).length;
    }
    return null;
  }

  String? _extractEventType(Map<String, dynamic> result) {
    
    if (result.containsKey('eventType')) {
      return result['eventType']?.toString();
    }
    if (result.containsKey('detectedEventType')) {
      return result['detectedEventType']?.toString();
    }

    
    if (result.containsKey('eventDetection') &&
        result['eventDetection'] is Map) {
      final eventDet = result['eventDetection'] as Map;

      
      if (eventDet.containsKey('highestSeverityEvent')) {
        final highest = eventDet['highestSeverityEvent'];
        if (highest is Map && highest.containsKey('type')) {
          return highest['type']?.toString();
        }
        if (highest != null && highest.toString().isNotEmpty) {
          return highest.toString();
        }
      }

      
      if (eventDet.containsKey('events') && eventDet['events'] is List) {
        final events = eventDet['events'] as List;
        if (events.isNotEmpty) {
          return events.first?.toString();
        }
      }

      
      if (eventDet.containsKey('eventConfidences') &&
          eventDet['eventConfidences'] is Map) {
        final confs = eventDet['eventConfidences'] as Map;
        if (confs.isNotEmpty) {
          
          String? bestEvent;
          double bestConf = 0;
          confs.forEach((event, conf) {
            final confVal =
                conf is num ? conf.toDouble() : double.tryParse('$conf') ?? 0;
            if (confVal > bestConf) {
              bestEvent = event.toString();
              bestConf = confVal;
            }
          });
          if (bestEvent != null) return bestEvent;
        }
      }
    }

    return null;
  }
}
