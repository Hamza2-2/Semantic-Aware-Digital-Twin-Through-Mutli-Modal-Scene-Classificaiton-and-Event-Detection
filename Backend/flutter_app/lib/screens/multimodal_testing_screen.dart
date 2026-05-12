// file header note
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:video_player/video_player.dart';
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

class MultimodalTestingScreen extends StatefulWidget {
  const MultimodalTestingScreen({super.key});

  @override
  State<MultimodalTestingScreen> createState() =>
      _MultimodalTestingScreenState();
}

class _MultimodalTestingScreenState extends State<MultimodalTestingScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  final VideoClassifierService _classifier = VideoClassifierService();
  final PredictionHistoryService _historyService = PredictionHistoryService();
  final IpAddressService _ipService = IpAddressService();
  final EventDetectionService _eventService = EventDetectionService();

  bool _enableEventDetection = true;
  EventDetectionResult? _eventResult;
  GeoLocation? _currentLocation;

  String? _videoFilePath;
  String? _videoFileName;
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;

  String? _audioFilePath;
  String? _audioFileName;

  bool _isProcessing = false;
  Map<String, dynamic>? _result;

  late AnimationController _waveController;

  String _fusionMode = 'single';

  String _fusionMethod = 'confidence';

  bool _multiSceneMode = false;

  bool _isStreamMode = false;
  bool _isHardwareMode = false;
  bool _laptopMicEnabled = true;
  bool _laptopCameraEnabled = true;
  int _hardwareDuration = 8;
  final TextEditingController _streamUrlController = TextEditingController();
  int _streamDuration = 5;
  bool _isStreamConnected = false;
  bool _isConnectingStream = false;
  String? _streamError;

  final List<Map<String, String>> _fusionMethods = [
    {
      'value': 'confidence',
      'label': 'Confidence-Based',
      'description': 'Dynamic weighting based on model confidence'
    },
    {
      'value': 'weighted',
      'label': 'Weighted Average',
      'description': 'Simple 50/50 weighted average'
    },
    {
      'value': 'max',
      'label': 'Max Confidence',
      'description': 'Use most confident modality'
    },
    {
      'value': 'average',
      'label': 'Average Probs',
      'description': 'Average probability distributions'
    },
  ];

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _ipService.load().then((_) {
      if (mounted) setState(() {});
    });
    _classifier.loadSettings();
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

  Future<void> _loadGeolocation() async {
    final location = await _eventService.getGeolocation();
    if (mounted && location != null) {
      setState(() {
        _currentLocation = location;
      });
    }
  }

  Future<void> _loadHardwarePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final micEnabled = prefs.getBool('enable_laptop_mic') ?? true;
    final cameraEnabled = prefs.getBool('enable_laptop_camera') ?? true;
    setState(() {
      _laptopMicEnabled = micEnabled;
      _laptopCameraEnabled = cameraEnabled;
      if (_isHardwareMode && (!micEnabled || !cameraEnabled)) {
        _isHardwareMode = false;
      }
    });
  }

  DetectedEvent? _selectStrongestEvent(EventDetectionResult eventResult) {
    DetectedEvent? strongest = eventResult.highestSeverityEvent;

    if (eventResult.events.isNotEmpty) {
      final maxFromList = eventResult.events.reduce(
        (a, b) => a.confidence >= b.confidence ? a : b,
      );
      if (strongest == null || maxFromList.confidence > strongest.confidence) {
        strongest = maxFromList;
      }
    }

    return strongest;
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _videoController?.dispose();
    _waveController.dispose();
    _streamUrlController.dispose();
    super.dispose();
  }

  void _toggleInputMode(bool isStream) {
    if (_isStreamMode != isStream || _isHardwareMode) {
      _disconnectStream();
      setState(() {
        _isStreamMode = isStream;
        _isHardwareMode = false;
        _result = null;
      });
    }
  }

  void _setHardwareInputMode() {
    if (!_isHardwareMode) {
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
      setState(() => _streamError = 'Please enter a stream URL');
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
      _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
      await _videoController!.initialize();
      setState(() {
        _isStreamConnected = true;
        _videoInitialized = true;
        _isConnectingStream = false;
      });
      _videoController!.play();
      _videoController!.setLooping(true);
    } catch (e) {
      debugPrint('Stream preview not available: \$e');
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

  Future<void> _processStream() async {
    var url = _streamUrlController.text.trim();
    if (url.isEmpty) return;
    url = _normalizeStreamUrl(url);

    setState(() {
      _isProcessing = true;
      _result = null;
    });

    try {
      final results = await Future.wait([
        _classifier.classifyStream(url, durationSeconds: _streamDuration),
        _classifier.classifyAudioStream(url, durationSeconds: _streamDuration),
      ]);

      final videoResult = results[0];
      final audioResult = results[1];

      final videoConf = (videoResult['confidence'] as num?)?.toDouble() ?? 0.0;
      final audioConf = (audioResult['confidence'] as num?)?.toDouble() ?? 0.0;
      final totalConf = videoConf + audioConf;
      final videoWeight = totalConf > 0 ? videoConf / totalConf : 0.5;
      final audioWeight = totalConf > 0 ? audioConf / totalConf : 0.5;

      final fusedResult = {
        'type': 'fusion_stream',
        'fusionMethod': _fusionMethod,
        'predictedClass': videoConf >= audioConf
            ? videoResult['predictedClass']
            : audioResult['predictedClass'],
        'confidence': videoConf * videoWeight + audioConf * audioWeight,
        'topPredictions': videoResult['topPredictions'],
        'videoResult': videoResult,
        'audioResult': audioResult,
        'fusionAnalysis': {
          'modalityAgreement':
              videoResult['predictedClass'] == audioResult['predictedClass'],
          'agreementScore': videoConf >= audioConf ? videoConf : audioConf,
          'videoWeight': videoWeight,
          'audioWeight': audioWeight,
        },
        'streamUrl': url,
        'durationSeconds': _streamDuration,
      };

      setState(() => _result = fusedResult);

      String? eventType;
      EventDetectionResult? eventResult;
      if (_enableEventDetection && fusedResult['error'] != true) {
        eventResult = await _runEventDetectionForStream(url, fusedResult);
        if (eventResult != null) {
          final strongestEvent = _selectStrongestEvent(eventResult);
          eventType = strongestEvent?.eventType;
          fusedResult['eventDetection'] = {
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
        type: 'fusion_stream',
        fileName: 'Live Stream Fusion',
        filePath: url,
        result: fusedResult,
        source: 'stream',
        streamUrl: url,
        streamDuration: _streamDuration,
        fusionMethod: _fusionMethod,
        eventType: eventType,
        eventDetectionEnabled: _enableEventDetection,
      );

      if (eventResult != null) {
        await _saveAndNotifyEvent(
          eventResult,
          predictionId: predictionId,
          streamUrl: url,
          sourceType: 'fusion_stream',
        );
      }
    } catch (e) {
      setState(() {
        _result = {
          'error': true,
          'message': 'Error processing stream: \$e',
        };
      });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<EventDetectionResult?> _runEventDetectionForStream(
      String streamUrl, Map<String, dynamic> result) async {
    try {
      final eventResult = await _eventService.detectEventsInStream(
        streamUrl,
        duration: _streamDuration,
        confidenceThreshold: 0.55,
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
      debugPrint('[MultimodalTesting] Stream event detection failed: $e');
      return null;
    }
  }

  Future<EventDetectionResult?> _runEventDetectionForFile(
      Map<String, dynamic> result) async {
    if (_videoFilePath == null) return null;

    try {
      final eventResult = await _eventService.detectEventsInVideo(
        _videoFilePath!,
        enableAvSlowFast: true,
        confidenceThreshold: 0.55,
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
      debugPrint('[MultimodalTesting] File event detection failed: $e');
      return null;
    }
  }

  Future<void> _saveAndNotifyEvent(
    EventDetectionResult eventResult, {
    String? predictionId,
    String? streamUrl,
    String sourceType = 'fusion',
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
        iconColor: const Color(0xFF7C4DFF),
      );
    }
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      await _handleVideoSelected(file.path!, file.name);
    }
  }

  Future<void> _handleVideoSelected(String path, String name) async {
    setState(() {
      _videoFilePath = path;
      _videoFileName = name;
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
      setState(() {
        _videoInitialized = true;
      });
    } catch (e) {
      _videoController?.dispose();
      _videoController = null;
      debugPrint('Error initializing video: $e');
    }
  }

  void _clearVideo() {
    _videoController?.dispose();
    _videoController = null;
    setState(() {
      _videoFilePath = null;
      _videoFileName = null;
      _result = null;
      _videoInitialized = false;
    });
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      _handleAudioSelected(file.path!, file.name);
    }
  }

  void _handleAudioSelected(String path, String name) {
    setState(() {
      _audioFilePath = path;
      _audioFileName = name;
      _result = null;
    });
  }

  void _clearAudio() {
    setState(() {
      _audioFilePath = null;
      _audioFileName = null;
      _result = null;
    });
  }

  Future<void> _processMultimodal() async {
    if (_fusionMode == 'single') {
      if (_videoFilePath == null) {
        showGlassSnackBar(
            context, 'Please select a video file containing audio',
            isError: true);
        return;
      }
    } else {
      if (_videoFilePath == null && _audioFilePath == null) {
        showGlassSnackBar(context, 'Please select at least one file',
            isError: true);
        return;
      }
    }

    setState(() {
      _isProcessing = true;
      _result = null;
    });

    try {
      Map<String, dynamic> result;

      if (_fusionMode == 'single') {
        result = await _classifier.classifyFusion(
          _videoFilePath!,
          fusionMethod: _fusionMethod,
          multiScene: _multiSceneMode,
        );
      } else {
        result = await _classifier.classifyMultimodal(
          videoPath: _videoFilePath,
          audioPath: _audioFilePath,
        );
      }

      setState(() {
        _result = result;
      });

      String? eventType;
      EventDetectionResult? eventResult;
      if (_enableEventDetection && result['error'] != true) {
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

      final fileName = _videoFileName ?? _audioFileName ?? 'Unknown';
      final predictionId = await _historyService.saveToHistory(
        type: 'fusion',
        fileName: fileName,
        result: result,
        source: 'file',
        fusionMethod: _fusionMode == 'single' ? _fusionMethod : null,
        multiScene: _multiSceneMode,
        eventType: eventType,
        eventDetectionEnabled: _enableEventDetection,
      );

      if (eventResult != null) {
        await _saveAndNotifyEvent(
          eventResult,
          predictionId: predictionId,
          sourceType: 'fusion',
        );
      }
    } catch (e) {
      setState(() {
        _result = {
          'error': true,
          'message': 'Error processing files: $e',
        };
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasFile = _videoFilePath != null || _audioFilePath != null;

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
                Expanded(
                  child: _isHardwareMode
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                            child: _buildHardwareFusionPanel(scheme, isDark),
                          ),
                        )
                      : _isStreamMode
                          ? SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(vertical: 30),
                              child: Center(
                                child: Column(
                                  children: [
                                    _buildStreamInput(scheme, isDark),
                                    if (_isStreamConnected &&
                                        _videoInitialized) ...[
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
                                        if (_videoFilePath != null)
                                          _buildVideoPreview(scheme),
                                        if (_videoFilePath != null &&
                                            _audioFilePath != null)
                                          const SizedBox(height: 20),
                                        if (_audioFilePath != null)
                                          _buildAudioPreview(scheme),
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
                  ? "Device Hardware - Multimodal"
                  : _isStreamMode
                      ? "Live Stream - Multimodal"
                      : "Upload - Multimodal",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const Spacer(),
            _buildInputModeToggle(scheme),
            const SizedBox(width: 8),
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

  Widget _buildInputModeToggle(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleButton(
            label: "Upload",
            isSelected: !_isStreamMode && !_isHardwareMode,
            scheme: scheme,
            onTap: () => _toggleInputMode(false),
          ),
          _buildToggleButton(
            label: "IP Stream",
            isSelected: _isStreamMode && !_isHardwareMode,
            scheme: scheme,
            onTap: () => _toggleInputMode(true),
          ),
          if (_laptopMicEnabled && _laptopCameraEnabled)
            _buildToggleButton(
              label: "Hardware",
              isSelected: _isHardwareMode,
              scheme: scheme,
              onTap: () => _setHardwareInputMode(),
            ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required bool isSelected,
    required ColorScheme scheme,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? scheme.onPrimary
                : scheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildDropZone(ColorScheme scheme, bool isDark) {
    return DropTarget(
      onDragDone: (details) async {
        if (details.files.isNotEmpty) {
          final file = details.files.first;
          final ext = file.name.toLowerCase();
          if (ext.endsWith('.mp4') ||
              ext.endsWith('.avi') ||
              ext.endsWith('.mov') ||
              ext.endsWith('.mkv')) {
            await _handleVideoSelected(file.path, file.name);
          } else {
            if (_fusionMode == 'separate') {
              _handleAudioSelected(file.path, file.name);
            }
          }
        }
      },
      child: GlassContainer(
        opacity: 0.22,
        padding: const EdgeInsets.all(26),
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModeToggle(scheme),
              const SizedBox(height: 20),
              Icon(
                _fusionMode == 'single'
                    ? Icons.merge_type_rounded
                    : Icons.cloud_upload_outlined,
                size: 68,
                color: scheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                _fusionMode == 'single'
                    ? "Single File Fusion"
                    : "Separate Files Multimodal",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _fusionMode == 'single'
                    ? "Upload a video with audio. Both video and audio\nwill be processed and fused for classification."
                    : "Upload separate video and audio files.\nBoth will be processed and combined.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              if (_fusionMode == 'single') ...[
                const SizedBox(height: 20),
                _buildFusionMethodSelector(scheme),
              ],
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickVideo,
                    icon: const Icon(Icons.videocam, size: 18),
                    label: Text(
                        _fusionMode == 'single' ? "Select Video" : "Video"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  if (_fusionMode == 'separate') ...[
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _pickAudio,
                      icon: const Icon(Icons.audiotrack, size: 18),
                      label: const Text("Audio"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeToggle(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeButton(
            'single',
            'Single File Fusion',
            Icons.merge_type,
            scheme,
          ),
          const SizedBox(width: 4),
          _buildModeButton(
            'separate',
            'Separate Files',
            Icons.call_split,
            scheme,
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(
      String mode, String label, IconData icon, ColorScheme scheme) {
    final isSelected = _fusionMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _fusionMode = mode;
          _result = null;

          if (mode == 'single') {
            _audioFilePath = null;
            _audioFileName = null;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHardwareFusionPanel(ColorScheme scheme, bool isDark) {
    return SizedBox(
      width: 520,
      child: GlassContainer(
        opacity: 0.22,
        padding: const EdgeInsets.all(26),
        borderRadius: BorderRadius.circular(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mic, size: 32, color: scheme.primary),
                const SizedBox(width: 12),
                Icon(Icons.videocam, size: 32, color: scheme.secondary),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Device Hardware Fusion',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Records from laptop mic & camera simultaneously',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            DurationSlider(
              value: _hardwareDuration,
              min: 5,
              max: 20,
              divisions: 15,
              subtitle: 'Capture Duration',
              onChanged: (v) => setState(() => _hardwareDuration = v),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isProcessing ? null : _processHardwareFusion,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sensors),
              label: Text(_isProcessing ? 'Capturing...' : 'Record & Classify'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(200, 46),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 20),
              _buildResults(scheme, isDark),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _processHardwareFusion() async {
    setState(() {
      _isProcessing = true;
      _result = null;
    });

    try {
      final results = await Future.wait([
        _classifier.classifyVideoLocal(durationSeconds: _hardwareDuration),
        _classifier.classifyAudioLocal(durationSeconds: _hardwareDuration),
      ]);

      final videoResult = results[0];
      final audioResult = results[1];

      if (videoResult['isDemo'] == true || audioResult['isDemo'] == true) {
        setState(() => _result = {
              'error': true,
              'message':
                  'ML server unreachable. Ensure inference_server.py is running.',
            });
        return;
      }

      final videoConf = (videoResult['confidence'] as num?)?.toDouble() ?? 0.0;
      final audioConf = (audioResult['confidence'] as num?)?.toDouble() ?? 0.0;
      final totalConf = videoConf + audioConf;
      final videoWeight = totalConf > 0 ? videoConf / totalConf : 0.5;
      final audioWeight = totalConf > 0 ? audioConf / totalConf : 0.5;

      final fusedResult = {
        'type': 'fusion_local',
        'fusionMethod': _fusionMethod,
        'predictedClass': videoConf >= audioConf
            ? videoResult['predictedClass']
            : audioResult['predictedClass'],
        'confidence': videoConf * videoWeight + audioConf * audioWeight,
        'topPredictions': videoResult['topPredictions'],
        'videoResult': videoResult,
        'audioResult': audioResult,
        'fusionAnalysis': {
          'modalityAgreement':
              videoResult['predictedClass'] == audioResult['predictedClass'],
          'agreementScore': videoConf >= audioConf ? videoConf : audioConf,
          'videoWeight': videoWeight,
          'audioWeight': audioWeight,
        },
        'source': 'hardware',
        'durationSeconds': _hardwareDuration,
      };

      setState(() => _result = fusedResult);

      String? eventType;
      EventDetectionResult? eventResult;
      if (_enableEventDetection && fusedResult['error'] != true) {
        try {
          eventResult = await _eventService.detectEventsFromLocalCamera(
            duration: _hardwareDuration,
            confidenceThreshold: 0.55,
            enableMotionFallback: false,
          );
          if (eventResult != null) {
            if (mounted) setState(() => _eventResult = eventResult);
            final strongestEvent = _selectStrongestEvent(eventResult);
            eventType = strongestEvent?.eventType;
            fusedResult['eventDetection'] = {
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
        } catch (e) {
          debugPrint('[MultimodalTesting] Hardware event detection failed: $e');
        }
      }

      final predictionId = await _historyService.saveToHistory(
        type: 'fusion_local',
        fileName: 'Device Hardware Fusion',
        filePath: 'hardware://local',
        result: fusedResult,
        source: 'hardware',
        fusionMethod: _fusionMethod,
        eventType: eventType,
        eventDetectionEnabled: _enableEventDetection,
      );

      if (eventResult != null) {
        await _saveAndNotifyEvent(
          eventResult,
          predictionId: predictionId,
          sourceType: 'fusion_local',
        );
      }
    } catch (e) {
      setState(() => _result = {
            'error': true,
            'message': 'Error capturing from hardware: $e',
          });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Widget _buildStreamInput(ColorScheme scheme, bool isDark) {
    return SizedBox(
      width: 480,
      child: GlassContainer(
        opacity: 0.22,
        padding: const EdgeInsets.all(26),
        borderRadius: BorderRadius.circular(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.merge_type_rounded,
              size: 60,
              color: scheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              "Fusion Stream",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Connect to an IP camera stream.\nBoth video and audio will be captured and fused.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 20),
            _buildFusionMethodSelector(scheme),
            const SizedBox(height: 16),
            if (_ipService.devices.isNotEmpty) ...[
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
                          items: _ipService.devices.map((d) {
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
              style: TextStyle(color: scheme.onSurface, fontSize: 14),
              onChanged: (value) {
                if (_streamError != null) {
                  setState(() => _streamError = null);
                }
              },
            ),
            if (_streamError != null) ...[
              const SizedBox(height: 8),
              Text(
                _streamError!,
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
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
                      'Enter IP:PORT to auto-complete supported HTTP camera URLs.\n'
                      'DroidCam uses port 4747, IP Webcam uses port 8080, and RTSP cameras usually use port 554.',
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
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isConnectingStream
                        ? null
                        : _isStreamConnected
                            ? _disconnectStream
                            : _connectToStream,
                    icon: _isConnectingStream
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(_isStreamConnected
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded),
                    label: Text(_isConnectingStream
                        ? 'Connecting...'
                        : _isStreamConnected
                            ? 'Disconnect'
                            : 'Connect'),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          _isStreamConnected ? scheme.error : scheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamPreview(ColorScheme scheme) {
    return SizedBox(
      width: 480,
      child: GlassContainer(
        opacity: 0.22,
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.circle, color: Colors.redAccent, size: 10),
                const SizedBox(width: 6),
                Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventDetectionToggle(ColorScheme scheme, {double width = 480}) {
    return SizedBox(
      width: width,
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

  Widget _buildStreamActionButtons(ColorScheme scheme) {
    return Column(
      children: [
        SizedBox(
          width: 480,
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
        _buildEventDetectionToggle(scheme),
        const SizedBox(height: 12),
        SizedBox(
          width: 480,
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isProcessing || !_isStreamConnected
                      ? null
                      : _processStream,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.merge_type_rounded),
                  label: Text(_isProcessing
                      ? 'Processing...'
                      : 'Analyze Stream (Fusion)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFusionMethodSelector(ColorScheme scheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              Text(
                'Fusion Method',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: _fusionMethod,
                isExpanded: true,
                underline: const SizedBox(),
                itemHeight: 56,
                dropdownColor: isDark
                    ? Color.lerp(scheme.surface, Colors.white, 0.08)
                    : Color.lerp(Colors.white, scheme.surface, 0.03),
                borderRadius: BorderRadius.circular(16),
                elevation: 8,
                items: _fusionMethods.map((method) {
                  final isSelected = method['value'] == _fusionMethod;
                  return DropdownMenuItem<String>(
                    value: method['value'],
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: isSelected
                          ? BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: scheme.primary.withOpacity(0.6),
                                  width: 2.5,
                                ),
                              ),
                            )
                          : null,
                      child: Padding(
                        padding: EdgeInsets.only(left: isSelected ? 10 : 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              method['label']!,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              method['description']!,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurface.withValues(alpha: 0.5),
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
                    setState(() {
                      _fusionMethod = value;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPreview(ColorScheme scheme) {
    return SizedBox(
      width: 440,
      child: GlassContainer(
        opacity: 0.22,
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
                    _videoFileName ?? 'Video',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: scheme.error, size: 18),
                  onPressed: _clearVideo,
                  tooltip: 'Remove video',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            if (_videoInitialized && _videoController != null) ...[
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
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            _videoController!.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.white,
                            size: 24,
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

  Widget _buildAudioPreview(ColorScheme scheme) {
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
                Icon(Icons.audiotrack, color: scheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _audioFileName ?? 'Audio',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: scheme.error, size: 18),
                  onPressed: _clearAudio,
                  tooltip: 'Remove audio',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedBuilder(
                animation: _waveController,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(double.infinity, 60),
                    painter: _WaveformPainter(
                      progress: _waveController.value,
                      color: scheme.primary,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(ColorScheme scheme) {
    final hasFiles = _fusionMode == 'single'
        ? _videoFilePath != null
        : (_videoFilePath != null || _audioFilePath != null);

    return Column(
      children: [
        SizedBox(
          width: 480,
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
        if (_fusionMode == 'single') ...[
          SizedBox(
            width: 480,
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
                          "Multi-Scene Classification",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          "Detect scene transitions with fusion",
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _multiSceneMode,
                    onChanged: (value) {
                      setState(() {
                        _multiSceneMode = value;
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
        ],
        _buildEventDetectionToggle(scheme),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LiquidGlassButton(
              onPressed: _isProcessing || !hasFiles ? null : _processMultimodal,
              isLoading: _isProcessing,
              icon: _multiSceneMode
                  ? Icons.layers
                  : (_fusionMode == 'single'
                      ? Icons.merge_type
                      : Icons.analytics_outlined),
              label: _isProcessing
                  ? (_multiSceneMode ? "Analyzing Scenes..." : "Processing...")
                  : (_multiSceneMode
                      ? "Detect Scenes (Fusion)"
                      : (_fusionMode == 'single'
                          ? "Run Fusion Analysis"
                          : "Classify Multimodal")),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResults(ColorScheme scheme, bool isDark) {
    final isError = _result?['error'] == true;
    final isDemo = _result?['isDemo'] == true;
    final isFusion = _result?['type'] == 'fusion' ||
        _result?['type'] == 'fusion_multiscene' ||
        _result?['type'] == 'fusion_stream';
    final isMultiscene = _result?['type'] == 'fusion_multiscene' ||
        _result?['isMultiscene'] == true;

    return SizedBox(
      width: isMultiscene ? 540.0 : 480.0,
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
                  isError ? Icons.error_outline : Icons.check_circle_outline,
                  color: isError ? scheme.error : scheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isError
                        ? "Error"
                        : (isMultiscene
                            ? "Multi-Scene Fusion Result"
                            : (isFusion
                                ? "Fusion Classification Result"
                                : "Multimodal Classification Result")),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                if (isDemo) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.3)),
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
            if (isDemo) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: scheme.primary.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⚠ Server not connected — showing demo data',
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_result?['connectionError'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${_result!['connectionError']}',
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: 11,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (isError)
              Text(
                _result?['message'] ?? 'Unknown error',
                style: TextStyle(color: scheme.error),
              )
            else ...[
              _buildResultRow(
                "Predicted Class",
                _result?['predictedClass']?.toString().toUpperCase() ?? 'N/A',
                scheme,
                isHighlighted: true,
              ),
              const SizedBox(height: 12),
              _buildResultRow(
                "Confidence",
                "${((_result?['confidence'] ?? 0) * 100).toStringAsFixed(1)}%",
                scheme,
              ),
              if (isFusion && _result?['fusionMethod'] != null) ...[
                const SizedBox(height: 12),
                _buildResultRow(
                  "Fusion Method",
                  _result!['fusionMethod'].toString().toUpperCase(),
                  scheme,
                ),
              ],
              if (isFusion && _result?['fusionAnalysis'] != null) ...[
                const SizedBox(height: 20),
                _buildFusionAnalysis(scheme),
              ],
              if (isFusion &&
                  (_result?['videoResult'] != null ||
                      _result?['audioResult'] != null)) ...[
                const SizedBox(height: 20),
                _buildModalityResults(scheme, isDark),
              ],
              if (isMultiscene && _result?['detectedScenes'] != null) ...[
                const SizedBox(height: 20),
                _buildMultiSceneResults(scheme, isDark),
              ],
              if (isMultiscene && _result?['segmentPredictions'] != null) ...[
                const SizedBox(height: 20),
                _buildSegmentTimeline(scheme, isDark),
              ],
              if (_result?['topPredictions'] != null) ...[
                const SizedBox(height: 20),
                Text(
                  "Fused Top Predictions",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                ...(_result?['topPredictions'] as List).map((pred) {
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
                              color: scheme.onSurface.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: confidence / 100,
                              backgroundColor:
                                  scheme.onSurface.withValues(alpha: 0.1),
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
                              color: scheme.onSurface.withValues(alpha: 0.7),
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
              if (isDemo && _result?['message'] != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: Colors.orange, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _result!['message'],
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontSize: 12,
                              ),
                            ),
                            if (_result?['connectionError'] != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Error: ${_result!['connectionError']}',
                                style: TextStyle(
                                  color: Colors.orange.shade600,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(
    String label,
    String value,
    ColorScheme scheme, {
    bool isHighlighted = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(
                vertical: isHighlighted ? 6 : 4,
                horizontal: isHighlighted ? 12 : 8,
              ),
              decoration: BoxDecoration(
                color: isHighlighted
                    ? scheme.primary.withValues(alpha: 0.08)
                    : scheme.onSurface.withValues(alpha: 0.1),
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
      ),
    );
  }

  Widget _buildFusionAnalysis(ColorScheme scheme) {
    final analysis = _result?['fusionAnalysis'] as Map<String, dynamic>?;
    if (analysis == null) return const SizedBox();

    final agreement = analysis['modalityAgreement'] == true;
    final videoWeight = (analysis['videoWeight'] ?? 0.5) * 100;
    final audioWeight = (analysis['audioWeight'] ?? 0.5) * 100;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                "Fusion Analysis",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                agreement ? Icons.check_circle : Icons.compare_arrows,
                size: 16,
                color: agreement ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                agreement
                    ? "Video & Audio models agree"
                    : "Video & Audio models disagree",
                style: TextStyle(
                  fontSize: 13,
                  color: agreement ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Modality Weights",
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.videocam, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: videoWeight / 100,
                    backgroundColor: scheme.onSurface.withValues(alpha: 0.1),
                    color: Colors.blue,
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "${videoWeight.toStringAsFixed(1)}%",
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.audiotrack, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: audioWeight / 100,
                    backgroundColor: scheme.onSurface.withValues(alpha: 0.1),
                    color: scheme.primary,
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "${audioWeight.toStringAsFixed(1)}%",
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModalityResults(ColorScheme scheme, bool isDark) {
    final videoResult = _result?['videoResult'] as Map<String, dynamic>?;
    final audioResult = _result?['audioResult'] as Map<String, dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Individual Modality Results",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (videoResult != null)
              Expanded(
                child: _buildModalityCard(
                  "Video Model",
                  Icons.videocam,
                  Colors.blue,
                  videoResult,
                  scheme,
                ),
              ),
            if (videoResult != null && audioResult != null)
              const SizedBox(width: 12),
            if (audioResult != null)
              Expanded(
                child: _buildModalityCard(
                  "Audio Model",
                  Icons.audiotrack,
                  Colors.green,
                  audioResult,
                  scheme,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildModalityCard(
    String title,
    IconData icon,
    Color color,
    Map<String, dynamic> result,
    ColorScheme scheme,
  ) {
    final predictedClass = result['predictedClass'] ?? 'N/A';
    final confidence = (result['confidence'] ?? 0) * 100;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            predictedClass.toString().toUpperCase(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "${confidence.toStringAsFixed(1)}%",
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiSceneResults(ColorScheme scheme, bool isDark) {
    final detectedScenes = _result?['detectedScenes'] as List? ?? [];
    final summary = _result?['summary'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.layers, color: scheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              "Detected Scenes",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "${detectedScenes.length} scene${detectedScenes.length != 1 ? 's' : ''}",
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (summary != null) ...[
          const SizedBox(height: 8),
          Text(
            summary,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withOpacity(0.6),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 12),
        ...detectedScenes.map((scene) {
          final className = scene['class'] ?? 'Unknown';
          final maxConf =
              ((scene['maxConfidence'] ?? 0) * 100).toStringAsFixed(1);
          final pct = (scene['percentageOfVideo'] ?? 0).toStringAsFixed(0);
          final occurrences = scene['occurrences'] ?? 0;
          final agreement = scene['fusionAgreement'] ?? true;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(isDark ? 0.08 : 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.primary.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: agreement ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          className.toString().toUpperCase(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "$occurrences segment${occurrences != 1 ? 's' : ''} · $pct% of video",
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "$maxConf%",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            agreement
                                ? Icons.check_circle
                                : Icons.warning_amber,
                            size: 12,
                            color: agreement ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            agreement ? "Agreed" : "Diverged",
                            style: TextStyle(
                              fontSize: 10,
                              color: agreement ? Colors.green : Colors.orange,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSegmentTimeline(ColorScheme scheme, bool isDark) {
    final segments = _result?['segmentPredictions'] as List? ?? [];
    if (segments.isEmpty) return const SizedBox();

    final sceneColors = <String, Color>{};
    final palette = [
      scheme.primary,
      const Color(0xFF2E7D32),
      const Color(0xFFE65100),
      const Color(0xFF1565C0),
      const Color(0xFF6A1B9A),
      const Color(0xFF00796B),
      const Color(0xFFC62828),
      const Color(0xFFFF8F00),
    ];
    var colorIdx = 0;

    for (final seg in segments) {
      final cls = seg['fusedClass'] ?? seg['predictedClass'] ?? '';
      if (!sceneColors.containsKey(cls)) {
        sceneColors[cls] = palette[colorIdx % palette.length];
        colorIdx++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Segment Timeline",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 24,
            child: Row(
              children: segments.map((seg) {
                final cls = seg['fusedClass'] ?? seg['predictedClass'] ?? '';
                return Expanded(
                  child: Tooltip(
                    message:
                        "$cls (${((seg['fusedConfidence'] ?? seg['confidence'] ?? 0) * 100).toStringAsFixed(1)}%)",
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 0.5),
                      color: sceneColors[cls] ?? Colors.grey,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: sceneColors.entries.map((entry) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: entry.value,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        ...segments.asMap().entries.map((entry) {
          final idx = entry.key;
          final seg = entry.value;
          final cls = seg['fusedClass'] ?? seg['predictedClass'] ?? '';
          final conf =
              ((seg['fusedConfidence'] ?? seg['confidence'] ?? 0) * 100)
                  .toStringAsFixed(1);
          final start = (seg['startTime'] ?? 0).toStringAsFixed(1);
          final end = (seg['endTime'] ?? 0).toStringAsFixed(1);
          final agreement = seg['agreement'] ?? true;

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: (sceneColors[cls] ?? Colors.grey).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      "${idx + 1}",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: sceneColors[cls] ?? Colors.grey,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "${start}s–${end}s",
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withOpacity(0.5),
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cls.toString().toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sceneColors[cls] ?? scheme.onSurface,
                    ),
                  ),
                ),
                Icon(
                  agreement
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_rounded,
                  size: 14,
                  color: agreement ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  "$conf%",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;

  _WaveformPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const barCount = 30;
    final barWidth = size.width / barCount;

    for (int i = 0; i < barCount; i++) {
      final x = i * barWidth + barWidth / 2;
      final phase = (progress * 2 * 3.14159) + (i * 0.2);
      final amplitude = (size.height / 3) * (0.3 + 0.7 * ((i % 4 + 1) / 4));
      final y = size.height / 2 + amplitude * _sin(phase);

      canvas.drawLine(
        Offset(x, size.height / 2 - y.abs() / 2),
        Offset(x, size.height / 2 + y.abs() / 2),
        paint,
      );
    }
  }

  double _sin(double x) {
    x = x % (2 * 3.14159);
    if (x > 3.14159) x -= 2 * 3.14159;
    return x - (x * x * x) / 6 + (x * x * x * x * x) / 120;
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _LiquidGlassButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData icon;
  final String label;

  const _LiquidGlassButton({
    required this.onPressed,
    this.isLoading = false,
    required this.icon,
    required this.label,
  });

  @override
  State<_LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<_LiquidGlassButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _disabled => widget.onPressed == null && !widget.isLoading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(
        scale: _scale.value,
        child: child,
      ),
      child: Opacity(
        opacity: _disabled ? 0.45 : 1.0,
        child: GestureDetector(
          onTapDown: _disabled ? null : (_) => _ctrl.forward(),
          onTapUp: _disabled ? null : (_) => _ctrl.reverse(),
          onTapCancel: _disabled ? null : () => _ctrl.reverse(),
          onTap: _disabled
              ? null
              : () {
                  if (!widget.isLoading) widget.onPressed?.call();
                },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.isLoading) ...[
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ] else ...[
                      Icon(widget.icon, size: 20, color: Colors.white),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
