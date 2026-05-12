// file header note
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class StreamUrlFormatter {
  static const Map<String, int> defaultPorts = {
    'droidcam': 4747,
    'ipwebcam': 8080,
    'rtsp': 554,
  };

  static const Map<String, String> defaultPaths = {
    'droidcam': '/video',
    'ipwebcam': '/video',
  };

  static const Map<String, String> defaultAudioPaths = {
    'droidcam': '/audio.wav',
    'ipwebcam': '/audio.wav',
  };

  static String normalize(
    String raw, {
    String type = 'custom',
    bool applyDefaultPort = false,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;

    final normalizedType = type.toLowerCase();
    final preferredScheme = normalizedType == 'rtsp' ? 'rtsp' : 'http';
    var withScheme = trimmed;

    if (!withScheme.startsWith('http://') &&
        !withScheme.startsWith('https://') &&
        !withScheme.startsWith('rtsp://')) {
      withScheme = '$preferredScheme://$withScheme';
    }

    final parsed = Uri.tryParse(withScheme);
    if (parsed == null || parsed.host.isEmpty) {
      return withScheme;
    }

    final defaultPort = defaultPorts[normalizedType];
    final inferredPath = defaultPaths[normalizedType];
    final usesKnownHttpCameraPort = parsed.scheme != 'rtsp' &&
        (parsed.hasPort
            ? parsed.port == 4747 || parsed.port == 8080
            : defaultPort == 4747 || defaultPort == 8080);

    final nextPath = (parsed.path.isEmpty || parsed.path == '/') &&
            (inferredPath != null || usesKnownHttpCameraPort)
        ? inferredPath ?? '/video'
        : parsed.path;

    final nextPort = !parsed.hasPort && applyDefaultPort && defaultPort != null
        ? defaultPort
        : parsed.hasPort
            ? parsed.port
            : null;

    return parsed
        .replace(
          scheme: parsed.scheme.isEmpty ? preferredScheme : parsed.scheme,
          port: nextPort,
          path: nextPath,
        )
        .toString();
  }

  static String exampleForType(String type) {
    switch (type.toLowerCase()) {
      case 'droidcam':
        return '192.168.1.100:4747';
      case 'ipwebcam':
        return '192.168.1.100:8080';
      case 'rtsp':
        return 'rtsp://192.168.1.100:554/stream';
      default:
        return '192.168.1.100:4747 or full URL';
    }
  }

  
  
  
  static String normalizeAudio(
    String raw, {
    String type = 'custom',
    bool applyDefaultPort = false,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;

    final normalizedType = type.toLowerCase();
    var withScheme = trimmed;

    if (!withScheme.startsWith('http://') &&
        !withScheme.startsWith('https://') &&
        !withScheme.startsWith('rtsp://')) {
      withScheme = 'http://$withScheme';
    }

    final parsed = Uri.tryParse(withScheme);
    if (parsed == null || parsed.host.isEmpty) {
      return withScheme;
    }

    
    if (parsed.port == 8080 || normalizedType == 'ipwebcam') {
      final port = parsed.hasPort ? parsed.port : 8080;
      return 'http://${parsed.host}:$port/audio.wav';
    }

    
    
    if (parsed.port == 4747 ||
        (normalizedType == 'droidcam' && !parsed.hasPort)) {
      final port = parsed.hasPort ? parsed.port : 4747;
      return 'http://${parsed.host}:$port/audio.wav';
    }

    
    if (parsed.scheme == 'rtsp') {
      return withScheme;
    }

    
    return parsed
        .replace(
          path: parsed.path.isEmpty || parsed.path == '/'
              ? '/video'
              : parsed.path,
        )
        .toString();
  }

  static String portDescription(String type) {
    switch (type.toLowerCase()) {
      case 'droidcam':
        return 'Default port 4747. The app adds /video automatically.';
      case 'ipwebcam':
        return 'Default port 8080. The app adds /video automatically.';
      case 'rtsp':
        return 'Typical RTSP port is 554, but vendor ports may differ.';
      default:
        return 'Use the full stream URL, including any required port and path.';
    }
  }
}


class DeviceIp {
  final String id;
  String label;
  String address;
  String type; 
  DateTime addedAt;
  double? latitude;
  double? longitude;

  
  List<String> supportedModalities;

  DeviceIp({
    required this.id,
    required this.label,
    required this.address,
    this.type = 'custom',
    DateTime? addedAt,
    this.latitude,
    this.longitude,
    List<String>? supportedModalities,
  })  : addedAt = addedAt ?? DateTime.now(),
        supportedModalities =
            supportedModalities ?? defaultModalities(type ?? 'custom');

  
  static List<String> defaultModalities(String type) {
    switch (type) {
      case 'droidcam':
        
        return ['video', 'audio', 'fusion'];
      case 'ipwebcam':
        return ['video', 'audio', 'fusion'];
      case 'rtsp':
        
        return ['video', 'audio', 'fusion'];
      default:
        return ['video'];
    }
  }

  bool get supportsVideo => supportedModalities.contains('video');
  bool get supportsAudio => supportedModalities.contains('audio');
  bool get supportsFusion => supportedModalities.contains('fusion');

  
  bool get hasLocation =>
      latitude != null &&
      longitude != null &&
      (latitude != 0 || longitude != 0);

  
  String get streamUrl {
    return StreamUrlFormatter.normalize(
      address,
      type: type,
      applyDefaultPort: true,
    );
  }

  
  String get audioStreamUrl {
    return StreamUrlFormatter.normalizeAudio(
      address,
      type: type,
      applyDefaultPort: true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'address': address,
        'type': type,
        'addedAt': addedAt.toIso8601String(),
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'supportedModalities': supportedModalities,
      };

  factory DeviceIp.fromJson(Map<String, dynamic> json) => DeviceIp(
        id: json['id'] as String,
        label: json['label'] as String,
        address: json['address'] as String,
        type: json['type'] as String? ?? 'custom',
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
            DateTime.now(),
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        supportedModalities:
            (json['supportedModalities'] as List<dynamic>?)?.cast<String>(),
      );

  DeviceIp copyWith({
    String? id,
    String? label,
    String? address,
    String? type,
    DateTime? addedAt,
    double? latitude,
    double? longitude,
    List<String>? supportedModalities,
  }) {
    return DeviceIp(
      id: id ?? this.id,
      label: label ?? this.label,
      address: address ?? this.address,
      type: type ?? this.type,
      addedAt: addedAt ?? this.addedAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      supportedModalities: supportedModalities ?? this.supportedModalities,
    );
  }
}



class IpAddressService extends ChangeNotifier {
  static const String _storageKey = 'saved_device_ips';
  static const String _backendUrlKey = 'backend_url';
  static const String _defaultBackendUrl = 'http://localhost:3000';

  static final IpAddressService _instance = IpAddressService._internal();
  factory IpAddressService() => _instance;
  IpAddressService._internal();

  List<DeviceIp> _devices = [];
  bool _loaded = false;
  String? _cachedBackendUrl;

  List<DeviceIp> get devices => List.unmodifiable(_devices);

  
  Future<String> get _backendUrl async {
    if (_cachedBackendUrl != null) return _cachedBackendUrl!;
    final prefs = await SharedPreferences.getInstance();
    _cachedBackendUrl = prefs.getString(_backendUrlKey) ?? _defaultBackendUrl;
    return _cachedBackendUrl!;
  }

  
  Future<void> load() async {
    if (_loaded) return;

    
    try {
      final url = await _backendUrl;
      final response = await http.get(
        Uri.parse('$url/devices'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final List<dynamic> list = data['data'];
          _devices = list
              .map((e) => DeviceIp.fromJson(e as Map<String, dynamic>))
              .toList();
          _loaded = true;
          
          await _saveLocal();
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint('IpAddressService: backend unavailable, using local: $e');
    }

    
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _devices = list
            .map((e) => DeviceIp.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('IpAddressService: failed to parse stored IPs: $e');
        _devices = [];
      }
    }
    _loaded = true;
    notifyListeners();
  }

  
  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _storageKey, jsonEncode(_devices.map((d) => d.toJson()).toList()));
  }

  
  Future<void> _saveToBackend(DeviceIp device) async {
    try {
      final url = await _backendUrl;
      await http
          .post(
            Uri.parse('$url/devices'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(device.toJson()),
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('IpAddressService: failed to save device to backend: $e');
    }
  }

  
  Future<void> _updateOnBackend(DeviceIp device) async {
    try {
      final url = await _backendUrl;
      await http
          .put(
            Uri.parse('$url/devices/${device.id}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'label': device.label,
              'address': device.address,
              'type': device.type,
              'latitude': device.latitude,
              'longitude': device.longitude,
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('IpAddressService: failed to update device on backend: $e');
    }
  }

  
  Future<void> _deleteFromBackend(String id) async {
    try {
      final url = await _backendUrl;
      await http.delete(
        Uri.parse('$url/devices/$id'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('IpAddressService: failed to delete device from backend: $e');
    }
  }

  
  Future<void> addDevice(DeviceIp device) async {
    _devices.add(device);
    await _saveLocal();
    await _saveToBackend(device);
    notifyListeners();
  }

  
  Future<void> updateDevice(DeviceIp device) async {
    final idx = _devices.indexWhere((d) => d.id == device.id);
    if (idx != -1) {
      _devices[idx] = device;
      await _saveLocal();
      await _updateOnBackend(device);
      notifyListeners();
    }
  }

  
  Future<void> removeDevice(String id) async {
    _devices.removeWhere((d) => d.id == id);
    await _saveLocal();
    await _deleteFromBackend(id);
    notifyListeners();
  }

  
  String generateId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${_devices.length}';

  
  DeviceIp? findDeviceByStreamUrl(String streamUrl) {
    if (streamUrl.isEmpty) return null;
    final normalized = streamUrl.trim().toLowerCase();
    for (final d in _devices) {
      final addr = d.address.trim().toLowerCase();
      if (addr.isNotEmpty && normalized.contains(addr)) return d;
      
      final full = d.streamUrl.trim().toLowerCase();
      if (full.isNotEmpty &&
          (normalized.contains(full) || full.contains(normalized))) return d;
    }
    return null;
  }

  
  DeviceIp? findDeviceById(String id) {
    try {
      return _devices.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  
  List<DeviceIp> devicesForModality(String modality) {
    return _devices
        .where((d) => d.supportedModalities.contains(modality))
        .toList();
  }
}
