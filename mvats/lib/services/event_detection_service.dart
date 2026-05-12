// Event detection and creation service
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'ip_address_service.dart';

const Map<String, List<String>> sceneEventMap = {
  'airport': ['explosion', 'riot', 'fire_alarm', 'evacuation'],
  'bus': ['accident', 'fire', 'explosion', 'riot'],
  'metro': ['explosion', 'fire_alarm', 'evacuation', 'riot'],
  'metro_station': ['explosion', 'fire_alarm', 'riot', 'evacuation'],
  'park': ['riot', 'fire', 'accident', 'fight'],
  'public_square': ['riot', 'explosion', 'fight', 'fire'],
  'shopping_mall': ['riot', 'fire_alarm', 'explosion', 'fight'],
  'street_pedestrian': ['accident', 'fight', 'riot', 'explosion'],
  'street_traffic': ['accident', 'explosion', 'fire', 'vehicle_crash'],
  'tram': ['accident', 'fire', 'explosion', 'sudden_brake'],
};

const Map<String, int> eventSeverity = {
  'explosion': 5,
  'fire': 5,
  'fire_alarm': 4,
  'riot': 4,
  'accident': 4,
  'vehicle_crash': 4,
  'evacuation': 3,
  'fight': 3,
  'sudden_brake': 2,
};

class GeoLocation {
  final double latitude;
  final double longitude;
  final String city;
  final String region;
  final String country;
  final String accuracy;
  final String? ipAddress;
  final bool isLocal;

  GeoLocation({
    required this.latitude,
    required this.longitude,
    this.city = 'Unknown',
    this.region = 'Unknown',
    this.country = 'Unknown',
    this.accuracy = 'unknown',
    this.ipAddress,
    this.isLocal = false,
  });

