// App settings and device config screen
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/theme_controller.dart';
import '../widgets/glass_container.dart';
import '../widgets/background_blobs.dart';
import '../services/backend_api_service.dart';
import '../services/video_classifier_service.dart';
import '../services/ip_address_service.dart';
import '../utils/glass_snackbar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _backendUrlController = TextEditingController();
  final TextEditingController _mlServerUrlController = TextEditingController();
  final VideoClassifierService _classifier = VideoClassifierService();
  final IpAddressService _ipService = IpAddressService();

  bool _isCheckingBackend = false;
  bool? _backendAvailable;
  Map<String, dynamic>? _apiInfo;
  bool _saveToBackend = true;
  bool _enableMotionFallback = true;

  bool _showDummyMapEvents = false;
  bool _showDummyAudioData = false;
  bool _showDummyVideoData = false;
  bool _showDummyFusionData = false;

  bool _showDetectedEventsOnMap = true;

  bool _showFullPredictionDetails = true;

  bool _enableLaptopMic = true;
  bool _enableLaptopCamera = true;

  // Audio model selection: 'cnn14' or 'passt'
  String _audioModelType = 'cnn14';
  bool _isLoadingAudioModel = false;
  bool _passtAvailable = false;

  String _defaultMapProvider = 'osm';

  final TextEditingController _locationIpController = TextEditingController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();
  double? _savedLat;
  double? _savedLng;
  bool _resolvingLocation = false;

  @override
  void initState() {
    super.initState();
    _backendUrlController.text = BackendConfig.baseUrl;
    _mlServerUrlController.text = 'http://localhost:5000';
    _saveToBackend = _classifier.saveToBackend;
    _initializeSettings();
  }

  Future<void> _initializeSettings() async {
    await _loadDummyToggles();
    _checkBackendStatus();
    _checkAudioModelStatus();
    await _ipService.load();
    if (mounted) setState(() {});
  }

  Future<void> _checkAudioModelStatus() async {
    try {
      final mlUrl = _mlServerUrlController.text.trim();
      print('[Settings] Checking audio model status at: $mlUrl/audio/model');
      final resp = await http
          .get(Uri.parse('$mlUrl/audio/model'))
          .timeout(const Duration(seconds: 5));
      print('[Settings] Response status: ${resp.statusCode}');
      if (resp.statusCode == 200 && mounted) {
        final data = json.decode(resp.body);
        print('[Settings] Audio model data: $data');
        setState(() {
          _audioModelType = data['currentModel'] ?? 'cnn14';
          _passtAvailable = data['passtAvailable'] ?? false;
        });
        print('[Settings] PaSST available: $_passtAvailable, current model: $_audioModelType');
      }
    } catch (e) {
      print('[Settings] Failed to check audio model status: $e');
      // ML server not available, will use saved preference
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _audioModelType = prefs.getString('audio_model_type') ?? 'cnn14';
          // Don't change _passtAvailable here - keep it false if we can't reach server
        });
      }
    }
  }

  Future<void> _switchAudioModel(String modelType) async {
    if (_isLoadingAudioModel) return;
    setState(() => _isLoadingAudioModel = true);

    try {
      final mlUrl = _mlServerUrlController.text.trim();
      final resp = await http
          .post(
            Uri.parse('$mlUrl/audio/model/switch'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'model_type': modelType}),
          )
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200 && mounted) {
        final data = json.decode(resp.body);
        if (data['success'] == true) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('audio_model_type', modelType);
          setState(() {
            _audioModelType = modelType;
          });
          showGlassSnackBar(
            context,
            'Audio model switched to ${modelType.toUpperCase()}',
          );
        } else {
          showGlassSnackBar(
            context,
            'Failed: ${data['error']}',
            isError: true,
          );
        }
      } else if (mounted) {
        showGlassSnackBar(
          context,
          'Server error: ${resp.statusCode}',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, 'Error: $e', isError: true);
      }
    }

    if (mounted) setState(() => _isLoadingAudioModel = false);
  }

  // load data
  Future<void> _loadDummyToggles() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      final savedBackendUrl = prefs.getString('backend_url');
      final savedMlServerUrl = prefs.getString('ml_server_url');
      if (savedBackendUrl != null && savedBackendUrl.isNotEmpty) {
        _backendUrlController.text = savedBackendUrl;
        BackendConfig.setBaseUrl(savedBackendUrl);
      }
      if (savedMlServerUrl != null && savedMlServerUrl.isNotEmpty) {
        _mlServerUrlController.text = savedMlServerUrl;
        _classifier.setApiUrl(savedMlServerUrl);
      }
      _showDummyMapEvents = prefs.getBool('show_dummy_map_events') ?? false;
      _showDummyAudioData = prefs.getBool('show_dummy_audio_data') ?? false;
      _showDummyVideoData = prefs.getBool('show_dummy_video_data') ?? false;
      _showDummyFusionData = prefs.getBool('show_dummy_fusion_data') ?? false;
      _showFullPredictionDetails =
          prefs.getBool('show_full_prediction_details') ?? true;
      _enableMotionFallback = prefs.getBool('enable_motion_fallback') ?? false;
      _enableLaptopMic = prefs.getBool('enable_laptop_mic') ?? true;
      _enableLaptopCamera = prefs.getBool('enable_laptop_camera') ?? true;
      _showDetectedEventsOnMap =
          prefs.getBool('show_detected_events_on_map') ?? true;
      _defaultMapProvider = prefs.getString('default_map_provider') ?? 'osm';
      _savedLat = prefs.getDouble('user_location_lat');
      _savedLng = prefs.getDouble('user_location_lng');
      _locationIpController.text = prefs.getString('my_location_ip') ?? '';
      if (_savedLat != null)
        _latController.text = _savedLat!.toStringAsFixed(6);
      if (_savedLng != null)
        _lngController.text = _savedLng!.toStringAsFixed(6);
    });
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    _mlServerUrlController.dispose();
    super.dispose();
  }

  Future<void> _geolocateFromIp() async {
    final ip = _locationIpController.text.trim();
    if (ip.isEmpty) {
      showGlassSnackBar(context, 'Please enter an IP address first');
      return;
    }
    setState(() => _resolvingLocation = true);
    try {
      final backendUrl = _backendUrlController.text.trim();
      final resp = await http
          .get(
            Uri.parse('$backendUrl/locations/geolocate/${ip.split(':').first}'),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data['success'] == true) {
          final d = data['data'];
          final lat = (d['latitude'] as num).toDouble();
          final lng = (d['longitude'] as num).toDouble();
          if (lat != 0 || lng != 0) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setDouble('user_location_lat', lat);
            await prefs.setDouble('user_location_lng', lng);
            await prefs.setString('my_location_ip', ip);
            setState(() {
              _savedLat = lat;
              _savedLng = lng;
              _latController.text = lat.toStringAsFixed(6);
              _lngController.text = lng.toStringAsFixed(6);
            });
            if (mounted) {
              showGlassSnackBar(
                context,
                'Location resolved: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
              );
            }
          } else {
            showGlassSnackBar(
              context,
              'Could not resolve location for this IP',
            );
          }
        } else {
          showGlassSnackBar(
            context,
            'Geolocate failed: ${data['message'] ?? 'unknown'}',
          );
        }
      } else {
        final isPrivate = ip.startsWith('192.168.') ||
            ip.startsWith('10.') ||
            ip.startsWith('172.16.') ||
            ip.startsWith('172.17.') ||
            ip.startsWith('172.18.') ||
            ip.startsWith('172.19.') ||
            ip.startsWith('172.2') ||
            ip.startsWith('172.30.') ||
            ip.startsWith('172.31.');
        if (isPrivate) {
          showGlassSnackBar(
            context,
            'Private IPs (192.168.x.x, 10.x.x.x) cannot be geolocated. Use a public IP.',
            isError: true,
          );
        } else {
          showGlassSnackBar(context, 'Backend returned ${resp.statusCode}',
              isError: true);
        }
      }
    } catch (e) {
      showGlassSnackBar(context, 'Error: $e');
    }
    if (mounted) setState(() => _resolvingLocation = false);
  }

  // save data
  Future<void> _saveManualCoordinates() async {
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());
    if (lat == null || lng == null) {
      showGlassSnackBar(context, 'Enter valid latitude and longitude');
      return;
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      showGlassSnackBar(context, 'Coordinates out of range');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('user_location_lat', lat);
    await prefs.setDouble('user_location_lng', lng);
    setState(() {
      _savedLat = lat;
      _savedLng = lng;
    });
    if (mounted) {
      showGlassSnackBar(
        context,
        'Location saved: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
      );
    }
  }

  // check state
  Future<void> _checkBackendStatus() async {
    setState(() {
      _isCheckingBackend = true;
      _backendAvailable = null;
    });

    try {
      final isAvailable = await BackendConfig.isAvailable();
      Map<String, dynamic>? apiInfo;

      if (isAvailable) {
        final backend = BackendApiService();
        apiInfo = await backend.getApiInfo();
      }

      setState(() {
        _backendAvailable = isAvailable;
        _apiInfo = apiInfo;
        _isCheckingBackend = false;
      });
    } catch (e) {
      setState(() {
        _backendAvailable = false;
        _isCheckingBackend = false;
      });
    }
  }

  // save data
  void _saveSettings() {
    final backendUrl = _backendUrlController.text.trim();
    final mlUrl = _mlServerUrlController.text.trim();

    if (backendUrl.isNotEmpty) {
      BackendConfig.setBaseUrl(backendUrl);
    }
    if (mlUrl.isNotEmpty) {
      _classifier.setApiUrl(mlUrl);
    }

    _classifier.saveToBackend = _saveToBackend;

    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('backend_url', backendUrl);
      prefs.setString('ml_server_url', mlUrl);
      prefs.setBool('show_dummy_map_events', _showDummyMapEvents);
      prefs.setBool('show_dummy_audio_data', _showDummyAudioData);
      prefs.setBool('show_dummy_video_data', _showDummyVideoData);
      prefs.setBool('show_dummy_fusion_data', _showDummyFusionData);
      prefs.setBool('enable_motion_fallback', _enableMotionFallback);
      prefs.setBool('show_detected_events_on_map', _showDetectedEventsOnMap);
    });

    showGlassSnackBar(context, 'Settings saved');

    _checkBackendStatus();
  }

  // build ui section
  Widget _buildDeviceIpTile(
    DeviceIp device,
    ColorScheme scheme,
    bool isDark,
    int index,
  ) {
    final typeIcon = switch (device.type) {
      'droidcam' => Icons.android_rounded,
      'ipwebcam' => Icons.videocam_rounded,
      'rtsp' => Icons.cast_connected_rounded,
      _ => Icons.device_hub_rounded,
    };
    final typeLabel = switch (device.type) {
      'droidcam' => 'DroidCam',
      'ipwebcam' => 'IP Webcam',
      'rtsp' => 'RTSP',
      _ => 'Custom',
    };

    return Container(
      margin: EdgeInsets.only(top: index == 0 ? 0 : 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(typeIcon, color: scheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  device.address,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  typeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.primary.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (device.hasLocation)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(Icons.gps_fixed_rounded,
                            size: 10, color: Colors.green.shade600),
                        const SizedBox(width: 3),
                        Text(
                          '${device.latitude!.toStringAsFixed(4)}, ${device.longitude!.toStringAsFixed(4)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green.shade700,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 4,
                    children: [
                      for (final mod in device.supportedModalities)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: switch (mod) {
                              'video' => Colors.blue,
                              'audio' => Colors.orange,
                              'fusion' => Colors.purple,
                              _ => Colors.grey,
                            }
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            mod,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: switch (mod) {
                                'video' => Colors.blue.shade700,
                                'audio' => Colors.orange.shade700,
                                'fusion' => Colors.purple.shade700,
                                _ => Colors.grey.shade700,
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () =>
                _showAddEditIpDialog(context, scheme, isDark, existing: device),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.edit_rounded,
                size: 18,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _showDeleteIpDialog(context, scheme, device),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: Colors.redAccent.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // show dialog or ui
  void _showDeleteIpDialog(
    BuildContext context,
    ColorScheme scheme,
    DeviceIp device,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Device'),
        content: Text(
          'Remove "${device.label}" (${device.address}) from saved IPs?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _ipService.removeDevice(device.id);
              setState(() {});
              Navigator.pop(ctx);
              showGlassSnackBar(context, '${device.label} removed');
            },
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  // show dialog or ui
  void _showAddEditIpDialog(
    BuildContext context,
    ColorScheme scheme,
    bool isDark, {
    DeviceIp? existing,
  }) {
    final isEdit = existing != null;
    final labelCtrl = TextEditingController(text: isEdit ? existing.label : '');
    final addressCtrl = TextEditingController(
      text: isEdit ? existing.address : '',
    );
    final latCtrl = TextEditingController(
      text: isEdit && existing.latitude != null
          ? existing.latitude!.toStringAsFixed(6)
          : '',
    );
    final lngCtrl = TextEditingController(
      text: isEdit && existing.longitude != null
          ? existing.longitude!.toStringAsFixed(6)
          : '',
    );
    String selectedType = isEdit ? existing.type : 'droidcam';
    bool fetchingGps = false;
    List<String> selectedModalities = isEdit
        ? List<String>.from(existing.supportedModalities)
        : DeviceIp.defaultModalities('droidcam');

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: GlassContainer(
            padding: const EdgeInsets.all(28),
            borderRadius: BorderRadius.circular(28),
            blur: 20,
            opacity: 0.18,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEdit ? 'Edit Device' : 'Add Device',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: labelCtrl,
                    decoration: InputDecoration(
                      hintText: isEdit
                          ? 'e.g. Living Room Camera'
                          : 'Device Name (Optional)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.5),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      prefixIcon: const Icon(Icons.label_outline_rounded),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: addressCtrl,
                    decoration: InputDecoration(
                      hintText: StreamUrlFormatter.exampleForType(selectedType),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.5),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      prefixIcon: const Icon(Icons.lan_rounded),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.9),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    StreamUrlFormatter.portDescription(selectedType),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.devices_other_rounded,
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButton<String>(
                            value: selectedType,
                            isExpanded: true,
                            underline: const SizedBox(),
                            itemHeight: 64,
                            dropdownColor: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            elevation: 8,
                            icon: const Icon(Icons.expand_more_rounded),
                            items: [
                              {
                                'value': 'droidcam',
                                'label': 'DroidCam',
                                'description': 'Stream via DroidCam app',
                              },
                              {
                                'value': 'ipwebcam',
                                'label': 'IP Webcam',
                                'description': 'Stream via IP Webcam app',
                              },
                              {
                                'value': 'rtsp',
                                'label': 'RTSP Camera',
                                'description': 'Real-time streaming protocol',
                              },
                              {
                                'value': 'custom',
                                'label': 'Custom URL',
                                'description': 'Custom video stream URL',
                              },
                            ].map((device) {
                              final isSelected =
                                  device['value'] == selectedType;
                              return DropdownMenuItem<String>(
                                value: device['value'],
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  decoration: isSelected
                                      ? BoxDecoration(
                                          border: Border(
                                            left: BorderSide(
                                              color: scheme.primary
                                                  .withValues(alpha: 0.6),
                                              width: 2.5,
                                            ),
                                          ),
                                        )
                                      : null,
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: isSelected ? 10 : 0,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          device['label']!,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: scheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          device['description']!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: scheme.onSurface
                                                .withValues(alpha: 0.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (v) => setDialogState(() {
                              selectedType = v!;
                              selectedModalities =
                                  DeviceIp.defaultModalities(v);
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Supported Modalities',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select which testing modes this device supports',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final mod in ['video', 'audio', 'fusion'])
                        FilterChip(
                          label: Text(
                            mod[0].toUpperCase() + mod.substring(1),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: selectedModalities.contains(mod)
                                  ? scheme.onPrimary
                                  : scheme.onSurface,
                            ),
                          ),
                          selected: selectedModalities.contains(mod),
                          selectedColor: scheme.primary,
                          checkmarkColor: scheme.onPrimary,
                          backgroundColor:
                              scheme.onSurface.withValues(alpha: 0.06),
                          side: BorderSide(
                            color: selectedModalities.contains(mod)
                                ? scheme.primary
                                : scheme.outline.withValues(alpha: 0.3),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          onSelected: (selected) {
                            setDialogState(() {
                              if (selected) {
                                selectedModalities.add(mod);
                              } else {
                                selectedModalities.remove(mod);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Device Location (GPS)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: latCtrl,
                          decoration: InputDecoration(
                            hintText: 'Latitude',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: scheme.outline.withValues(alpha: 0.5),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: scheme.outline.withValues(alpha: 0.3),
                              ),
                            ),
                            prefixIcon:
                                const Icon(Icons.north_rounded, size: 18),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.9),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: lngCtrl,
                          decoration: InputDecoration(
                            hintText: 'Longitude',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: scheme.outline.withValues(alpha: 0.5),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: scheme.outline.withValues(alpha: 0.3),
                              ),
                            ),
                            prefixIcon:
                                const Icon(Icons.east_rounded, size: 18),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.9),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: fetchingGps
                          ? null
                          : () async {
                              setDialogState(() => fetchingGps = true);
                              try {
                                LocationPermission perm =
                                    await Geolocator.checkPermission();
                                if (perm == LocationPermission.denied) {
                                  perm = await Geolocator.requestPermission();
                                }
                                if (perm == LocationPermission.denied ||
                                    perm == LocationPermission.deniedForever) {
                                  if (context.mounted) {
                                    showGlassSnackBar(
                                      context,
                                      'Location permission denied',
                                      isError: true,
                                    );
                                  }
                                  return;
                                }
                                final pos = await Geolocator.getCurrentPosition(
                                  locationSettings: const LocationSettings(
                                    accuracy: LocationAccuracy.high,
                                    timeLimit: Duration(seconds: 15),
                                  ),
                                );
                                setDialogState(() {
                                  latCtrl.text =
                                      pos.latitude.toStringAsFixed(6);
                                  lngCtrl.text =
                                      pos.longitude.toStringAsFixed(6);
                                });
                              } catch (e) {
                                if (context.mounted) {
                                  showGlassSnackBar(
                                    context,
                                    'GPS failed: $e',
                                    isError: true,
                                  );
                                }
                              } finally {
                                setDialogState(() => fetchingGps = false);
                              }
                            },
                      icon: fetchingGps
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.gps_fixed_rounded,
                              size: 16, color: scheme.primary),
                      label: Text(
                        fetchingGps
                            ? 'Getting GPS...'
                            : 'Use current GPS location',
                        style: TextStyle(
                          fontSize: 12,
                          color: fetchingGps ? scheme.outline : scheme.primary,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        side: BorderSide(
                          color: scheme.primary.withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: scheme.outline),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 12,
                          ),
                        ),
                        onPressed: () {
                          var label = labelCtrl.text.trim();
                          final address = addressCtrl.text.trim();

                          if (address.isEmpty) {
                            showGlassSnackBar(
                              context,
                              'IP address is required',
                              isError: true,
                            );
                            return;
                          }

                          if (label.isEmpty && !isEdit) {
                            final nextNumber = _ipService.devices.length + 1;
                            label = 'Device $nextNumber';
                          }

                          final lat = double.tryParse(latCtrl.text.trim());
                          final lng = double.tryParse(lngCtrl.text.trim());

                          if (isEdit) {
                            _ipService.updateDevice(
                              existing.copyWith(
                                label: label,
                                address: address,
                                type: selectedType,
                                latitude: lat,
                                longitude: lng,
                                supportedModalities: selectedModalities,
                              ),
                            );
                          } else {
                            _ipService.addDevice(
                              DeviceIp(
                                id: DateTime.now().toString(),
                                label: label,
                                address: address,
                                type: selectedType,
                                latitude: lat,
                                longitude: lng,
                                supportedModalities: selectedModalities,
                              ),
                            );
                          }
                          setState(() {});
                          Navigator.pop(ctx);
                          showGlassSnackBar(
                            context,
                            isEdit ? '$label updated' : '$label added',
                          );
                        },
                        child: Text(isEdit ? 'Update' : 'Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        children: [
          BackgroundBlobs(isDark: isDark),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _GlassNavbar(onSave: _saveSettings),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GlassContainer(
                          opacity: 0.1,
                          padding: const EdgeInsets.all(20),
                          borderRadius: BorderRadius.circular(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.cloud_rounded,
                                    color: scheme.primary,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Backend Status',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_isCheckingBackend)
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: scheme.primary,
                                      ),
                                    )
                                  else
                                    IconButton(
                                      icon: const Icon(Icons.refresh_rounded),
                                      onPressed: _checkBackendStatus,
                                      color: scheme.primary,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _backendAvailable == null
                                          ? Colors.grey
                                          : _backendAvailable!
                                              ? Colors.green
                                              : Colors.red,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _backendAvailable == null
                                        ? 'Checking...'
                                        : _backendAvailable!
                                            ? 'Connected'
                                            : 'Disconnected',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              if (_apiInfo != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'Version: ${_apiInfo!['version'] ?? 'Unknown'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        GlassContainer(
                          opacity: 0.1,
                          padding: const EdgeInsets.all(20),
                          borderRadius: BorderRadius.circular(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.dns_rounded,
                                    color: scheme.primary,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Server Configuration',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Backend API URL',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _backendUrlController,
                                decoration: InputDecoration(
                                  hintText: 'http://localhost:3000',
                                  filled: true,
                                  fillColor: scheme.surface.withValues(
                                    alpha: 0.5,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'ML Server URL',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _mlServerUrlController,
                                decoration: InputDecoration(
                                  hintText: 'http://localhost:5000',
                                  filled: true,
                                  fillColor: scheme.surface.withValues(
                                    alpha: 0.5,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        GlassContainer(
                          opacity: 0.1,
                          padding: const EdgeInsets.all(20),
                          borderRadius: BorderRadius.circular(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.settings_rounded,
                                    color: scheme.primary,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Options',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SwitchListTile(
                                value: _saveToBackend,
                                onChanged: (value) {
                                  setState(() => _saveToBackend = value);
                                },
                                title: Text(
                                  'Save results to backend',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                subtitle: Text(
                                  'Store classification results in MongoDB',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              Divider(
                                color: scheme.onSurface.withValues(alpha: 0.08),
                              ),
                              SwitchListTile(
                                value: _enableMotionFallback,
                                onChanged: (value) {
                                  setState(() => _enableMotionFallback = value);
                                },
                                title: Text(
                                  'Enable motion fallback',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                subtitle: Text(
                                  'When disabled, stream events use detector output only',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        GlassContainer(
                          opacity: 0.1,
                          padding: const EdgeInsets.all(20),
                          borderRadius: BorderRadius.circular(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.science_rounded,
                                    color: scheme.primary,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Dummy Data',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Enable test data for each section when no live data is available',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SwitchListTile(
                                value: _showDummyMapEvents,
                                onChanged: (v) {
                                  setState(() => _showDummyMapEvents = v);
                                  SharedPreferences.getInstance().then(
                                    (p) =>
                                        p.setBool('show_dummy_map_events', v),
                                  );
                                },
                                title: Text(
                                  'Map event pins',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                subtitle: Text(
                                  'Show dummy event markers on the map',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                secondary: Icon(
                                  Icons.map_rounded,
                                  color: Colors.orange.withValues(alpha: 0.8),
                                  size: 22,
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              Divider(
                                color: scheme.onSurface.withValues(alpha: 0.08),
                              ),
                              SwitchListTile(
                                value: _showDummyAudioData,
                                onChanged: (v) {
                                  setState(() => _showDummyAudioData = v);
                                  SharedPreferences.getInstance().then(
                                    (p) =>
                                        p.setBool('show_dummy_audio_data', v),
                                  );
                                },
                                title: Text(
                                  'Audio classification',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                subtitle: Text(
                                  'Show dummy audio tagging results',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                secondary: Icon(
                                  Icons.audiotrack_rounded,
                                  color: Colors.cyan.withValues(alpha: 0.8),
                                  size: 22,
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              Divider(
                                color: scheme.onSurface.withValues(alpha: 0.08),
                              ),
                              SwitchListTile(
                                value: _showDummyVideoData,
                                onChanged: (v) {
                                  setState(() => _showDummyVideoData = v);
                                  SharedPreferences.getInstance().then(
                                    (p) =>
                                        p.setBool('show_dummy_video_data', v),
                                  );
                                },
                                title: Text(
                                  'Video classification',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                subtitle: Text(
                                  'Show dummy video tagging results',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                secondary: Icon(
                                  Icons.videocam_rounded,
                                  color: Colors.purple.withValues(alpha: 0.8),
                                  size: 22,
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              Divider(
                                color: scheme.onSurface.withValues(alpha: 0.08),
                              ),
                              SwitchListTile(
                                value: _showDummyFusionData,
                                onChanged: (v) {
                                  setState(() => _showDummyFusionData = v);
                                  SharedPreferences.getInstance().then(
                                    (p) =>
                                        p.setBool('show_dummy_fusion_data', v),
                                  );
                                },
                                title: Text(
                                  'Late fusion layer',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                subtitle: Text(
                                  'Show dummy fusion results',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                secondary: Icon(
                                  Icons.merge_type_rounded,
                                  color: Colors.teal.withValues(alpha: 0.8),
                                  size: 22,
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        GlassContainer(
                          opacity: 0.1,
                          padding: const EdgeInsets.all(20),
                          borderRadius: BorderRadius.circular(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.laptop_rounded,
                                    color: scheme.primary,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Local Hardware',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Use your device\'s built-in microphone and camera for testing',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SwitchListTile(
                                value: _enableLaptopMic,
                                onChanged: (v) {
                                  setState(() => _enableLaptopMic = v);
                                  SharedPreferences.getInstance().then(
                                    (p) => p.setBool('enable_laptop_mic', v),
                                  );
                                },
                                title: Text(
                                  'Laptop Microphone',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                subtitle: Text(
                                  'Use device mic for audio testing',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                secondary: Icon(
                                  Icons.mic_rounded,
                                  color: Colors.blue.withValues(alpha: 0.8),
                                  size: 22,
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              Divider(
                                color: scheme.onSurface.withValues(alpha: 0.08),
                              ),
                              SwitchListTile(
                                value: _enableLaptopCamera,
                                onChanged: (v) {
                                  setState(() => _enableLaptopCamera = v);
                                  SharedPreferences.getInstance().then(
                                    (p) => p.setBool('enable_laptop_camera', v),
                                  );
                                },
                                title: Text(
                                  'Laptop Camera',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                subtitle: Text(
                                  'Use device camera for video testing',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                secondary: Icon(
                                  Icons.videocam_rounded,
                                  color: Colors.green.withValues(alpha: 0.8),
                                  size: 22,
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Audio Model Selection Section
                        GlassContainer(
                          opacity: 0.1,
                          padding: const EdgeInsets.all(20),
                          borderRadius: BorderRadius.circular(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.graphic_eq_rounded,
                                    color: Colors.deepPurple,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Audio Model',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_isLoadingAudioModel)
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: scheme.primary,
                                      ),
                                    )
                                  else
                                    IconButton(
                                      icon: Icon(
                                        Icons.refresh_rounded,
                                        size: 20,
                                        color: scheme.onSurface.withValues(alpha: 0.6),
                                      ),
                                      tooltip: 'Refresh audio model status',
                                      onPressed: _checkAudioModelStatus,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Select the audio classification model for scene detection',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // CNN14 Option
                              _buildModelOption(
                                scheme: scheme,
                                title: 'CNN14',
                                subtitle: 'Convolutional Neural Network (66.8% accuracy)',
                                isSelected: _audioModelType == 'cnn14',
                                isAvailable: true,
                                icon: Icons.memory_rounded,
                                color: Colors.blue,
                                onTap: () => _switchAudioModel('cnn14'),
                              ),
                              const SizedBox(height: 12),
                              // PaSST Option
                              _buildModelOption(
                                scheme: scheme,
                                title: 'PaSST',
                                subtitle: 'Patchout Spectrogram Transformer (88.13% accuracy)',
                                isSelected: _audioModelType == 'passt',
                                isAvailable: _passtAvailable,
                                icon: Icons.auto_awesome_rounded,
                                color: Colors.deepPurple,
                                onTap: _passtAvailable
                                    ? () => _switchAudioModel('passt')
                                    : null,
                              ),
                              if (!_passtAvailable) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'PaSST requires hear21passt library (pip install hear21passt)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange.withValues(alpha: 0.8),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        GlassContainer(
                          opacity: 0.1,
                          padding: const EdgeInsets.all(20),
                          borderRadius: BorderRadius.circular(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.analytics_rounded,
                                    color: scheme.primary,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'History Details',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Control how much detail is shown in detection history',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SwitchListTile(
                                value: _showFullPredictionDetails,
                                onChanged: (v) {
                                  setState(
                                      () => _showFullPredictionDetails = v);
                                  SharedPreferences.getInstance().then(
                                    (p) => p.setBool(
                                        'show_full_prediction_details', v),
                                  );
                                },
                                title: Text(
                                  'Full prediction details',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                subtitle: Text(
                                  _showFullPredictionDetails
                                      ? 'Showing top-5 classes, severity, event tags & multi-scene labels'
                                      : 'Showing only the primary generated class',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                secondary: Icon(
                                  _showFullPredictionDetails
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  color: Colors.indigo.withValues(alpha: 0.8),
                                  size: 22,
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        GlassContainer(
                          opacity: 0.1,
                          padding: const EdgeInsets.all(20),
                          borderRadius: BorderRadius.circular(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.map_rounded,
                                    color: scheme.primary,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Map Settings',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Configure default map appearance and provider',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white.withOpacity(
                                        isDark ? 0.10 : 0.55,
                                      ),
                                      Colors.white.withOpacity(
                                        isDark ? 0.05 : 0.30,
                                      ),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(
                                      isDark ? 0.15 : 0.45,
                                    ),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(
                                        isDark ? 0.15 : 0.06,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Default Map Provider',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.onSurface.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    DropdownButton<String>(
                                      value: _defaultMapProvider,
                                      isExpanded: true,
                                      underline: const SizedBox(),
                                      itemHeight: 56,
                                      dropdownColor: isDark
                                          ? Color.lerp(
                                              scheme.surface,
                                              Colors.white,
                                              0.08,
                                            )
                                          : Color.lerp(
                                              Colors.white,
                                              scheme.surface,
                                              0.03,
                                            ),
                                      borderRadius: BorderRadius.circular(16),
                                      elevation: 8,
                                      items: const [
                                        {
                                          'value': 'osm',
                                          'label': 'OpenStreetMap',
                                          'description':
                                              'Open-source community map tiles',
                                        },
                                        {
                                          'value': 'google',
                                          'label': 'Google Maps',
                                          'description':
                                              'Google satellite and road mapping',
                                        },
                                      ].map((provider) {
                                        final isSelected = provider['value'] ==
                                            _defaultMapProvider;
                                        return DropdownMenuItem<String>(
                                          value: provider['value'],
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            decoration: isSelected
                                                ? BoxDecoration(
                                                    border: Border(
                                                      left: BorderSide(
                                                        color:
                                                            (provider['value'] ==
                                                                        'google'
                                                                    ? Colors
                                                                        .blue
                                                                    : Colors
                                                                        .indigo)
                                                                .withOpacity(
                                                          0.7,
                                                        ),
                                                        width: 2.5,
                                                      ),
                                                    ),
                                                  )
                                                : null,
                                            child: Padding(
                                              padding: EdgeInsets.only(
                                                left: isSelected ? 10 : 0,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    provider['label']!,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 14,
                                                      color: scheme.onSurface,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    provider['description']!,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: scheme.onSurface
                                                          .withValues(
                                                        alpha: 0.5,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (value) {
                                        if (value != null) {
                                          setState(
                                            () => _defaultMapProvider = value,
                                          );
                                          SharedPreferences.getInstance().then(
                                            (p) => p.setString(
                                              'default_map_provider',
                                              value,
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white.withOpacity(
                                        isDark ? 0.10 : 0.55,
                                      ),
                                      Colors.white.withOpacity(
                                        isDark ? 0.05 : 0.30,
                                      ),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(
                                      isDark ? 0.15 : 0.45,
                                    ),
                                    width: 1.2,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.dark_mode_rounded,
                                      color: scheme.primary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Dark Map Tiles',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: scheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Use dark-themed map tiles when available',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color:
                                                  scheme.onSurface.withValues(
                                                alpha: 0.6,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    FutureBuilder<SharedPreferences>(
                                      future: SharedPreferences.getInstance(),
                                      builder: (ctx, snapshot) {
                                        final enabled = snapshot.data?.getBool(
                                                'enable_dark_map_tiles') ??
                                            false;
                                        return Switch(
                                          value: enabled,
                                          activeColor: scheme.primary,
                                          onChanged: (value) async {
                                            final prefs =
                                                await SharedPreferences
                                                    .getInstance();
                                            await prefs.setBool(
                                                'enable_dark_map_tiles', value);
                                            setState(() {});
                                          },
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white.withOpacity(
                                        isDark ? 0.10 : 0.55,
                                      ),
                                      Colors.white.withOpacity(
                                        isDark ? 0.05 : 0.30,
                                      ),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(
                                      isDark ? 0.15 : 0.45,
                                    ),
                                    width: 1.2,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.pin_drop_rounded,
                                      color: Colors.orange,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Show Detected Events on Map',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: scheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Display events detected from audio/video testing as pins on the Event Map',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color:
                                                  scheme.onSurface.withValues(
                                                alpha: 0.6,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: _showDetectedEventsOnMap,
                                      activeColor: scheme.primary,
                                      onChanged: (value) {
                                        setState(() =>
                                            _showDetectedEventsOnMap = value);
                                        SharedPreferences.getInstance().then(
                                          (p) => p.setBool(
                                              'show_detected_events_on_map',
                                              value),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              Divider(
                                color: scheme.onSurface.withValues(alpha: 0.12),
                                height: 1,
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Icon(
                                    Icons.my_location_rounded,
                                    color: Colors.teal,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'My Location (Navigation Origin)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Set your location via IP geolocation or manual coordinates for map navigation',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white.withOpacity(
                                        isDark ? 0.10 : 0.55,
                                      ),
                                      Colors.white.withOpacity(
                                        isDark ? 0.05 : 0.30,
                                      ),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(
                                      isDark ? 0.15 : 0.45,
                                    ),
                                    width: 1.2,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.language_rounded,
                                      color: Colors.teal.withOpacity(0.7),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextField(
                                        controller: _locationIpController,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: scheme.onSurface,
                                        ),
                                        decoration: InputDecoration(
                                          hintText:
                                              'Enter IP address (e.g. 203.99.44.1)',
                                          hintStyle: TextStyle(
                                            fontSize: 13,
                                            color: scheme.onSurface.withValues(
                                              alpha: 0.4,
                                            ),
                                          ),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                        ),
                                        keyboardType: TextInputType.url,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      height: 34,
                                      child: ElevatedButton.icon(
                                        onPressed: _resolvingLocation
                                            ? null
                                            : _geolocateFromIp,
                                        icon: _resolvingLocation
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.search_rounded,
                                                size: 16,
                                              ),
                                        label: Text(
                                          _resolvingLocation
                                              ? 'Locating...'
                                              : 'Locate',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.teal,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          elevation: 0,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Colors.white.withOpacity(
                                              isDark ? 0.10 : 0.55,
                                            ),
                                            Colors.white.withOpacity(
                                              isDark ? 0.05 : 0.30,
                                            ),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(
                                            isDark ? 0.15 : 0.45,
                                          ),
                                          width: 1.2,
                                        ),
                                      ),
                                      child: TextField(
                                        controller: _latController,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: scheme.onSurface,
                                        ),
                                        decoration: InputDecoration(
                                          labelText: 'Latitude',
                                          labelStyle: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurface.withValues(
                                              alpha: 0.5,
                                            ),
                                          ),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                        ),
                                        keyboardType: const TextInputType
                                            .numberWithOptions(
                                          decimal: true,
                                          signed: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Colors.white.withOpacity(
                                              isDark ? 0.10 : 0.55,
                                            ),
                                            Colors.white.withOpacity(
                                              isDark ? 0.05 : 0.30,
                                            ),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(
                                            isDark ? 0.15 : 0.45,
                                          ),
                                          width: 1.2,
                                        ),
                                      ),
                                      child: TextField(
                                        controller: _lngController,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: scheme.onSurface,
                                        ),
                                        decoration: InputDecoration(
                                          labelText: 'Longitude',
                                          labelStyle: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurface.withValues(
                                              alpha: 0.5,
                                            ),
                                          ),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                        ),
                                        keyboardType: const TextInputType
                                            .numberWithOptions(
                                          decimal: true,
                                          signed: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    height: 38,
                                    child: ElevatedButton(
                                      onPressed: _saveManualCoordinates,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            Colors.teal.withOpacity(0.9),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: const Text(
                                        'Save',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_savedLat != null && _savedLng != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.teal.withValues(
                                        alpha: 0.25,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        color: Colors.teal,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Current location: ${_savedLat!.toStringAsFixed(4)}, ${_savedLng!.toStringAsFixed(4)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.teal.shade700,
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () async {
                                          final prefs = await SharedPreferences
                                              .getInstance();
                                          await prefs.remove(
                                            'user_location_lat',
                                          );
                                          await prefs.remove(
                                            'user_location_lng',
                                          );
                                          setState(() {
                                            _savedLat = null;
                                            _savedLng = null;
                                            _latController.clear();
                                            _lngController.clear();
                                          });
                                          showGlassSnackBar(
                                            context,
                                            'Location cleared',
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(6),
                                        child: Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 16,
                                            color: Colors.teal.withOpacity(0.6),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        GlassContainer(
                          opacity: 0.1,
                          padding: const EdgeInsets.all(20),
                          borderRadius: BorderRadius.circular(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.wifi_tethering_rounded,
                                    color: scheme.primary,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Device IP Addresses',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => _showAddEditIpDialog(
                                      context,
                                      scheme,
                                      isDark,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.primary,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.add_rounded,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Add',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Manage device IPs for streaming in audio/video screens',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (_ipService.devices.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.04,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: scheme.onSurface.withValues(
                                        alpha: 0.08,
                                      ),
                                    ),
                                  ),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.devices_other_rounded,
                                          size: 36,
                                          color: scheme.onSurface.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'No devices added yet',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: scheme.onSurface.withValues(
                                              alpha: 0.5,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Tap "Add" to save a device IP',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: scheme.onSurface.withValues(
                                              alpha: 0.35,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                ...List.generate(_ipService.devices.length, (
                                  i,
                                ) {
                                  final device = _ipService.devices[i];
                                  return _buildDeviceIpTile(
                                    device,
                                    scheme,
                                    isDark,
                                    i,
                                  );
                                }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: GestureDetector(
                            onTap: _saveSettings,
                            child: GlassContainer(
                              opacity: 0.2,
                              borderRadius: BorderRadius.circular(20),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 36,
                                vertical: 16,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          scheme.primary.withValues(alpha: 0.3),
                                          scheme.tertiary.withValues(
                                            alpha: 0.2,
                                          ),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.check_circle_outline_rounded,
                                      color: scheme.primary,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Save Settings',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                      Text(
                                        'Apply configuration changes',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurface.withValues(
                                            alpha: 0.6,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 16),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 16,
                                    color: scheme.primary.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelOption({
    required ColorScheme scheme,
    required String title,
    required String subtitle,
    required bool isSelected,
    required bool isAvailable,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isAvailable && !_isLoadingAudioModel ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.15)
                : scheme.surface.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? color.withValues(alpha: 0.5)
                  : scheme.onSurface.withValues(alpha: 0.1),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isAvailable
                      ? color.withValues(alpha: 0.15)
                      : scheme.onSurface.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: isAvailable ? color : scheme.onSurface.withValues(alpha: 0.4),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isAvailable
                                ? scheme.onSurface
                                : scheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Active',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isAvailable
                            ? scheme.onSurface.withValues(alpha: 0.6)
                            : scheme.onSurface.withValues(alpha: 0.35),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle_rounded,
                  color: color,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassNavbar extends StatelessWidget {
  final VoidCallback onSave;

  const _GlassNavbar({required this.onSave});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.of(context);
    final scheme = Theme.of(context).colorScheme;

    return GlassContainer(
      opacity: 0.16,
      borderRadius: BorderRadius.circular(22),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
            color: scheme.onSurface,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Text(
            'Settings',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(theme.isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: theme.toggleTheme,
          ),
        ],
      ),
    );
  }
}
