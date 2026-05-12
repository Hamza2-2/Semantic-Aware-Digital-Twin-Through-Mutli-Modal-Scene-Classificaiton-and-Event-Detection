// file header note
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
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

class AudioTestingScreen extends StatefulWidget {
  const AudioTestingScreen({super.key});

  @override
  State<AudioTestingScreen> createState() => _AudioTestingScreenState();
}

class _AudioTestingScreenState extends State<AudioTestingScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  final VideoClassifierService _classifier = VideoClassifierService();
  final PredictionHistoryService _historyService = PredictionHistoryService();
  final IpAddressService _ipService = IpAddressService();
  final EventDetectionService _eventService = EventDetectionService();

  
  bool _enableEventDetection = true;
  EventDetectionResult? _eventResult;
  GeoLocation? _currentLocation;

  String? _selectedFilePath;
  String? _fileName;
  bool _isProcessing = false;
  Map<String, dynamic>? _result;

  
  bool _isStreamMode = false;
  bool _isHardwareMode = false;
  bool _laptopMicEnabled = true;
  final TextEditingController _streamUrlController = TextEditingController();
  int _streamDuration = 10;
  String? _streamError;

  
  bool _isStreamConnected = false;
  bool _isConnectingStream = false;
  String? _connectionInfo;

  late AnimationController _waveController;

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
    setState(() {
      _laptopMicEnabled = micEnabled;
      if (_isHardwareMode && !micEnabled) {
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

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _waveController.dispose();
    _streamUrlController.dispose();
    super.dispose();
  }

  String _normalizeStreamUrl(String url) {
    return StreamUrlFormatter.normalizeAudio(url);
  }

  
  Future<void> _connectToAudioStream() async {
    var url = _streamUrlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _streamError = 'Please enter a stream URL';
      });
      return;
    }

    
    final normalizedUrl = _normalizeStreamUrl(url);

    setState(() {
      _isConnectingStream = true;
      _streamError = null;
      _connectionInfo = null;
    });

    final client = http.Client();
    try {
      final audioUri = Uri.parse(normalizedUrl);

      
      
      Uri checkUri;
      if (audioUri.scheme == 'rtsp') {
        
        checkUri = Uri(
          scheme: 'http',
          host: audioUri.host,
          port: audioUri.port,
          path: '/status.json', 
        );
      } else if (audioUri.port == 8080) {
        
        checkUri = Uri(
          scheme: 'http',
          host: audioUri.host,
          port: audioUri.port,
          path: '/audio.wav',
        );
      } else {
        
        checkUri = Uri(
          scheme: 'http',
          host: audioUri.host,
          port: audioUri.port,
          path: '/',
        );
      }

      final request =
          http.Request('HEAD', checkUri); 
      final streamed = await client.send(request).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Connection timed out'),
          );

      
      if (streamed.statusCode < 400) {
        
        String? mlWarning;
        try {
          final mlUrl = _eventService.mlServerUrl;
          await http
              .get(Uri.parse('$mlUrl/classes'))
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          mlWarning =
              'Warning: Inference server not running at ${_eventService.mlServerUrl}';
        }

        final audioInfo = audioUri.scheme == 'rtsp'
            ? 'RTSP audio stream'
            : 'Audio: ${audioUri.path}';
        setState(() {
          _isStreamConnected = true;
          _isConnectingStream = false;
          _connectionInfo =
              'Device reachable at ${audioUri.host}:${audioUri.port} · $audioInfo';
          if (mlWarning != null) _streamError = mlWarning;
        });
        if (mounted) {
          if (mlWarning != null) {
            showGlassSnackBar(
              context,
              'Device reachable but inference server is not running.\\n'
              'Start: python inference_server.py',
              isError: true,
            );
          } else {
            showGlassSnackBar(
              context,
              'Device reachable: ${audioUri.host}:${audioUri.port}',
              icon: Icons.check_circle_rounded,
              iconColor: Colors.green,
            );
          }
        }
      } else {
        throw Exception('Device returned ${streamed.statusCode}');
      }
    } catch (e) {
      String errorMsg = e.toString();
      if (errorMsg.contains('SocketException') ||
          errorMsg.contains('Connection refused')) {
        errorMsg = 'Cannot reach device. Is IP Webcam or DroidCam running?';
      } else if (errorMsg.contains('timed out')) {
        errorMsg = 'Connection timed out. Check network.';
      }
      setState(() {
        _isConnectingStream = false;
        _streamError = errorMsg;
      });
      if (mounted) {
        showGlassSnackBar(context, errorMsg, isError: true);
      }
    } finally {
      client.close();
    }
  }

  
  void _disconnectAudioStream() {
    setState(() {
      _isStreamConnected = false;
      _connectionInfo = null;
      _streamError = null;
      _result = null;
      _eventResult = null;
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      _handleFileSelected(file.path!, file.name);
    }
  }

  void _handleFileSelected(String path, String name) {
    setState(() {
      _selectedFilePath = path;
      _fileName = name;
      _result = null;
    });
  }

  Future<void> _processAudio() async {
    if (_selectedFilePath == null) return;

    setState(() {
      _isProcessing = true;
      _result = null;
      _eventResult = null;
    });

    try {
      final result = await _classifier.classifyAudio(_selectedFilePath!);

      
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

      setState(() {
        _result = result;
      });

      
      final predictionId = await _historyService.saveToHistory(
        type: 'audio',
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
          sourceType: 'audio',
        );
      }
    } catch (e) {
      setState(() {
        _result = {
          'error': true,
          'message': 'Error processing audio: $e',
        };
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _processAudioStream() async {
    final url = _normalizeStreamUrl(_streamUrlController.text.trim());
    if (url.isEmpty) {
      setState(() {
        _streamError = 'Please enter a stream URL';
      });
      return;
    }

    
    try {
      final mlUrl = _eventService.mlServerUrl;
      await http
          .get(Uri.parse('$mlUrl/classes'))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      setState(() {
        _streamError =
            'Inference server not reachable at ${_eventService.mlServerUrl}. '
            'Start: python inference_server.py';
      });
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
      _streamError = null;
      _eventResult = null;
    });

    try {
      Map<String, dynamic> result;
      String? eventType;
      EventDetectionResult? eventResult;

      
      if (_enableEventDetection) {
        eventResult = await _runEventDetectionForStream(url);
        if (eventResult != null) {
          final strongestEvent = _selectStrongestEvent(eventResult);
          eventType = strongestEvent?.eventType;
          
          
          result = {
            'type': 'audio_stream',
            'predictedClass': eventResult.sceneClass,
            'confidence': eventResult.sceneConfidence,
            'topPredictions': eventResult.topPredictions,
          };
        } else {
          
          result = await _classifier.classifyAudioStream(url,
              durationSeconds: _streamDuration);
        }
      } else {
        result = await _classifier.classifyAudioStream(url,
            durationSeconds: _streamDuration);
      }

      setState(() {
        _result = result;
      });

      
      final predictionId = await _historyService.saveToHistory(
        type: 'audio_stream',
        fileName: 'Audio Stream',
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
          sourceType: 'audio_stream',
        );
      }
    } catch (e) {
      setState(() {
        _result = {
          'error': true,
          'message': 'Error processing audio stream: $e',
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
      final eventResult = await _eventService.detectEventsInAudioStream(
        streamUrl,
        duration: _streamDuration,
        confidenceThreshold: 0.005,
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
      debugPrint('[AudioTesting] Stream event detection failed: $e');
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
      debugPrint('[AudioTesting] File event detection failed: $e');
      return null;
    }
  }

  
  Future<void> _saveAndNotifyEvent(
    EventDetectionResult eventResult, {
    String? predictionId,
    String? streamUrl,
    String sourceType = 'audio',
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

  void _clearSelection() {
    setState(() {
      _selectedFilePath = null;
      _fileName = null;
      _result = null;
    });
  }

  
  Future<void> _processHardwareMic() async {
    
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
      _eventResult = null;
    });

    try {
      Map<String, dynamic> result;
      String? eventType;
      EventDetectionResult? eventResult;

      if (_enableEventDetection) {
        eventResult = await _eventService.detectEventsFromLocalMic(
          duration: _streamDuration,
          confidenceThreshold: 0.50,
        );
        if (eventResult != null) {
          final strongestEvent = _selectStrongestEvent(eventResult);
          eventType = strongestEvent?.eventType;
          result = {
            'type': 'audio_local',
            'source': 'laptop_microphone',
            'predictedClass': eventResult.sceneClass,
            'confidence': eventResult.sceneConfidence,
            'topPredictions': eventResult.topPredictions,
          };
        } else {
          result = await _classifier.classifyAudioLocal(
              durationSeconds: _streamDuration);
        }
      } else {
        result = await _classifier.classifyAudioLocal(
            durationSeconds: _streamDuration);
      }

      setState(() => _result = result);

      final predictionId = await _historyService.saveToHistory(
        type: 'audio_local',
        fileName: 'Laptop Microphone',
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
          sourceType: 'audio_local',
        );
      }
    } catch (e) {
      setState(() {
        _result = {
          'error': true,
          'message': 'Error processing microphone audio: $e',
        };
      });
    } finally {
      setState(() => _isProcessing = false);
    }
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
                                _buildHardwareMicPanel(scheme, isDark),
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
                                      _buildAudioStreamPreview(scheme),
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

  Widget _buildHardwareMicPanel(ColorScheme scheme, bool isDark) {
    return SizedBox(
      width: 440,
      child: GlassContainer(
        opacity: 0.22,
        padding: const EdgeInsets.all(26),
        borderRadius: BorderRadius.circular(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_rounded, size: 60, color: scheme.primary),
            const SizedBox(height: 18),
            Text(
              'Record from Laptop Microphone',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Uses your device\'s built-in or connected\nmicrophone for audio classification.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer_outlined,
                    size: 18, color: scheme.onSurface.withOpacity(0.7)),
                const SizedBox(width: 8),
                Text(
                  'Duration: ${_streamDuration}s',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: _streamDuration.toDouble(),
              min: 5,
              max: 30,
              divisions: 5,
              label: '${_streamDuration}s',
              onChanged: (v) => setState(() => _streamDuration = v.toInt()),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isProcessing ? null : _processHardwareMic,
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
              icon: Icons.audio_file_outlined,
              label: "Audio File",
              isSelected: !_isStreamMode && !_isHardwareMode,
              onTap: () {
                if (_isStreamMode || _isHardwareMode) {
                  setState(() {
                    _isStreamMode = false;
                    _isHardwareMode = false;
                    _result = null;
                    _streamError = null;
                  });
                }
              },
            ),
            _buildModeButton(
              scheme: scheme,
              icon: Icons.stream,
              label: "IP Stream",
              isSelected: _isStreamMode,
              onTap: () {
                if (!_isStreamMode) {
                  setState(() {
                    _isStreamMode = true;
                    _isHardwareMode = false;
                    _result = null;
                  });
                }
              },
            ),
            if (_laptopMicEnabled)
              _buildModeButton(
                scheme: scheme,
                icon: Icons.mic_rounded,
                label: "Device Mic",
                isSelected: _isHardwareMode,
                onTap: () {
                  if (!_isHardwareMode) {
                    setState(() {
                      _isHardwareMode = true;
                      _isStreamMode = false;
                      _result = null;
                      _streamError = null;
                    });
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

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
              Icons.mic_rounded,
              size: 60,
              color: scheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              "Connect to Audio Stream",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Enter your DroidCam, IP Webcam, or other\nnetwork stream URL for live audio testing.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 20),
            if (_ipService.devicesForModality('audio').isNotEmpty) ...[
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
                              _ipService.devicesForModality('audio').map((d) {
                            return DropdownMenuItem<String>(
                              value: d.audioStreamUrl,
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
                                
                                _isStreamConnected = false;
                                _connectionInfo = null;
                                _streamError = null;
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
                
                if (_isStreamConnected || _streamError != null) {
                  setState(() {
                    _isStreamConnected = false;
                    _connectionInfo = null;
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
                onPressed: _disconnectAudioStream,
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
                onPressed: (_isConnectingStream ||
                        _streamUrlController.text.trim().isEmpty)
                    ? null
                    : _connectToAudioStream,
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
                      "http:// and /audio.wav are added automatically\n"
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

  Widget _buildAudioStreamPreview(ColorScheme scheme) {
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
                    "Audio Stream Ready",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: scheme.error, size: 20),
                  onPressed: _disconnectAudioStream,
                  tooltip: 'Disconnect stream',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.primary.withOpacity(0.2)),
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
            if (_connectionInfo != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.check_circle, color: scheme.primary, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _connectionInfo!,
                      style: TextStyle(
                        color: scheme.onSurface.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

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
        _buildEventDetectionToggle(scheme),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: (_isProcessing || _streamUrlController.text.trim().isEmpty)
              ? null
              : _processAudioStream,
          icon: _isProcessing
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onPrimary,
                  ),
                )
              : const Icon(Icons.mic),
          label: Text(_isProcessing
              ? "Capturing Audio (${_streamDuration}s)..."
              : "Classify Audio Stream"),
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
              _isStreamMode ? "Live Stream - Audio" : "Upload - Audio Only",
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
                    _fileName ?? 'Selected Audio',
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
                  tooltip: 'Remove audio',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedBuilder(
                animation: _waveController,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(double.infinity, 80),
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
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
        _buildEventDetectionToggle(scheme),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _isProcessing ? null : _processAudio,
          icon: _isProcessing
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onPrimary,
                  ),
                )
              : const Icon(Icons.analytics_outlined),
          label: Text(_isProcessing ? "Processing..." : "Classify Audio"),
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

  Widget _buildResults(ColorScheme scheme, bool isDark) {
    final isError = _result?['error'] == true;
    final isDemo = _result?['isDemo'] == true && !isError;

    return SizedBox(
      width: 440,
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
                Text(
                  isError ? "Error" : "Classification Result",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                if (isDemo) ...[
                  const Spacer(),
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
              if (_result?['topPredictions'] != null) ...[
                const SizedBox(height: 20),
                Text(
                  "Top Predictions",
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
                              backgroundColor:
                                  scheme.onSurface.withOpacity(0.1),
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
                }).toList(),
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
              
              if (_result?['eventDetection'] != null) ...[
                const SizedBox(height: 20),
                Divider(color: scheme.onSurface.withOpacity(0.1)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: (_result!['eventDetection']['eventsDetected'] ==
                                true)
                            ? Colors.orange
                            : Colors.green,
                        size: 22),
                    const SizedBox(width: 10),
                    Text(
                      "Event Detection",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (_result!['eventDetection']['eventsDetected'] ==
                                true)
                            ? Colors.orange.withOpacity(0.15)
                            : Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _result!['eventDetection']['alertLevel'] ?? 'NORMAL',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: (_result!['eventDetection']
                                      ['eventsDetected'] ==
                                  true)
                              ? Colors.orange
                              : Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                if (_result!['eventDetection']['eventsDetected'] == true &&
                    _result!['eventDetection']['highestSeverityEvent'] != null)
                  Builder(builder: (context) {
                    final event = _result!['eventDetection']
                        ['highestSeverityEvent'] as Map<String, dynamic>;
                    final eventType = (event['type'] ?? 'unknown')
                        .toString()
                        .replaceAll('_', ' ')
                        .toUpperCase();
                    final conf =
                        ((event['confidence'] ?? 0) as num).toDouble() * 100;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_rounded,
                              size: 20, color: Colors.orange),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "$eventType detected",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "${conf.toStringAsFixed(1)}%",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  })
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified_rounded,
                            color: Colors.green, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          "No threats detected",
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
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

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;

  _WaveformPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const barCount = 40;
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