  factory GeoLocation.fromJson(Map<String, dynamic> json) {
    return GeoLocation(
      latitude: (json['latitude'] ?? json['lat'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? json['lng'] ?? 0).toDouble(),
      city: json['city'] ?? 'Unknown',
      region: json['region'] ?? json['regionName'] ?? 'Unknown',
      country: json['country'] ?? json['country_name'] ?? 'Unknown',
      accuracy: json['accuracy'] ?? 'city_level',
      ipAddress: json['ip'] ?? json['ipAddress'],
      isLocal: json['isLocal'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'city': city,
        'region': region,
        'country': country,
        'accuracy': accuracy,
        'ipAddress': ipAddress,
        'isLocal': isLocal,
      };

  String get displayAddress => '$city, $region, $country';

  bool get hasValidCoordinates => latitude != 0 || longitude != 0;
}

class DetectedEvent {
  final String eventType;
  final double confidence;
  final int severity;
  final String sceneClass;
  final DateTime timestamp;
  final GeoLocation? location;

  DetectedEvent({
    required this.eventType,
    required this.confidence,
    required this.sceneClass,
    int? severity,
    DateTime? timestamp,
    this.location,
  })  : severity = severity ?? eventSeverity[eventType] ?? 3,
        timestamp = timestamp ?? DateTime.now();

  factory DetectedEvent.fromJson(Map<String, dynamic> json) {
    return DetectedEvent(
      eventType: json['type'] ?? json['eventType'] ?? 'unknown',
      confidence: (json['confidence'] ?? 0).toDouble(),
      sceneClass: json['sceneClass'] ?? json['scene'] ?? 'unknown',
      severity: json['severity'],
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString())
          : null,
      location: json['location'] != null
          ? GeoLocation.fromJson(json['location'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'eventType': eventType,
        'confidence': confidence,
        'severity': severity,
        'sceneClass': sceneClass,
        'timestamp': timestamp.toIso8601String(),
        'location': location?.toJson(),
      };

  String get displayName => eventType.replaceAll('_', ' ').toUpperCase();

  String get severityLabel {
    if (severity >= 5) return 'CRITICAL';
    if (severity >= 4) return 'HIGH';
    if (severity >= 3) return 'MEDIUM';
    return 'LOW';
  }
}

class EventDetectionResult {
  final String sceneClass;
  final double sceneConfidence;
  final List<Map<String, dynamic>> topPredictions;
  final List<DetectedEvent> events;
  final bool emergencyDetected;
  final String alertLevel;
  final GeoLocation? location;
  final DetectedEvent? highestSeverityEvent;

  EventDetectionResult({
    required this.sceneClass,
    required this.sceneConfidence,
    this.topPredictions = const [],
    required this.events,
    required this.emergencyDetected,
    required this.alertLevel,
    this.location,
    this.highestSeverityEvent,
  });

  factory EventDetectionResult.fromJson(Map<String, dynamic> json) {
    final sceneData = json['sceneClassification'] ?? {};
    final topPredictionsRaw = sceneData['topPredictions'];
    final topPredictions = <Map<String, dynamic>>[];
    if (topPredictionsRaw is List) {
      for (final item in topPredictionsRaw) {
        if (item is Map) {
          topPredictions.add(Map<String, dynamic>.from(item));
        }
      }
    }

    final eventData = json['eventDetection'] ?? {};
    final locationData = json['location'];

    final events = <DetectedEvent>[];
    final eventConfidences =
        eventData['eventConfidences'] as Map<String, dynamic>? ?? {};
    final sceneClass = sceneData['predictedClass'] ?? 'unknown';

    for (final entry in eventConfidences.entries) {
      events.add(DetectedEvent(
        eventType: entry.key,
        confidence: (entry.value as num).toDouble(),
        sceneClass: sceneClass,
        location:
            locationData != null ? GeoLocation.fromJson(locationData) : null,
      ));
    }

    events.sort((a, b) {
      final confCmp = b.confidence.compareTo(a.confidence);
      return confCmp != 0 ? confCmp : b.severity.compareTo(a.severity);
    });

    DetectedEvent? highestSeverity = events.isNotEmpty ? events.first : null;
    final highestData = eventData['highestSeverityEvent'];
    if (highestSeverity == null && highestData != null) {
      highestSeverity = DetectedEvent(
        eventType: highestData['type'] ?? 'unknown',
        confidence: (highestData['confidence'] ?? 0).toDouble(),
        severity: highestData['severity'],
        sceneClass: sceneClass,
        location:
            locationData != null ? GeoLocation.fromJson(locationData) : null,
      );
    }

    return EventDetectionResult(
      sceneClass: sceneClass,
      sceneConfidence: (sceneData['confidence'] ?? 0).toDouble(),
      topPredictions: topPredictions,
      events: events,
      emergencyDetected: eventData['eventsDetected'] ?? false,
      alertLevel: eventData['alertLevel'] ?? 'NORMAL',
      location:
          locationData != null ? GeoLocation.fromJson(locationData) : null,
      highestSeverityEvent: highestSeverity,
    );
  }
}

class EventDetectionService {
  static final EventDetectionService _instance =
      EventDetectionService._internal();
  factory EventDetectionService() => _instance;
  EventDetectionService._internal();

  String _mlServerUrl = 'http://localhost:5000';
  String _backendUrl = 'http://localhost:3000';

  // load data
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _mlServerUrl = prefs.getString('ml_server_url') ?? 'http://localhost:5000';
    _backendUrl = prefs.getString('backend_url') ?? 'http://localhost:3000';
  }

  String get mlServerUrl => _mlServerUrl;
  String get backendUrl => _backendUrl;

  Future<Map<String, String>> reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=14&addressdetails=1');
      final response = await http.get(uri, headers: {
        'User-Agent': 'MVATS/1.0',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final addr = data['address'] as Map<String, dynamic>? ?? {};
        final city = addr['city'] ??
            addr['town'] ??
            addr['village'] ??
            addr['suburb'] ??
            addr['neighbourhood'] ??
            'Unknown';
        final region = addr['state'] ??
            addr['county'] ??
            addr['state_district'] ??
            'Unknown';
        final country = addr['country'] ?? 'Unknown';
        return {'city': city, 'region': region, 'country': country};
      }
    } catch (e) {
      debugPrint('[EventDetectionService] Reverse geocode failed: $e');
    }
    return {'city': 'Unknown', 'region': 'Unknown', 'country': 'Unknown'};
  }

  Future<GeoLocation?> getGeolocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble('user_location_lat');
      final lng = prefs.getDouble('user_location_lng');
      if (lat != null && lng != null && (lat != 0 || lng != 0)) {
        final addr = await reverseGeocode(lat, lng);
        return GeoLocation(
          latitude: lat,
          longitude: lng,
          city: addr['city'] ?? 'Unknown',
          region: addr['region'] ?? 'Unknown',
          country: addr['country'] ?? 'Unknown',
          accuracy: 'gps',
        );
      }

      final response = await http
          .get(
            Uri.parse('$_mlServerUrl/geolocation'),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['location'] != null) {
          return GeoLocation.fromJson(data['location']);
        }
      }
    } catch (e) {
      debugPrint('[EventDetectionService] Geolocation failed: $e');
    }
    return null;
  }

