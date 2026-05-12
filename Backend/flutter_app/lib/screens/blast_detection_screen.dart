import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/theme_controller.dart';
import '../widgets/glass_container.dart';
import '../widgets/background_blobs.dart';
import '../services/video_classifier_service.dart';

class BlastDetectionScreen extends StatefulWidget {
  const BlastDetectionScreen({super.key});

  @override
  State<BlastDetectionScreen> createState() => _BlastDetectionScreenState();
}

class _BlastDetectionScreenState extends State<BlastDetectionScreen>
    with SingleTickerProviderStateMixin {
  final VideoClassifierService _classifier = VideoClassifierService();

  String? _selectedFilePath;
  String? _fileName;
  bool _isProcessing = false;
  Map<String, dynamic>? _result;
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _showAlert = false;
  late AnimationController _alertAnimationController;
  late Animation<double> _alertAnimation;

  bool _isStreamMode = false;
  final TextEditingController _streamUrlController = TextEditingController();
  bool _isStreamConnected = false;
  int _streamDuration = 5;

  @override
  void initState() {
    super.initState();
    _alertAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _alertAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _alertAnimationController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _alertAnimationController.dispose();
    _streamUrlController.dispose();
    super.dispose();
  }

  String _normalizeStreamUrl(String url) {
    String normalized = url.trim();

    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }

    final uri = Uri.tryParse(normalized);
    if (uri != null) {
      if ((uri.port == 4747 || uri.port == 8080) &&
          !normalized.endsWith('/video') &&
          !normalized.contains('/video?')) {
        normalized = '$normalized/video';
      }
    }

    return normalized;
  }

  void _connectToStream() {
    final url = _normalizeStreamUrl(_streamUrlController.text);
    if (url.isEmpty) return;

    setState(() {
      _isStreamConnected = true;
      _result = null;
      _showAlert = false;
    });
  }

  void _disconnectStream() {
    setState(() {
      _isStreamConnected = false;
      _result = null;
      _showAlert = false;
    });
  }

  Future<void> _analyzeStream() async {
    final url = _normalizeStreamUrl(_streamUrlController.text);
    if (url.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _result = null;
      _showAlert = false;
    });

    try {
      final result = await _classifier.detectAnomalyStream(
        url,
        durationSeconds: _streamDuration,
      );
      setState(() {
        _result = result;
      });

      if (result['blastDetected'] == true) {
        setState(() {
          _showAlert = true;
        });
        _alertAnimationController.forward(from: 0);
      }
    } catch (e) {
      setState(() {
        _result = {
          'error': true,
          'message': 'Error analyzing stream: $e',
        };
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

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

  Future<void> _handleFileSelected(String path, String name) async {
    setState(() {
      _selectedFilePath = path;
      _fileName = name;
      _result = null;
      _videoInitialized = false;
      _showAlert = false;
    });

    _videoController?.dispose();
    _videoController = VideoPlayerController.file(File(path));

    try {
      await _videoController!.initialize();
      setState(() {
        _videoInitialized = true;
      });
    } catch (e) {
      debugPrint('Error initializing video: $e');
    }
  }

  Future<void> _analyzeVideo() async {
    if (_selectedFilePath == null) return;

    setState(() {
      _isProcessing = true;
      _result = null;
      _showAlert = false;
    });

    try {
      final result = await _classifier.detectAnomalies(_selectedFilePath!);
      setState(() {
        _result = result;
      });

      if (result['blastDetected'] == true) {
        setState(() {
          _showAlert = true;
        });
        _alertAnimationController.forward(from: 0);
      }
    } catch (e) {
      setState(() {
        _result = {
          'error': true,
          'message': 'Error analyzing video: $e',
        };
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _clearSelection() {
    _videoController?.dispose();
    _videoController = null;
    setState(() {
      _selectedFilePath = null;
      _fileName = null;
      _result = null;
      _videoInitialized = false;
      _showAlert = false;
    });
  }

  Future<void> _call911() async {
    final Uri phoneUri = Uri(scheme: 'tel', path: '911');
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    } else {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.red.shade900,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.emergency, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Text('Emergency Call', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: const Text(
              'Please dial 911 immediately!\n\nOn desktop, automatic dialing is not available.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasFile = _selectedFilePath != null;
    final hasStreamInput = _isStreamMode && _isStreamConnected;

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
                  child: (hasFile || hasStreamInput)
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Column(
                              children: [
                                if (_isStreamMode)
                                  _buildStreamInputSection(scheme, isDark)
                                else
                                  _buildVideoPreviewWithBoxes(scheme),
                                const SizedBox(height: 20),
                                if (_isStreamMode)
                                  _buildStreamActionButtons(scheme)
                                else
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
                      : Center(child: _buildUploadSection(scheme, isDark)),
                ),
              ],
            ),
          ),
          if (_showAlert) _buildEmergencyAlert(scheme),
        ],
      ),
    );
  }

  Widget _buildNavbar(BuildContext context) {
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
          const Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 24),
          const SizedBox(width: 8),
          Text(
            "Blast Detection - Digital Twin",
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

  Widget _buildUploadSection(ColorScheme scheme, bool isDark) {
    return GlassContainer(
      opacity: 0.22,
      padding: const EdgeInsets.all(30),
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_fire_department_rounded,
                size: 60,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "Blast/Explosion Detection",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Upload a video or use an IP stream to detect\nexplosions, blasts, or sudden bright flashes.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurface.withOpacity(0.7),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isStreamMode = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: !_isStreamMode
                              ? Colors.orange
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.video_file_rounded,
                              color: !_isStreamMode
                                  ? Colors.white
                                  : scheme.onSurface.withOpacity(0.6),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Video File",
                              style: TextStyle(
                                color: !_isStreamMode
                                    ? Colors.white
                                    : scheme.onSurface.withOpacity(0.6),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isStreamMode = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _isStreamMode
                              ? Colors.orange
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.wifi_tethering_rounded,
                              color: _isStreamMode
                                  ? Colors.white
                                  : scheme.onSurface.withOpacity(0.6),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "IP Stream",
                              style: TextStyle(
                                color: _isStreamMode
                                    ? Colors.white
                                    : scheme.onSurface.withOpacity(0.6),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_isStreamMode) ...[
              TextField(
                controller: _streamUrlController,
                decoration: InputDecoration(
                  hintText: '192.168.1.100:4747',
                  labelText: 'Stream URL',
                  prefixIcon: const Icon(Icons.link),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.help_outline),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Stream URL Help'),
                          content: const Text(
                            'Enter your IP camera stream URL:\n\n'
                            '• DroidCam: 192.168.x.x:4747\n'
                            '• IP Webcam: 192.168.x.x:8080\n'
                            '• RTSP: rtsp://...\n\n'
                            'http:// and /video will be added automatically for DroidCam.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest.withOpacity(0.3),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Capture Duration:',
                    style: TextStyle(color: scheme.onSurface.withOpacity(0.8)),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _streamDuration,
                    items: [3, 5, 10, 15, 20, 30]
                        .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text('$d seconds'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _streamDuration = v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _streamUrlController.text.isNotEmpty
                    ? _connectToStream
                    : null,
                icon: const Icon(Icons.wifi_tethering_rounded),
                label: const Text("Connect to Stream"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.video_library_rounded),
                label: const Text("Select Video"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.security, color: Colors.red, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Part of Semantic-Aware Digital Twin\nfor emergency scene classification",
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
        ),
      ),
    );
  }

  Widget _buildVideoPreviewWithBoxes(ColorScheme scheme) {
    final boxes = _result?['primaryDetection']?['boundingBoxes'] as List? ?? [];
    final videoInfo = _result?['videoInfo'];

    return SizedBox(
      width: 560,
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
            if (_videoInitialized && _videoController != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: Stack(
                        children: [
                          VideoPlayer(_videoController!),
                          if (boxes.isNotEmpty && videoInfo != null)
                            CustomPaint(
                              size: Size.infinite,
                              painter: BoundingBoxPainter(
                                boxes: boxes,
                                videoWidth:
                                    (videoInfo['width'] ?? 1920).toDouble(),
                                videoHeight:
                                    (videoInfo['height'] ?? 1080).toDouble(),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            if (_videoController!.value.isPlaying) {
                              _videoController!.pause();
                            } else {
                              _videoController!.play();
                            }
                          });
                        },
                        child: Center(
                          child: AnimatedOpacity(
                            opacity: _videoController!.value.isPlaying ? 0 : 1,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                          ),
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

  Widget _buildActionButtons(ColorScheme scheme) {
    return ElevatedButton.icon(
      onPressed: _isProcessing ? null : _analyzeVideo,
      icon: _isProcessing
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onPrimary,
              ),
            )
          : const Icon(Icons.shield_rounded),
      label: Text(_isProcessing
          ? "Analyzing for threats..."
          : "Detect Blast/Explosion"),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  Widget _buildResults(ColorScheme scheme, bool isDark) {
    final isError = _result?['error'] == true;
    final blastDetected = _result?['blastDetected'] == true;
    final alertLevel = _result?['alertLevel'] ?? 'NORMAL';
    final isDemo = _result?['isDemo'] == true;

    return SizedBox(
      width: 560,
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
                      : (blastDetected
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline),
                  color: isError
                      ? scheme.error
                      : (blastDetected ? Colors.red : Colors.green),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isError
                        ? "Error"
                        : (blastDetected
                            ? "⚠️ THREAT DETECTED"
                            : "No Threat Detected"),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: blastDetected ? Colors.red : scheme.onSurface,
                    ),
                  ),
                ),
                if (alertLevel == 'CRITICAL') ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "CRITICAL",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                if (isDemo) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "DEMO",
                      style: TextStyle(
                        color: Colors.orange,
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
              Text(_result?['message'] ?? 'Unknown error',
                  style: TextStyle(color: scheme.error))
            else ...[
              _buildInfoRow(
                  "Confidence",
                  "${((_result?['maxConfidence'] ?? 0) * 100).toStringAsFixed(0)}%",
                  scheme),
              const SizedBox(height: 8),
              _buildInfoRow("Total Detections",
                  "${_result?['totalDetections'] ?? 0}", scheme),
              if (_result?['primaryDetection'] != null) ...[
                const SizedBox(height: 8),
                _buildInfoRow(
                    "First Detection At",
                    "${_result?['primaryDetection']?['timestamp'] ?? 0}s",
                    scheme),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: blastDetected
                      ? Colors.red.withOpacity(0.15)
                      : Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: blastDetected
                        ? Colors.red.withOpacity(0.4)
                        : Colors.green.withOpacity(0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      blastDetected ? Icons.emergency : Icons.verified_user,
                      color: blastDetected ? Colors.red : Colors.green,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _result?['emergencyAction']?['message'] ?? '',
                        style: TextStyle(
                          color: blastDetected ? Colors.red : Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (blastDetected) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _call911,
                    icon: const Icon(Icons.phone, size: 24),
                    label:
                        const Text("Call 911", style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStreamInputSection(ColorScheme scheme, bool isDark) {
    return SizedBox(
      width: 560,
      child: GlassContainer(
        opacity: 0.18,
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi_tethering_rounded,
                    color: scheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Stream Input',
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
            const SizedBox(height: 12),
            TextField(
              controller: _streamUrlController,
              enabled: !_isProcessing,
              decoration: InputDecoration(
                hintText: 'Stream URL',
                labelText: 'Connected Stream',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withOpacity(0.3),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Capture Duration: $_streamDuration seconds',
              style: TextStyle(color: scheme.onSurface.withOpacity(0.8)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamActionButtons(ColorScheme scheme) {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: _isProcessing ? null : _analyzeStream,
          icon: _isProcessing
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onPrimary,
                  ),
                )
              : const Icon(Icons.shield_rounded),
          label: Text(_isProcessing
              ? "Analyzing stream..."
              : "Detect Blast/Explosion from Stream"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _disconnectStream,
          icon: const Icon(Icons.close),
          label: const Text("Disconnect Stream"),
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, ColorScheme scheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: scheme.onSurface.withOpacity(0.7))),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w600, color: scheme.onSurface)),
      ],
    );
  }

  Widget _buildEmergencyAlert(ColorScheme scheme) {
    return AnimatedBuilder(
      animation: _alertAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _alertAnimation.value,
          child: Transform.scale(
            scale: 0.8 + (_alertAnimation.value * 0.2),
            child: child,
          ),
        );
      },
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red.shade800, Colors.red.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.5),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 80,
                ),
                const SizedBox(height: 20),
                const Text(
                  "⚠️ EMERGENCY ALERT",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Explosion/Blast Detected!",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Confidence: ${((_result?['maxConfidence'] ?? 0) * 100).toStringAsFixed(0)}%",
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _call911,
                      icon: const Icon(Icons.phone, size: 28),
                      label: const Text("CALL 911",
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _showAlert = false;
                    });
                  },
                  child: const Text(
                    "Dismiss Alert",
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List boxes;
  final double videoWidth;
  final double videoHeight;

  BoundingBoxPainter({
    required this.boxes,
    required this.videoWidth,
    required this.videoHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final fillPaint = Paint()
      ..color = Colors.red.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (var box in boxes) {
      final scaleX = size.width / videoWidth;
      final scaleY = size.height / videoHeight;

      final x = (box['x'] as num).toDouble() * scaleX;
      final y = (box['y'] as num).toDouble() * scaleY;
      final w = (box['width'] as num).toDouble() * scaleX;
      final h = (box['height'] as num).toDouble() * scaleY;
      final confidence = (box['confidence'] as num?)?.toDouble() ?? 0;

      final rect = Rect.fromLTWH(x, y, w, h);

      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, paint);

      textPainter.text = TextSpan(
        text: " BLAST ${(confidence * 100).toStringAsFixed(0)}% ",
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.red,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x, y - 20));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
