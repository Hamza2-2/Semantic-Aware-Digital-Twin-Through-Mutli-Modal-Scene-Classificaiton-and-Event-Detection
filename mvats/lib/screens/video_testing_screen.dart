// Video prediction testing screen
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;

import '../theme/theme_controller.dart';
import '../widgets/glass_container.dart';
import '../widgets/background_blobs.dart';
import '../services/video_classifier_service.dart';
import '../services/prediction_history_service.dart';
import '../services/ip_address_service.dart';
import '../services/event_detection_service.dart';
import '../utils/glass_snackbar.dart';
import '../widgets/duration_slider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show routeObserver;

class VideoTestingScreen extends StatefulWidget {
  const VideoTestingScreen({super.key});

  @override
  State<VideoTestingScreen> createState() => _VideoTestingScreenState();
}

class _VideoTestingScreenState extends State<VideoTestingScreen>
    with RouteAware {
  final VideoClassifierService _classifier = VideoClassifierService();
  final PredictionHistoryService _historyService = PredictionHistoryService();
  final IpAddressService _ipService = IpAddressService();
  final EventDetectionService _eventService = EventDetectionService();

  bool _enableEventDetection = true;
  bool _enableMotionFallback = false;
  EventDetectionResult? _eventResult;
  GeoLocation? _currentLocation;

  String? _selectedFilePath;
  String? _fileName;
  bool _isProcessing = false;
  Map<String, dynamic>? _result;
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _multiLabelMode = false;

  bool _isStreamMode = false;
  bool _isHardwareMode = false;
  bool _laptopCameraEnabled = true;
  final TextEditingController _streamUrlController = TextEditingController();
  int _streamDuration = 5;
  bool _isStreamConnected = false;
  bool _isConnectingStream = false;
  String? _streamError;

  bool get _supportsVideoPreview {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  @override
  void initState() {
    super.initState();
    _ipService.load().then((_) {
      if (mounted) setState(() {});
    });
    _eventService.loadSettings();
    _loadGeolocation();
    _loadHardwarePrefs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPopNext() {
    _loadHardwarePrefs();
  }

  // load data
  Future<void> _loadGeolocation() async {
    final location = await _eventService.getGeolocation();
    if (mounted && location != null) {
      setState(() {
        _currentLocation = location;
      });
    }
  }

  // load data
  Future<void> _loadHardwarePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final cameraEnabled = prefs.getBool('enable_laptop_camera') ?? true;
    final motionFallback = prefs.getBool('enable_motion_fallback') ?? false;
    setState(() {
      _laptopCameraEnabled = cameraEnabled;
      _enableMotionFallback = motionFallback;
      if (_isHardwareMode && !cameraEnabled) {
        _isHardwareMode = false;
      }
    });
  }

  DetectedEvent? _selectStrongestEvent(EventDetectionResult eventResult) {
    if (eventResult.events.isNotEmpty) {
      return eventResult.events.first;
    }
    return eventResult.highestSeverityEvent;
  }

  static const double _busVsMetroBoost = 0.0175;
  static const double _busVsTramBoost = 0.01;

  List<Map<String, dynamic>> _applyBusBoost(List<dynamic> predictions) {
    final list = predictions
        .map((p) => Map<String, dynamic>.from(p as Map))
        .toList();
    final busIdx = list.indexWhere(
        (p) => (p['class'] as String?)?.toLowerCase() == 'bus');
    if (busIdx == -1) return list;
    double boost = 0.0;
    final classes = list
        .map((p) => (p['class'] as String?)?.toLowerCase() ?? '')
        .toSet();
    if (classes.any((c) => c.contains('metro'))) boost += _busVsMetroBoost;
    if (classes.contains('tram')) boost += _busVsTramBoost;
    if (boost > 0) {
      // Calculate sum of all OTHER classes (not bus)
      final otherTotal = list
          .asMap()
          .entries
          .where((e) => e.key != busIdx)
          .map((e) => (e.value['confidence'] as num).toDouble())
          .fold(0.0, (a, b) => a + b);
      // Set bus confidence = 1.0 - sum(others), ensuring total = 100%
      // This way if tram=0.2%, bus shows 99.8%, not 100%
      final oldBusConf = (list[busIdx]['confidence'] as num).toDouble();
      final maxBusConf = 1.0 - otherTotal;
      final boostedBusConf = (oldBusConf + boost).clamp(0.0, maxBusConf);
      list[busIdx] = Map<String, dynamic>.from(list[busIdx]);
      list[busIdx]['confidence'] = boostedBusConf;
    }
    return list;
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _videoController?.dispose();
    _streamUrlController.dispose();
    super.dispose();
  }

  // toggle setting
  void _toggleMode(bool isStream) {
    if (_isStreamMode != isStream || _isHardwareMode) {
      _clearSelection();
      _disconnectStream();
      setState(() {
        _isStreamMode = isStream;
        _isHardwareMode = false;
        _result = null;
      });
    }
  }

  void _setHardwareMode() {
    if (!_isHardwareMode) {
      _clearSelection();
      _disconnectStream();
      setState(() {
        _isHardwareMode = true;
        _isStreamMode = false;
        _result = null;
      });
    }
  }

  String _normalizeStreamUrl(String url) {
    return StreamUrlFormatter.normalize(url);
  }

  Future<void> _connectToStream() async {
    var url = _streamUrlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _streamError = 'Please enter a stream URL';
      });
      return;
    }

    url = _normalizeStreamUrl(url);

    setState(() {
      _isConnectingStream = true;
      _streamError = null;
      _videoInitialized = false;
    });

    try {
      _videoController?.dispose();
      if (_supportsVideoPreview) {
        _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
        await _videoController!.initialize();
        _videoController!.play();
        _videoController!.setLooping(true);
      } else {
        _videoController = null;
      }

      setState(() {
        _isStreamConnected = true;
        _videoInitialized = _supportsVideoPreview;
        _isConnectingStream = false;
      });
    } catch (e) {
      debugPrint('Stream preview not available: $e');
      setState(() {
        _isStreamConnected = true;
        _videoInitialized = false;
        _isConnectingStream = false;
        _streamError = null;
      });
    }
  }

  void _disconnectStream() {
    _videoController?.dispose();
    _videoController = null;
    setState(() {
      _isStreamConnected = false;
      _videoInitialized = false;
      _streamError = null;
    });
  }

  // process data
  Future<void> _processStream() async {
    var url = _streamUrlController.text.trim();
    if (url.isEmpty) return;

    url = _normalizeStreamUrl(url);

    setState(() {
      _isProcessing = true;
      _result = null;
    });

    if (_videoController != null) {
      try {
        await _videoController!.pause();
      } catch (_) {}
      _videoController!.dispose();
      _videoController = null;
      if (mounted) {
        setState(() {
          _videoInitialized = false;
        });
      }
    }

    try {
      Map<String, dynamic> result;
      String? eventType;
      EventDetectionResult? eventResult;

      if (_enableEventDetection && !_multiLabelMode) {
        eventResult = await _runEventDetectionForStream(url);
        if (eventResult == null) {
          setState(() {
            _result = {
              'error': true,
              'message': 'Event detection failed',
            };
          });
          return;
        }

        final strongestEvent = _selectStrongestEvent(eventResult);
        eventType = strongestEvent?.eventType;

        final sceneDetected = eventResult.sceneConfidence >= 0.50;
        result = {
          'type': 'stream',
          'predictedClass': eventResult.sceneClass,
          'confidence': eventResult.sceneConfidence,
          'topPredictions': eventResult.topPredictions,
          if (sceneDetected)
            'eventDetection': {
              'eventsDetected': eventResult.emergencyDetected,
              'events': eventResult.events.map((e) => e.eventType).toList(),
              'eventConfidences': {
                for (var e in eventResult.events) e.eventType: e.confidence
              },
              'highestSeverityEvent': strongestEvent != null
                  ? {
                      'type': strongestEvent.eventType,
                      'confidence': strongestEvent.confidence,
                    }
                  : null,
              'alertLevel': eventResult.alertLevel,
            },
        };

        if (!sceneDetected) {
          eventResult = null;
          eventType = null;
        }
      } else {
        result = await _classifier.classifyStream(
          url,
          durationSeconds: _streamDuration,
          multiLabel: _multiLabelMode,
        );

        final sceneConf = (result['confidence'] as num?) ?? 0;
        if (_enableEventDetection &&
            result['error'] != true &&
            sceneConf >= 0.50) {
          eventResult = await _runEventDetectionForStream(url);
          if (eventResult != null) {
            final strongestEvent = _selectStrongestEvent(eventResult);
            eventType = strongestEvent?.eventType;
            result['eventDetection'] = {
              'eventsDetected': eventResult.emergencyDetected,
              'events': eventResult.events.map((e) => e.eventType).toList(),
              'eventConfidences': {
                for (var e in eventResult.events) e.eventType: e.confidence
              },
              'highestSeverityEvent': strongestEvent != null
                  ? {
                      'type': strongestEvent.eventType,
                      'confidence': strongestEvent.confidence,
                    }
                  : null,
              'alertLevel': eventResult.alertLevel,
            };
          }
        }
      }

      setState(() {
        _result = result;
      });

      final predictionId = await _historyService.saveToHistory(
        type: 'video_stream',
        fileName: 'Live Stream',
        filePath: url,
        result: result,
        source: 'stream',
        streamUrl: url,
        streamDuration: _streamDuration,
        eventType: eventType,
        eventDetectionEnabled: _enableEventDetection,
      );

      if (eventResult != null) {
        await _saveAndNotifyEvent(
          eventResult,
          predictionId: predictionId,
          streamUrl: url,
          sourceType: 'video_stream',
        );
      }
    } catch (e) {
      setState(() {
        _result = {
          'error': true,
          'message': 'Error processing stream: $e',
        };
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // pick file or input
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      _handleFileSelected(file.path!, file.name);
    }
  }

  // handle user action
  Future<void> _handleFileSelected(String path, String name) async {
    setState(() {
      _selectedFilePath = path;
      _fileName = name;
      _result = null;
      _videoInitialized = false;
    });

    _videoController?.dispose();
    if (Platform.isWindows) {
      _videoController = null;
      return;
    }

    _videoController = VideoPlayerController.file(File(path));

    try {
      await _videoController!.initialize();
      if (mounted)
        setState(() {
          _videoInitialized = true;
        });
    } catch (e) {
      _videoController?.dispose();
      _videoController = null;
    }
  }

  // process data
  Future<void> _processVideo() async {
    if (_selectedFilePath == null) return;

    setState(() {
      _isProcessing = true;
      _result = null;
    });

    try {
      final result = await _classifier.classifyVideo(
        _selectedFilePath!,
        multiLabel: _multiLabelMode,
      );

      setState(() {
        _result = result;
      });

      String? eventType;
      EventDetectionResult? eventResult;

      final sceneConf = (result['confidence'] as num?) ?? 0;
      if (_enableEventDetection &&
          result['error'] != true &&
          sceneConf >= 0.50) {
        eventResult = await _runEventDetectionForFile(result);
        if (eventResult != null) {
          final strongestEvent = _selectStrongestEvent(eventResult);
          eventType = strongestEvent?.eventType;

          result['eventDetection'] = {
            'eventsDetected': eventResult.emergencyDetected,
            'events': eventResult.events.map((e) => e.eventType).toList(),
            'eventConfidences': {
              for (var e in eventResult.events) e.eventType: e.confidence
            },
            'highestSeverityEvent': strongestEvent != null
                ? {
                    'type': strongestEvent.eventType,
                    'confidence': strongestEvent.confidence,
                  }
                : null,
            'alertLevel': eventResult.alertLevel,
          };
        }
      }

      final predictionId = await _historyService.saveToHistory(
        type: 'video',
        fileName: _fileName ?? 'Unknown',
        filePath: _selectedFilePath,
        result: result,
        eventType: eventType,
        eventDetectionEnabled: _enableEventDetection,
      );

      if (eventResult != null) {
        await _saveAndNotifyEvent(
          eventResult,
          predictionId: predictionId,
          sourceType: 'video',
        );
      }
    } catch (e) {
      setState(() {
        _result = {
          'error': true,
          'message': 'Error processing video: $e',
        };
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<EventDetectionResult?> _runEventDetectionForStream(
      String streamUrl) async {
    try {
      final eventResult = await _eventService.detectEventsInStream(
        streamUrl,
        duration: _streamDuration,
        confidenceThreshold: 0.005,
        enableMotionFallback: false,
      );

      if (eventResult == null) {
        if (mounted) {
          showGlassSnackBar(context, 'Event detection failed', isError: true);
        }
        return null;
      }

      if (mounted) {
        setState(() {
          _eventResult = eventResult;
        });
      }

      return eventResult;
    } catch (e) {
      debugPrint('[VideoTesting] Stream event detection failed: $e');
      return null;
    }
  }

  Future<EventDetectionResult?> _runEventDetectionForFile(
      Map<String, dynamic> result) async {
    if (_selectedFilePath == null) return null;

    try {
      final eventResult = await _eventService.detectEventsInVideo(
        _selectedFilePath!,
        enableAvSlowFast: true,
        confidenceThreshold: 0.005,
        enableMotionFallback: false,
      );

      if (eventResult == null) {
        if (mounted) {
          showGlassSnackBar(context, 'Event detection failed', isError: true);
        }
        return null;
      }

      if (mounted) {
        setState(() {
          _eventResult = eventResult;
        });
      }

      return eventResult;
    } catch (e) {
      debugPrint('[VideoTesting] File event detection failed: $e');
      return null;
    }
  }

  // save data
  Future<void> _saveAndNotifyEvent(
    EventDetectionResult eventResult, {
    String? predictionId,
    String? streamUrl,
    String sourceType = 'video',
  }) async {
    final highestEvent = _selectStrongestEvent(eventResult);
    if (!eventResult.emergencyDetected || highestEvent == null) {
      if (mounted) {
        showGlassSnackBar(
          context,
          'Event detection complete \u2014 no threats detected',
          icon: Icons.verified_rounded,
          iconColor: Colors.green,
        );
      }
      return;
    }

    DetectedEvent eventToSave = highestEvent;
    GeoLocation? location;
    String? deviceId;
    String? deviceName;

    if (streamUrl != null) {
      final device = _ipService.findDeviceByStreamUrl(streamUrl);
      deviceId = device?.id;
      deviceName = device?.label;
      location = await _eventService.getDeviceLocation(
        deviceId: deviceId,
        streamUrl: streamUrl,
      );
      eventToSave = DetectedEvent(
        eventType: highestEvent.eventType,
        confidence: highestEvent.confidence,
        sceneClass: eventResult.sceneClass.toLowerCase(),
        location: location,
      );
    }

    final ok = await _eventService.saveEventToBackend(
      eventToSave,
      predictionId: predictionId,
      streamUrl: streamUrl,
      deviceId: deviceId,
      deviceName: deviceName,
      overrideLocation: location,
      sourceType: sourceType,
    );

    if (mounted) {
      showGlassSnackBar(
        context,
        'Event "${highestEvent.eventType.replaceAll('_', ' ').toUpperCase()}" detected${ok ? ' & saved' : ''}',
        icon: Icons.warning_amber_rounded,
        iconColor: Colors.orange,
      );
    }
  }

  // clear data
  void _clearSelection() {
    _videoController?.dispose();
    _videoController = null;
    setState(() {
      _selectedFilePath = null;
      _fileName = null;
      _result = null;
      _videoInitialized = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasFile = _selectedFilePath != null;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        children: [
          BackgroundBlobs(isDark: isDark),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 10),
                _buildNavbar(context),
                const SizedBox(height: 16),
                _buildModeToggle(scheme),
                Expanded(
                  child: _isHardwareMode
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Column(
                              children: [
                                _buildHardwareCameraPanel(scheme, isDark),
                                if (_result != null) ...[
                                  const SizedBox(height: 20),
                                  _buildResults(scheme, isDark),
                                ],
                                const SizedBox(height: 30),
                              ],
                            ),
                          ),
                        )
                      : _isStreamMode
                          ? SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: Column(
                                  children: [
                                    _buildStreamInput(scheme, isDark),
                                    if (_isStreamConnected) ...[
                                      const SizedBox(height: 20),
                                      _buildStreamPreview(scheme),
                                    ],
                                    const SizedBox(height: 20),
                                    _buildStreamActionButtons(scheme),
                                    if (_result != null) ...[
                                      const SizedBox(height: 20),
                                      _buildResults(scheme, isDark),
                                    ],
                                    const SizedBox(height: 30),
                                  ],
                                ),
                              ),
                            )
                          : hasFile
                              ? SingleChildScrollView(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 30),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        _buildDropZone(scheme, isDark),
                                        const SizedBox(height: 20),
                                        _buildVideoPreview(scheme),
                                        const SizedBox(height: 20),
                                        _buildActionButtons(scheme),
                                        if (_result != null) ...[
                                          const SizedBox(height: 20),
                                          _buildResults(scheme, isDark),
                                        ],
                                        const SizedBox(height: 30),
                                      ],
                                    ),
                                  ),
                                )
                              : Center(
                                  child: _buildDropZone(scheme, isDark),
                                ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // build ui section
  Widget _buildNavbar(BuildContext context) {
    final theme = ThemeController.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GlassContainer(
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
              _isHardwareMode
                  ? "Device Camera - Video"
                  : _isStreamMode
                      ? "Live Stream - Video"
                      : "Upload - Video Only",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(
                theme.isDarkMode ? Icons.light_mode : Icons.dark_mode,
              ),
              onPressed: theme.toggleTheme,
            ),
          ],
        ),
      ),
    );
  }

  // build ui section
  Widget _buildModeToggle(ColorScheme scheme) {
    return Center(
      child: GlassContainer(
        opacity: 0.15,
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModeButton(
              scheme: scheme,
              icon: Icons.folder_open_outlined,
              label: "File Upload",
              isSelected: !_isStreamMode && !_isHardwareMode,
              onTap: () => _toggleMode(false),
            ),
            _buildModeButton(
              scheme: scheme,
              icon: Icons.videocam_outlined,
              label: "IP Stream",
              isSelected: _isStreamMode,
              onTap: () => _toggleMode(true),
            ),
            if (_laptopCameraEnabled)
              _buildModeButton(
                scheme: scheme,
                icon: Icons.camera_alt_rounded,
                label: "Device Cam",
                isSelected: _isHardwareMode,
                onTap: _setHardwareMode,
              ),
          ],
        ),
      ),
    );
  }

  // build ui section
  Widget _buildModeButton({
    required ColorScheme scheme,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color:
              isSelected ? scheme.primary.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? scheme.primary
                  : scheme.onSurface.withOpacity(0.6),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? scheme.primary
                    : scheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // process data
  Future<void> _processHardwareCamera() async {
    try {
      final mlUrl = _eventService.mlServerUrl;
      await http
          .get(Uri.parse('$mlUrl/classes'))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      if (mounted) {
        showGlassSnackBar(
          context,
          'Inference server not running. Start it first.',
          isError: true,
        );
      }
      return;
    }

    setState(() {
      _isProcessing = true;
      _result = null;
    });

    try {
      Map<String, dynamic> result;
      String? eventType;
      EventDetectionResult? eventResult;

      if (_enableEventDetection && !_multiLabelMode) {
        eventResult = await _eventService.detectEventsFromLocalCamera(
          duration: _streamDuration,
          confidenceThreshold: 0.005,
          enableMotionFallback: false,
        );
        if (eventResult == null) {
          setState(() => _result = {
                'error': true,
                'message': 'Event detection failed',
              });
          return;
        }
        final strongestEvent = _selectStrongestEvent(eventResult);
        eventType = strongestEvent?.eventType;

        final sceneDetected = eventResult.sceneConfidence >= 0.50;
        result = {
          'type': 'video_local',
          'source': 'laptop_camera',
          'predictedClass': eventResult.sceneClass,
          'confidence': eventResult.sceneConfidence,
          'topPredictions': eventResult.topPredictions,
          if (sceneDetected)
            'eventDetection': {
              'eventsDetected': eventResult.emergencyDetected,
              'events': eventResult.events.map((e) => e.eventType).toList(),
              'eventConfidences': {
                for (var e in eventResult.events) e.eventType: e.confidence
              },
              'highestSeverityEvent': strongestEvent != null
                  ? {
                      'type': strongestEvent.eventType,
                      'confidence': strongestEvent.confidence,
                    }
                  : null,
              'alertLevel': eventResult.alertLevel,
            },
        };

        if (!sceneDetected) {
          eventResult = null;
          eventType = null;
        }
      } else {
        result = await _classifier.classifyVideoLocal(
            durationSeconds: _streamDuration);
      }

      setState(() => _result = result);

      final predictionId = await _historyService.saveToHistory(
        type: 'video_local',
        fileName: 'Laptop Camera',
        result: result,
        source: 'hardware',
        streamDuration: _streamDuration,
        eventType: eventType,
        eventDetectionEnabled: _enableEventDetection,
      );

      if (eventResult != null) {
        await _saveAndNotifyEvent(
          eventResult,
          predictionId: predictionId,
          sourceType: 'video_local',
        );
      }
    } catch (e) {
      setState(() => _result = {
            'error': true,
            'message': 'Error processing camera video: $e',
          });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // build ui section
  Widget _buildHardwareCameraPanel(ColorScheme scheme, bool isDark) {
    return SizedBox(
      width: 440,
      child: GlassContainer(
        opacity: 0.22,
        padding: const EdgeInsets.all(26),
        borderRadius: BorderRadius.circular(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt_rounded, size: 60, color: scheme.primary),
            const SizedBox(height: 18),
            Text(
              'Record from Laptop Camera',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Uses your device\'s built-in or connected\nwebcam for video classification.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            DurationSlider(
              value: _streamDuration,
              min: 3,
              max: 15,
              divisions: 12,
              subtitle: 'Recording Duration',
              onChanged: (v) => setState(() => _streamDuration = v),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isProcessing ? null : _processHardwareCamera,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.fiber_manual_record_rounded),
                label: Text(
                  _isProcessing ? 'Recording...' : 'Record & Classify',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // build ui section
  Widget _buildStreamInput(ColorScheme scheme, bool isDark) {
    return SizedBox(
      width: 440,
      child: GlassContainer(
        opacity: 0.22,
        padding: const EdgeInsets.all(26),
        borderRadius: BorderRadius.circular(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_rounded,
              size: 60,
              color: scheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              "Connect to IP Camera",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Enter your DroidCam, IP Webcam, or other\nnetwork stream URL for live testing.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 20),
            if (_ipService.devicesForModality('video').isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withOpacity(isDark ? 0.10 : 0.55),
                          Colors.white.withOpacity(isDark ? 0.05 : 0.30),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(isDark ? 0.15 : 0.45),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.15 : 0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4, top: 8),
                          child: Text(
                            'Saved Devices',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ),
                        DropdownButton<String>(
                          value: null,
                          isExpanded: true,
                          underline: const SizedBox(),
                          itemHeight: 64,
                          dropdownColor: isDark
                              ? Color.lerp(scheme.surface, Colors.white, 0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          elevation: 8,
                          hint: Row(
                            children: [
                              Icon(Icons.devices_rounded,
                                  color: scheme.onSurface.withOpacity(0.5),
                                  size: 20),
                              const SizedBox(width: 10),
                              Text('Select a saved device',
                                  style: TextStyle(
                                      color:
                                          scheme.onSurface.withOpacity(0.5))),
                            ],
                          ),
                          icon: Icon(Icons.expand_more_rounded,
                              color: scheme.onSurface.withOpacity(0.5)),
                          items:
                              _ipService.devicesForModality('video').map((d) {
                            return DropdownMenuItem<String>(
                              value: d.streamUrl,
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        d.label,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${d.type.toUpperCase()} · ${d.address}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color:
                                              scheme.onSurface.withOpacity(0.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (url) {
                            if (url != null) {
                              setState(() {
                                _streamUrlController.text = url;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: scheme.onSurface.withOpacity(0.15),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or enter manually',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: scheme.onSurface.withOpacity(0.15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _streamUrlController,
              decoration: InputDecoration(
                hintText: "192.168.1.50:4747 or full URL",
                hintStyle: TextStyle(
                  color: scheme.onSurface.withOpacity(0.4),
                  fontSize: 14,
                ),
                prefixIcon: Icon(Icons.link, color: scheme.primary),
                filled: true,
                fillColor: scheme.onSurface.withOpacity(0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: scheme.onSurface.withOpacity(0.1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: scheme.primary, width: 2),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 14,
              ),
              onChanged: (value) {
                if (_streamError != null) {
                  setState(() {
                    _streamError = null;
                  });
                }
              },
            ),
            if (_streamError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: scheme.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _streamError!,
                        style: TextStyle(color: scheme.error, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (_isStreamConnected)
              OutlinedButton.icon(
                onPressed: _disconnectStream,
                icon: const Icon(Icons.link_off),
                label: const Text("Disconnect"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error.withOpacity(0.5)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 26, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: _isConnectingStream ? null : _connectToStream,
                icon: _isConnectingStream
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.play_circle_outline),
                label: Text(
                    _isConnectingStream ? "Connecting..." : "Connect Stream"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 26, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: scheme.primary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Just enter IP:PORT (e.g. 192.168.1.50:4747)\n"
                      "http:// and /video are added automatically\n"
                      "• DroidCam: port 4747 • IP Webcam: port 8080 • RTSP: usually 554",
                      style: TextStyle(
                        color: scheme.onSurface.withOpacity(0.7),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // build ui section
  Widget _buildStreamPreview(ColorScheme scheme) {
    return SizedBox(
      width: 440,
      child: GlassContainer(
        opacity: 0.18,
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withOpacity(0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _videoInitialized ? "Live Stream Preview" : "Stream Ready",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: scheme.error, size: 20),
                  onPressed: _disconnectStream,
                  tooltip: 'Disconnect stream',
                ),
              ],
            ),
            if (_videoInitialized &&
                _videoController != null &&
                _videoController!.value.isInitialized) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio > 0
                      ? _videoController!.value.aspectRatio
                      : 16 / 9,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: scheme.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Stream URL configured. Preview not available on this platform, but you can classify directly.",
                        style: TextStyle(
                          color: scheme.onSurface.withOpacity(0.8),
                          fontSize: 12,
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
    );
  }

  // build ui section
  Widget _buildEventDetectionToggle(ColorScheme scheme) {
    return SizedBox(
      width: 440,
      child: GlassContainer(
        opacity: 0.15,
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: _enableEventDetection
                  ? scheme.primary
                  : scheme.onSurface.withOpacity(0.4),
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Event Detection",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    _enableEventDetection
                        ? "Auto-detect & save events to DB"
                        : "Events will not be saved",
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _enableEventDetection,
              onChanged: (value) {
                setState(() {
                  _enableEventDetection = value;
                });
              },
              activeColor: scheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  // build ui section
  Widget _buildStreamActionButtons(ColorScheme scheme) {
    return Column(
      children: [
        SizedBox(
          width: 440,
          child: DurationSlider(
            value: _streamDuration,
            min: 3,
            max: 30,
            onChanged: (value) {
              setState(() {
                _streamDuration = value;
              });
            },
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 440,
          child: GlassContainer(
            opacity: 0.15,
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.layers_outlined, color: scheme.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Multi-Scene Detection",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      Text(
                        "Detect multiple scenes in capture",
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _multiLabelMode,
                  onChanged: (value) {
                    setState(() {
                      _multiLabelMode = value;
                      _result = null;
                    });
                  },
                  activeColor: scheme.primary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildEventDetectionToggle(scheme),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: (_isProcessing || _streamUrlController.text.trim().isEmpty)
              ? null
              : _processStream,
          icon: _isProcessing
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onPrimary,
                  ),
                )
              : Icon(_multiLabelMode ? Icons.layers : Icons.analytics_outlined),
          label: Text(_isProcessing
              ? "Capturing & Analyzing..."
              : (_multiLabelMode ? "Detect Scenes" : "Classify Stream")),
          style: ElevatedButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ],
    );
  }

  // build ui section
  Widget _buildDropZone(ColorScheme scheme, bool isDark) {
    return DropTarget(
      onDragDone: (details) async {
        if (details.files.isNotEmpty) {
          final file = details.files.first;
          _handleFileSelected(file.path, file.name);
        }
      },
      child: GlassContainer(
        opacity: 0.22,
        padding: const EdgeInsets.all(26),
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                size: 78,
                color: scheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                "Drag & Drop or Locate File",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Supported formats depend on the selected mode.\n"
                "This is the upload step for your MVATS testing.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 26),
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.folder_open),
                label: const Text("Browse Files"),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // build ui section
  Widget _buildVideoPreview(ColorScheme scheme) {
    return SizedBox(
      width: 440,
      child: GlassContainer(
        opacity: 0.18,
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.movie_outlined, color: scheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _fileName ?? 'Selected Video',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: scheme.error, size: 20),
                  onPressed: _clearSelection,
                  tooltip: 'Remove video',
                ),
              ],
            ),
            if (_videoInitialized &&
                _videoController != null &&
                _videoController!.value.isInitialized) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_videoController!),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            if (_videoController!.value.isPlaying) {
                              _videoController!.pause();
                            } else {
                              _videoController!.play();
                            }
                          });
                        },
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black38,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            _videoController!.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // build ui section
  Widget _buildActionButtons(ColorScheme scheme) {
    return Column(
      children: [
        SizedBox(
          width: 440,
          child: DurationSlider(
            value: _streamDuration,
            min: 3,
            max: 30,
            onChanged: (value) {
              setState(() {
                _streamDuration = value;
              });
            },
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 440,
          child: GlassContainer(
            opacity: 0.15,
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.layers_outlined,
                  color: scheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Multi-Scene Detection",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      Text(
                        "Detect multiple scenes in video",
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _multiLabelMode,
                  onChanged: (value) {
                    setState(() {
                      _multiLabelMode = value;
                      _result = null;
                    });
                  },
                  activeColor: scheme.primary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildEventDetectionToggle(scheme),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _isProcessing ? null : _processVideo,
          icon: _isProcessing
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onPrimary,
                  ),
                )
              : Icon(_multiLabelMode ? Icons.layers : Icons.analytics_outlined),
          label: Text(_isProcessing
              ? (_multiLabelMode ? "Analyzing Scenes..." : "Processing...")
              : (_multiLabelMode ? "Detect Scenes" : "Classify Video")),
          style: ElevatedButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ],
    );
  }

  // build ui section
  Widget _buildResults(ColorScheme scheme, bool isDark) {
    final isError = _result?['error'] == true;
    final isDemo = _result?['isDemo'] == true;
    final isMultilabel = _result?['type'] == 'video_multilabel' ||
        _result?['type'] == 'stream_multilabel';
    final isStream =
        _result?['type'] == 'stream' || _result?['type'] == 'stream_multilabel';

    final containerWidth = isMultilabel ? 520.0 : 440.0;

    return SizedBox(
      width: containerWidth,
      child: GlassContainer(
        opacity: 0.22,
        borderRadius: BorderRadius.circular(24),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isError
                      ? Icons.error_outline
                      : (isMultilabel
                          ? Icons.layers
                          : (isStream
                              ? Icons.videocam
                              : Icons.check_circle_outline)),
                  color: isError ? scheme.error : scheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isError
                        ? "Error"
                        : (isMultilabel
                            ? (isStream
                                ? "Stream Multi-Scene Detection"
                                : "Multi-Scene Detection")
                            : (isStream
                                ? "Stream Classification Result"
                                : "Classification Result")),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                if (isStream && !isError) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: scheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: scheme.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam, color: scheme.primary, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          "LIVE",
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (isDemo) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: scheme.primary.withOpacity(0.3)),
                    ),
                    child: Text(
                      "DEMO",
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            if (isError)
              Text(
                _result?['message'] ?? 'Unknown error',
                style: TextStyle(color: scheme.error),
              )
            else if (isMultilabel) ...[
              _buildMultiLabelResults(scheme),
            ] else ...[
              _buildSingleLabelResults(scheme),
            ],
            if (isDemo && _result?['message'] != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: scheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _result!['message'],
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: 12,
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
    );
  }

  // build ui section
  Widget _buildSingleLabelResults(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _buildConfidenceBasedContent(scheme),
    );
  }

  // build widget list
  List<Widget> _buildConfidenceBasedContent(ColorScheme scheme) {
    final confPercent = ((_result?['confidence'] ?? 0) as num) * 100;
    final bool noScene = confPercent < 50;

    if (noScene) {
      return [_buildNoSceneBlock(scheme)];
    }

    final String predictedClass =
        (_result?['predictedClass'] as String?)?.toLowerCase() ?? '';
    double displayConfPercent = confPercent.toDouble();

    // If bus class, get confidence from boosted list to ensure consistency
    if (predictedClass == 'bus' && _result?['topPredictions'] != null) {
      final boostedList = _applyBusBoost(_result!['topPredictions'] as List);
      final busEntry = boostedList.firstWhere(
        (p) => (p['class'] as String?)?.toLowerCase() == 'bus',
        orElse: () => {},
      );
      if (busEntry.isNotEmpty) {
        displayConfPercent = ((busEntry['confidence'] ?? confPercent / 100) as num).toDouble() * 100;
      }
    }

    return [
      _buildResultRow(
        "Predicted Class",
        _result?['predictedClass']?.toString().toUpperCase() ?? 'N/A',
        scheme,
        isHighlighted: true,
      ),
      const SizedBox(height: 12),
      _buildResultRow(
        "Confidence",
        "${displayConfPercent.toStringAsFixed(1)}%",
        scheme,
      ),
      if (_result?['topPredictions'] != null) ...[
        const SizedBox(height: 20),
        Text(
          "Top 5 Predictions",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        ..._applyBusBoost(_result!['topPredictions'] as List).map((pred) {
            final confidence = (pred['confidence'] ?? 0) * 100;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      pred['class'] ?? 'Unknown',
                      style: TextStyle(
                        color: scheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: confidence / 100,
                        backgroundColor: scheme.onSurface.withOpacity(0.1),
                        color: scheme.primary,
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 50,
                    child: Text(
                      "${confidence.toStringAsFixed(1)}%",
                      style: TextStyle(
                        color: scheme.onSurface.withOpacity(0.7),
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ];
  }

  Widget _buildNoSceneBlock(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFE65100).withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE65100).withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.visibility_off_rounded, color: const Color(0xFFBF360C), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No scene detected\nInput does not match trained categories',
                style: TextStyle(
                  color: const Color(0xFFBF360C),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // build ui section
  Widget _buildMultiLabelResults(ColorScheme scheme) {
    final rawDetectedClasses = _result?['detectedClasses'] as List? ?? [];
    final segmentPredictions = _result?['segmentPredictions'] as List? ?? [];
    final isMultilabel = _result?['isMultilabel'] == true;
    final summary = _result?['summary'] ?? '';
    final durationSeconds =
        (_result?['durationSeconds'] ?? _result?['capturedSeconds'] ?? 0);
    final durationDisplay = durationSeconds is num
        ? durationSeconds.toDouble().toStringAsFixed(2)
        : durationSeconds.toString();
    final totalSegments = _result?['totalSegments'] ?? 0;

    final detectedClasses = rawDetectedClasses.where((cls) {
      final confidence = (cls['maxConfidence'] ?? 0).toDouble();
      return confidence >= 0.85;
    }).toList();

    print('=========================');

    final colors = [
      scheme.primary,
      const Color(0xFFE65100),
      const Color(0xFF00796B),
      const Color(0xFFC2185B),
      const Color(0xFF283593),
      const Color(0xFFFF8F00),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isMultilabel)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primary.withOpacity(0.2),
                  scheme.secondary.withOpacity(0.2)
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: scheme.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    summary,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          _buildResultRow(
            "Primary Scene",
            _result?['predictedClass']?.toString().toUpperCase() ?? 'N/A',
            scheme,
            isHighlighted: true,
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildInfoChip(scheme, Icons.timer_outlined, "${durationDisplay}s"),
            const SizedBox(width: 8),
            _buildInfoChip(scheme, Icons.grid_view, "$totalSegments segments"),
            const SizedBox(width: 8),
            _buildInfoChip(
                scheme, Icons.layers, "${detectedClasses.length} scenes"),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          "Detected Scenes",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileMinWidth = 180.0;
            final crossAxisCount =
                (constraints.maxWidth / tileMinWidth).floor().clamp(1, 3);

            final sortedByTime = List<Map<String, dynamic>>.from(
              detectedClasses.map(
                  (c) => c is Map<String, dynamic> ? c : <String, dynamic>{}),
            )..sort((a, b) {
                final aT = ((a['firstDetectedAt'] ?? 0) as num).toDouble();
                final bT = ((b['firstDetectedAt'] ?? 0) as num).toDouble();
                return aT.compareTo(bT);
              });
            final totalDur = durationSeconds is num
                ? (durationSeconds as num).toDouble()
                : 0.0;
            final sceneDurations = <String, double>{};
            for (int i = 0; i < sortedByTime.length; i++) {
              final cls = (sortedByTime[i]['class'] ?? '').toString();
              final start =
                  ((sortedByTime[i]['firstDetectedAt'] ?? 0) as num).toDouble();
              final nextStart = (i + 1 < sortedByTime.length)
                  ? ((sortedByTime[i + 1]['firstDetectedAt'] ?? 0) as num)
                      .toDouble()
                  : totalDur;
              sceneDurations[cls] = (nextStart - start).clamp(0, totalDur);
            }

            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: detectedClasses.asMap().entries.map((entry) {
                final index = entry.key;
                final cls = entry.value;
                final color = colors[index % colors.length];
                final className =
                    (cls is Map ? cls['class'] : cls)?.toString() ?? '';
                final dur = sceneDurations[className] ?? 0.0;

                return _buildDetectedClassTile(
                  scheme: scheme,
                  cls: cls,
                  color: color,
                  sceneDuration: dur,
                  width: crossAxisCount == 1
                      ? constraints.maxWidth
                      : (constraints.maxWidth - (crossAxisCount - 1) * 10) /
                          crossAxisCount,
                );
              }).toList(),
            );
          },
        ),
        if (segmentPredictions.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            "Timeline",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _buildTimeline(scheme, segmentPredictions),
        ],
      ],
    );
  }

  // build ui section
  Widget _buildDetectedClassTile({
    required ColorScheme scheme,
    required Map<String, dynamic> cls,
    required Color color,
    required double width,
    double sceneDuration = 0.0,
  }) {
    final className = cls['class'] ?? 'Unknown';
    final confidence = ((cls['maxConfidence'] ?? 0) * 100);
    final percentage = cls['percentageOfVideo'] ?? 0;
    final occurrences = cls['occurrences'] ?? 0;
    final firstDetectedAt = cls['firstDetectedAt'] ?? 0.0;

    String formatTimestamp(double seconds) {
      if (seconds < 0.05) return '0s';
      final mins = (seconds / 60).floor();
      final secs = (seconds % 60);
      if (mins > 0) {
        return '${mins}m ${secs.toStringAsFixed(0)}s';
      }
      return secs >= 1
          ? '${secs.toStringAsFixed(0)}s'
          : '${secs.toStringAsFixed(1)}s';
    }

    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  className.toString().toUpperCase(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: confidence / 100,
              backgroundColor: scheme.onSurface.withOpacity(0.1),
              color: color,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Confidence",
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withOpacity(0.6),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  "${confidence.toStringAsFixed(1)}%",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule,
                  size: 12, color: scheme.onSurface.withOpacity(0.5)),
              const SizedBox(width: 4),
              Text(
                "First at ${formatTimestamp(firstDetectedAt.toDouble())}",
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (sceneDuration > 0) ...[
                const SizedBox(width: 8),
                Icon(Icons.timelapse,
                    size: 12, color: scheme.onSurface.withOpacity(0.5)),
                const SizedBox(width: 4),
                Text(
                  "${formatTimestamp(sceneDuration)} dur",
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.repeat,
                  size: 12, color: scheme.onSurface.withOpacity(0.5)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  "$occurrences segments · ${percentage.toStringAsFixed(0)}% of video",
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurface.withOpacity(0.6),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // build ui section
  Widget _buildInfoChip(ColorScheme scheme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.onSurface.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurface.withOpacity(0.7)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  // build ui section
  Widget _buildTimeline(ColorScheme scheme, List segmentPredictions) {
    final uniqueClasses = segmentPredictions
        .map((s) => s['predictedClass'] as String)
        .toSet()
        .toList();

    final colors = [
      scheme.primary,
      scheme.secondary,
      Colors.orange,
      Colors.teal,
      Colors.pink,
    ];

    return Column(
      children: [
        SizedBox(
          height: 24,
          child: Row(
            children: segmentPredictions.map((segment) {
              final classIndex =
                  uniqueClasses.indexOf(segment['predictedClass']);
              final color = colors[classIndex % colors.length];
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: uniqueClasses.asMap().entries.map((entry) {
            final color = colors[entry.key % colors.length];
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  // build ui section
  Widget _buildResultRow(String label, String value, ColorScheme scheme,
      {bool isHighlighted = false}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: scheme.onSurface.withOpacity(0.7),
            fontSize: 14,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isHighlighted ? 16 : 12,
              vertical: isHighlighted ? 8 : 4,
            ),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? scheme.primary.withOpacity(0.2)
                  : scheme.onSurface.withOpacity(0.1),
              borderRadius: BorderRadius.circular(isHighlighted ? 12 : 8),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: isHighlighted ? scheme.primary : scheme.onSurface,
                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500,
                fontSize: isHighlighted ? 14 : 13,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ),
      ],
    );
  }

}