  Future<GeoLocation?> getDeviceLocation({
    String? deviceId,
    String? streamUrl,
  }) async {
    final ipService = IpAddressService();
    DeviceIp? device;
    if (deviceId != null) device = ipService.findDeviceById(deviceId);
    if (device == null && streamUrl != null) {
      device = ipService.findDeviceByStreamUrl(streamUrl);
    }
    if (device != null && device.hasLocation) {
      return GeoLocation(
        latitude: device.latitude!,
        longitude: device.longitude!,
        accuracy: 'gps_device',
      );
    }

    return getGeolocation();
  }

  Future<EventDetectionResult?> detectEventsInVideo(
    String filePath, {
    bool enableAvSlowFast = true,
    double confidenceThreshold = 0.50,
    bool enableMotionFallback = false,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_mlServerUrl/detect/events'),
      );

      request.files.add(await http.MultipartFile.fromPath('video', filePath));
      request.fields['enable_avslowfast'] = enableAvSlowFast.toString();
      request.fields['confidence_threshold'] = confidenceThreshold.toString();
      request.fields['enable_motion_fallback'] =
          enableMotionFallback.toString();

      final streamedResponse =
          await request.send().timeout(const Duration(minutes: 5));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return EventDetectionResult.fromJson(data);
      } else {
        debugPrint('[EventDetectionService] Error: ${response.body}');
      }
    } catch (e) {
      debugPrint('[EventDetectionService] Detection failed: $e');
    }
    return null;
  }

  Future<EventDetectionResult?> detectEventsInAudio(
    String filePath, {
    double confidenceThreshold = 0.50,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_mlServerUrl/detect/events/audio'),
      );

      request.files.add(await http.MultipartFile.fromPath('audio', filePath));
      request.fields['confidence_threshold'] = confidenceThreshold.toString();

      final streamedResponse =
          await request.send().timeout(const Duration(minutes: 5));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return EventDetectionResult.fromJson(data);
      } else {
        debugPrint('[EventDetectionService] Audio error: ${response.body}');
      }
    } catch (e) {
      debugPrint('[EventDetectionService] Audio detection failed: $e');
    }
    return null;
  }

  Future<EventDetectionResult?> detectEventsInStream(
    String streamUrl, {
    int duration = 5,
    double confidenceThreshold = 0.50,
    bool enableMotionFallback = false,
  }) async {
    try {
      streamUrl = StreamUrlFormatter.normalize(streamUrl);
      final response = await http
          .post(
            Uri.parse('$_mlServerUrl/detect/events/stream'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'stream_url': streamUrl,
              'duration': duration,
              'confidence_threshold': confidenceThreshold,
              'enable_motion_fallback': enableMotionFallback,
            }),
          )
          .timeout(const Duration(minutes: 2));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return EventDetectionResult.fromJson(data);
      }
    } catch (e) {
      debugPrint('[EventDetectionService] Stream detection failed: $e');
    }
    return null;
  }

  Future<EventDetectionResult?> detectEventsInAudioStream(
    String streamUrl, {
    int duration = 10,
    double confidenceThreshold = 0.005,
  }) async {
    try {
      streamUrl = StreamUrlFormatter.normalizeAudio(streamUrl);
      final response = await http
          .post(
            Uri.parse('$_mlServerUrl/detect/events/audio/stream'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'stream_url': streamUrl,
              'duration': duration,
              'confidence_threshold': confidenceThreshold,
            }),
          )
          .timeout(const Duration(minutes: 2));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return EventDetectionResult.fromJson(data);
      } else {
        debugPrint(
            '[EventDetectionService] Audio stream detection error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[EventDetectionService] Audio stream detection failed: $e');
    }
    return null;
  }

  Future<EventDetectionResult?> detectEventsFromLocalMic({
    int duration = 10,
    double confidenceThreshold = 0.50,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_mlServerUrl/detect/events/audio/local'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'duration': duration,
              'confidence_threshold': confidenceThreshold,
            }),
          )
          .timeout(Duration(seconds: duration + 60));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return EventDetectionResult.fromJson(data);
      } else {
        debugPrint(
            '[EventDetectionService] Audio local detection error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[EventDetectionService] Audio local detection failed: $e');
    }
    return null;
  }

  Future<EventDetectionResult?> detectEventsFromLocalCamera({
    int duration = 5,
    double confidenceThreshold = 0.50,
    bool enableMotionFallback = false,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_mlServerUrl/detect/events/video/local'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'duration': duration,
              'confidence_threshold': confidenceThreshold,
              'enable_motion_fallback': enableMotionFallback,
            }),
          )
          .timeout(Duration(seconds: duration + 60));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return EventDetectionResult.fromJson(data);
      } else {
        debugPrint(
            '[EventDetectionService] Video local detection error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[EventDetectionService] Video local detection failed: $e');
    }
    return null;
  }

  Future<bool> saveEventToBackend(
    DetectedEvent event, {
    String? deviceId,
    String? deviceName,
    String? streamUrl,
    GeoLocation? overrideLocation,
    String sourceType = 'video',
    String? predictionId,
  }) async {
    try {
      GeoLocation? bestLocation = overrideLocation ?? event.location;

      if (bestLocation == null ||
          bestLocation.accuracy == 'city_level' ||
          !bestLocation.hasValidCoordinates) {
        final ipService = IpAddressService();
        DeviceIp? device;
        if (deviceId != null) device = ipService.findDeviceById(deviceId);
        if (device == null && streamUrl != null) {
          device = ipService.findDeviceByStreamUrl(streamUrl);
        }
        if (device != null && device.hasLocation) {
          bestLocation = GeoLocation(
            latitude: device.latitude!,
            longitude: device.longitude!,
            city: bestLocation?.city ?? 'Unknown',
            region: bestLocation?.region ?? 'Unknown',
            country: bestLocation?.country ?? 'Unknown',
            accuracy: 'gps_device',
            ipAddress: bestLocation?.ipAddress,
          );
        }
      }

      if (bestLocation == null || !bestLocation.hasValidCoordinates) {
        final prefs = await SharedPreferences.getInstance();
        final lat = prefs.getDouble('user_location_lat');
        final lng = prefs.getDouble('user_location_lng');
        if (lat != null && lng != null && (lat != 0 || lng != 0)) {
          bestLocation = GeoLocation(
            latitude: lat,
            longitude: lng,
            city: bestLocation?.city ?? 'Unknown',
            region: bestLocation?.region ?? 'Unknown',
            country: bestLocation?.country ?? 'Unknown',
            accuracy: 'gps',
            ipAddress: bestLocation?.ipAddress,
          );
        }
      }

      if (bestLocation != null &&
          bestLocation.hasValidCoordinates &&
          bestLocation.city == 'Unknown') {
        final addr =
            await reverseGeocode(bestLocation.latitude, bestLocation.longitude);
        bestLocation = GeoLocation(
          latitude: bestLocation.latitude,
          longitude: bestLocation.longitude,
          city: addr['city'] ?? 'Unknown',
          region: addr['region'] ?? 'Unknown',
          country: addr['country'] ?? 'Unknown',
          accuracy: bestLocation.accuracy,
          ipAddress: bestLocation.ipAddress,
        );
      }

      String? ipAddr = bestLocation?.ipAddress;
      if ((ipAddr == null || ipAddr.isEmpty) && streamUrl != null) {
        final uri = Uri.tryParse(streamUrl);
        if (uri != null && uri.host.isNotEmpty) {
          ipAddr = uri.host;
        }
      }

      final response = await http
          .post(
            Uri.parse('$_backendUrl/events'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'eventType': event.eventType,
              'severity': event.severityLabel.toLowerCase(),
              'predictedClass': event.sceneClass,
              'confidence': event.confidence,
              'sourceType': sourceType,
              if (streamUrl != null) 'streamUrl': streamUrl,
              if (deviceName != null) 'deviceName': deviceName,
              if (deviceId != null) 'deviceId': deviceId,
              if (predictionId != null) 'predictionId': predictionId,
              'location': bestLocation != null
                  ? {
                      'coordinates': [
                        bestLocation.longitude,
                        bestLocation.latitude
                      ],
                      'city': bestLocation.city,
                      'region': bestLocation.region,
                      'country': bestLocation.country,
                      'accuracy': bestLocation.accuracy,
                      if (ipAddr != null) 'ipAddress': ipAddr,
                    }
                  : null,
              'status': 'detected',
            }),
          )
          .timeout(const Duration(seconds: 30));

      return response.statusCode == 201;
    } catch (e) {
      debugPrint('[EventDetectionService] Save failed: $e');
      return false;
    }
  }

  List<String> getEventsForScene(String sceneClass) {
    return sceneEventMap[sceneClass.toLowerCase()] ?? [];
  }

  String? getBestEventForScene(String sceneClass) {
    final events = getEventsForScene(sceneClass);
    if (events.isEmpty) return null;

    String best = events.first;
    int bestSev = getSeverity(best);
    for (final e in events.skip(1)) {
      final s = getSeverity(e);
      if (s > bestSev) {
        best = e;
        bestSev = s;
      }
    }
    return best;
  }

  static const double eventConfidenceGate = 0.6;

  String? getBestEventForResult(Map<String, dynamic> result) {
    final eventDet = result['eventDetection'];
    if (eventDet is Map) {
      final eventConfs = eventDet['eventConfidences'] as Map?;
      if (eventConfs != null && eventConfs.isNotEmpty) {
        String? bestEvent;
        double bestConf = 0;
        eventConfs.forEach((event, conf) {
          final confVal =
              conf is num ? conf.toDouble() : double.tryParse('$conf') ?? 0;

          final tieBreaker =
              _getTieBreaker(event.toString(), eventConfs.length);
          if (confVal + tieBreaker >
              bestConf + _getTieBreaker(bestEvent ?? '', eventConfs.length)) {
            bestEvent = event.toString();
            bestConf = confVal;
          }
        });
        if (bestEvent != null && bestEvent!.isNotEmpty) {
          return bestEvent;
        }
      }

      final highest = eventDet['highestSeverityEvent'];
      if (highest != null && highest.toString().isNotEmpty) {
        return highest.toString();
      }

      final events = eventDet['events'];
      if (events is List && events.isNotEmpty) {
        return events.first.toString();
      }

      final probs = eventDet['probabilities'] ?? eventDet['eventProbabilities'];
      if (probs is Map && probs.isNotEmpty) {
        final typed = <String, double>{};
        for (final entry in probs.entries) {
          final value = entry.value;
          final parsed =
              value is num ? value.toDouble() : double.tryParse('$value');
          if (parsed != null) {
            typed[entry.key.toString()] = parsed;
          }
        }
        if (typed.isNotEmpty) {
          final sorted = typed.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          return sorted.first.key;
        }
      }
    }

    return null;
  }

  double _getTieBreaker(String event, int totalEvents) {
    final eventTieBreakers = {
      'explosion': 0.009,
      'fire': 0.008,
      'fire_alarm': 0.007,
      'riot': 0.006,
      'accident': 0.005,
      'vehicle_crash': 0.004,
      'evacuation': 0.003,
      'fight': 0.002,
      'sudden_brake': 0.001,
    };
    return eventTieBreakers[event.toLowerCase()] ?? 0.0001;
  }

  String _normalizeSceneKey(String value) {
    final key = value
        .toLowerCase()
        .replaceAll('(', '_')
        .replaceAll(')', '')
        .replaceAll('-', '_')
        .replaceAll('/', '_')
        .replaceAll(' ', '_')
        .replaceAll('__', '_');
    if (key == 'metro_underground') return 'metro';
    return key;
  }

  int getSeverity(String eventType) {
    return eventSeverity[eventType] ?? 3;
  }
}
