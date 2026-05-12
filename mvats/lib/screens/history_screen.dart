// Prediction history list screen
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/theme_controller.dart';
import '../widgets/glass_container.dart';
import '../widgets/background_blobs.dart';
import '../services/prediction_history_service.dart';
import '../utils/glass_snackbar.dart';

class HistoryScreen extends StatefulWidget {
  final bool showClearButton;

  const HistoryScreen({super.key, this.showClearButton = true});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final PredictionHistoryService _historyService = PredictionHistoryService();
  List<Map<String, dynamic>> uploads = [];
  bool isLoading = false;
  Set<String> expandedItems = {};
  bool _hasMigrated = false;
  String _selectedFilter = 'all';
  bool _showFullDetails = true;

List<Map<String, dynamic>> get filteredUploads {
  if (_selectedFilter == 'all') return uploads;
  return uploads.where((upload) {
    final type =
        (upload['type'] ?? upload['fileType'] ?? '').toString().toLowerCase();
    if (_selectedFilter == 'video') {
      return type == 'video' || type == 'video_stream';
    }
    return type == _selectedFilter;
  }).toList();
}

  @override
  void initState() {
    super.initState();
    _loadUploadHistory();
  }

  // load data
  Future<void> _loadUploadHistory() async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _showFullDetails = prefs.getBool('show_full_prediction_details') ?? true;

      if (!_hasMigrated) {
        await _migrateOldHistory();
        _hasMigrated = true;
      }

      final history = await _historyService.getHistory();

      setState(() {
        uploads = history;
      });
    } catch (e) {
      showGlassSnackBar(context, 'Error loading history: $e', isError: true);
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _migrateOldHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final oldUploadsList = prefs.getStringList('uploads') ?? [];

      if (oldUploadsList.isEmpty) return;

      dev.log('Migrating ${oldUploadsList.length} old entries to MongoDB...',
          name: 'History');

      for (final uploadJson in oldUploadsList) {
        try {
          final upload = jsonDecode(uploadJson) as Map<String, dynamic>;

          await _historyService.saveToHistory(
            type: upload['type'] ?? upload['fileType'] ?? 'video',
            fileName: upload['fileName'] ?? 'Unknown',
            result: upload['result'] ?? upload,
            filePath: upload['filePath'],
            eventDetectionEnabled: upload['eventDetectionEnabled'] ?? true,
          );
        } catch (e) {
          dev.log('Error migrating entry: $e', name: 'History');
        }
      }

      await prefs.remove('uploads');
      dev.log('Migration complete, old data cleared', name: 'History');
    } catch (e) {
      dev.log('Migration error: $e', name: 'History');
    }
  }

  // clear data
  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.white.withValues(alpha: 0.15),
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: GlassContainer(
              borderRadius: BorderRadius.circular(28),
              blur: 20,
              opacity: 0.18,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clear History',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Are you sure you want to clear all upload history?',
                    style: TextStyle(
                      fontSize: 15,
                      color: scheme.onSurface.withValues(alpha: 0.82),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF3B30),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      await _historyService.clearHistory();
      setState(() => uploads.clear());

      showGlassSnackBar(context, 'History cleared');
    }
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
                  child: _GlassNavbar(
                      onClear: widget.showClearButton && uploads.isNotEmpty
                          ? _clearHistory
                          : null,
                      onRefresh: _loadUploadHistory),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('all', 'All', Icons.list_alt, scheme),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                            'video', 'Video', Icons.videocam, scheme),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                            'audio', 'Audio', Icons.audiotrack, scheme),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                            'fusion', 'Fusion', Icons.merge_type, scheme),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (isLoading)
                  Expanded(
                    child: Center(
                      child: CircularProgressIndicator(
                        color: scheme.primary,
                      ),
                    ),
                  )
                else if (filteredUploads.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _selectedFilter == 'all'
                                ? Icons.analytics_outlined
                                : _getTypeIcon(_selectedFilter),
                            size: 80,
                            color: scheme.primary.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _selectedFilter == 'all'
                                ? 'No Prediction History'
                                : 'No ${_selectedFilter.toUpperCase()} Predictions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _selectedFilter == 'all'
                                ? 'Your analysis results will appear here'
                                : 'No ${_selectedFilter} analysis found',
                            style: TextStyle(
                              fontSize: 14,
                              color: scheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          if (_selectedFilter != 'all') ...[
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: () =>
                                  setState(() => _selectedFilter = 'all'),
                              icon: const Icon(Icons.list_alt),
                              label: const Text('Show All'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '${filteredUploads.length} ${_selectedFilter == 'all' ? 'results' : _selectedFilter + ' results'}',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: filteredUploads.length,
                            itemBuilder: (context, index) {
                              final upload = filteredUploads[index];
                              final id =
                                  upload['id']?.toString() ?? index.toString();
                              final type = upload['type'] ?? upload['fileType'];

                              final prediction = upload['prediction'] ??
                                  upload['predictedClass'];
                              Map<String, dynamic>? result =
                                  _safeCastMap(upload['result']);

                              if (result == null &&
                                  upload['predictedClass'] != null) {
                                result = {
                                  'predictedClass': upload['predictedClass'],
                                  'confidence': upload['confidence'],
                                  'topPredictions': upload['topPredictions'],
                                };
                              }

                              Map<String, dynamic>? probabilities =
                                  _safeCastMap(upload['probabilities']);
                              if (probabilities == null && result != null) {
                                probabilities =
                                    _extractProbabilitiesFromResult(result);
                              }

                              if (probabilities == null ||
                                  probabilities.isEmpty) {
                                final topPreds = upload['topPredictions'] ??
                                    result?['topPredictions'];
                                if (topPreds is List && topPreds.isNotEmpty) {
                                  probabilities = {};
                                  for (final p in topPreds) {
                                    if (p is Map) {
                                      final className = p['class'] ??
                                          p['className'] ??
                                          p['label'] ??
                                          'unknown';
                                      final conf = p['confidence'] ??
                                          p['probability'] ??
                                          0;
                                      probabilities[className.toString()] =
                                          conf is num ? conf.toDouble() : 0.0;
                                    }
                                  }
                                }
                              }

                              if ((probabilities == null ||
                                      probabilities.length <= 1) &&
                                  result != null) {
                                final allProbs = result['allProbabilities'];
                                if (allProbs is Map) {
                                  final fused = allProbs['fused'] ??
                                      allProbs['video'] ??
                                      allProbs['audio'];
                                  if (fused is Map && fused.length > 1) {
                                    final sorted = fused.entries.toList()
                                      ..sort((a, b) => (b.value as num)
                                          .compareTo(a.value as num));
                                    probabilities = {};
                                    for (final e in sorted.take(5)) {
                                      probabilities![e.key.toString()] =
                                          (e.value as num).toDouble();
                                    }
                                  }
                                }
                              }

                              if ((probabilities == null ||
                                      probabilities.isEmpty) &&
                                  prediction != null) {
                                final conf = upload['confidence'];
                                probabilities = {
                                  prediction.toString():
                                      conf is num ? conf.toDouble() : 0.0
                                };
                              }

                              int tagsCount = probabilities?.length ?? 1;

                              final isExpanded = expandedItems.contains(id);

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: GlassContainer(
                                  opacity: 0.1,
                                  padding: const EdgeInsets.all(16),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            if (isExpanded) {
                                              expandedItems.remove(id);
                                            } else {
                                              expandedItems.add(id);
                                            }
                                          });
                                        },
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: _getTypeColor(type)
                                                    .withValues(alpha: 0.2),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                _getTypeIcon(type),
                                                color: _getTypeColor(type),
                                                size: 24,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    upload['fileName'] ??
                                                        'Unknown',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: scheme.onSurface,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    _formatDateTime(upload[
                                                            'timestamp'] ??
                                                        upload['uploadTime']),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: scheme.onSurface
                                                          .withValues(
                                                              alpha: 0.6),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF7C4DFF)
                                                    .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: const Color(0xFF7C4DFF)
                                                      .withValues(alpha: 0.3),
                                                ),
                                              ),
                                              child: const Text(
                                                'COMPLETED',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF7C4DFF),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (prediction != null)
                                              Builder(builder: (context) {
                                                final isMultiScene = upload[
                                                            'multiScene'] ==
                                                        true ||
                                                    upload['isMultilabel'] ==
                                                        true;
                                                final detectedClasses =
                                                    upload['detectedClasses'];
                                                final classCount =
                                                    detectedClasses is List
                                                        ? detectedClasses.length
                                                        : (probabilities
                                                                ?.length ??
                                                            1);
                                                final showClassCount =
                                                    isMultiScene &&
                                                        classCount > 1;

                                                return Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 10,
                                                    vertical: 5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: scheme.primary
                                                        .withValues(alpha: 0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                  child: Text(
                                                    showClassCount
                                                        ? '$classCount CLASSES'
                                                        : prediction
                                                            .toString()
                                                            .toUpperCase(),
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: scheme.primary,
                                                    ),
                                                  ),
                                                );
                                              }),
                                            const SizedBox(width: 4),
                                            Icon(
                                              isExpanded
                                                  ? Icons.keyboard_arrow_up
                                                  : Icons.keyboard_arrow_down,
                                              color: scheme.onSurface
                                                  .withValues(alpha: 0.5),
                                              size: 24,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isExpanded) ...[
                                        const SizedBox(height: 16),
                                        Divider(
                                          color: scheme.onSurface
                                              .withValues(alpha: 0.1),
                                          height: 1,
                                        ),
                                        const SizedBox(height: 16),
                                        Builder(
                                          builder: (context) {
                                            final isEventDetectionOn = upload[
                                                    'eventDetectionEnabled'] ==
                                                true;
                                            final primaryEvent =
                                                isEventDetectionOn
                                                    ? _extractPrimaryEvent(
                                                        upload,
                                                        prediction?.toString(),
                                                        probabilities)
                                                    : null;
                                            final sceneProbabilities =
                                                probabilities
                                                        is Map<String, dynamic>
                                                    ? probabilities
                                                    : <String, dynamic>{};

                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [ 
                                                    if (type != null)
                                                    _buildInfoBadge(
                                                      type.toString().toUpperCase(),
                                                      _getTypeIcon(type),
                                                      _getTypeColor(type),
                                                    ),
                                                  if (upload['source'] == 'edge_device')
                                                    _buildInfoBadge(
                                                      'PI5 EDGE',
                                                      Icons.developer_board_rounded,
                                                      const Color(0xFF00BCD4),
                                                    ),
                                                  if (upload['sourceType'] == 'video_stream' &&
                                                      upload['source'] != 'edge_device')
                                                    _buildInfoBadge(
                                                      'IP CAMERA',
                                                      Icons.videocam_rounded,
                                                      const Color(0xFF0097A7),
                                                    ),
                                                  if (upload['source'] != 'edge_device' &&
                                                      upload['sourceType'] != 'video_stream')
                                                    _buildInfoBadge(
                                                      'FILE UPLOAD',
                                                      Icons.upload_file_rounded,
                                                      const Color(0xFF546E7A),
                                                    ),
                                                  if (_showFullDetails && primaryEvent != null)
                                              
                                            
                                          
                                          
                                                      _buildInfoBadge(
                                                        primaryEvent
                                                            .replaceAll(
                                                                '_', ' ')
                                                            .toUpperCase(),
                                                        Icons
                                                            .local_fire_department_rounded,
                                                        const Color(0xFFE53935),
                                                      ),
                                                    if (_showFullDetails &&
                                                        primaryEvent != null)
                                                      _buildSeverityBadge(
                                                          primaryEvent, scheme),
                                                    if (_showFullDetails &&
                                                        upload['multiScene'] ==
                                                            true)
                                                      _buildInfoBadge(
                                                        'MULTI-SCENE',
                                                        Icons.layers_rounded,
                                                        const Color(0xFF9C27B0),
                                                      ),
                                                    if (_showFullDetails &&
                                                        upload['fusionMethod'] !=
                                                            null)
                                                      _buildInfoBadge(
                                                        upload['fusionMethod']
                                                            .toString()
                                                            .toUpperCase(),
                                                        Icons
                                                            .merge_type_rounded,
                                                        const Color(0xFF7C4DFF),
                                                      ),
                                                    if (_showFullDetails &&
                                                        upload['source'] !=
                                                            null)
                                                      _buildInfoBadge(
                                                        upload['source']
                                                            .toString()
                                                            .toUpperCase(),
                                                        Icons.input_rounded,
                                                        const Color(0xFFAB47BC),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                        if (probabilities != null &&
                                            probabilities.isNotEmpty) ...[
                                          Builder(builder: (context) {
                                            final isMultiScene =
                                                upload['multiScene'] == true ||
                                                    upload['isMultilabel'] ==
                                                        true;
                                            final detectedClasses =
                                                upload['detectedClasses'];
                                            final hasMultiSceneData =
                                                isMultiScene &&
                                                    detectedClasses is List &&
                                                    detectedClasses.length > 1;

                                            if (hasMultiSceneData) {
                                              return _buildMultiSceneHistoryLayout(
                                                scheme,
                                                upload,
                                                result,
                                                detectedClasses,
                                                probabilities!,
                                              );
                                            }

                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Predicted Class',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: scheme.onSurface,
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                _buildTopPrediction(
                                                    probabilities!, scheme),
                                                const SizedBox(height: 16),
                                                if (_showFullDetails &&
                                                    probabilities!.length >
                                                        1) ...[
                                                  Text(
                                                    'Top Class Distribution',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: scheme.onSurface,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  ..._buildRemainingTagsList(
                                                      probabilities!, scheme),
                                                  const SizedBox(height: 16),
                                                ],
                                              ],
                                            );
                                          }),
                                          if (_showFullDetails)
                                            ..._buildEventTags(
                                              _extractPrimaryEvent(
                                                upload,
                                                prediction?.toString(),
                                                probabilities,
                                              ),
                                              scheme,
                                              upload,
                                              probabilities
                                                      is Map<String, dynamic>
                                                  ? probabilities
                                                  : <String, dynamic>{},
                                            ),
                                        ],
                                        if (result != null &&
                                            (probabilities == null ||
                                                probabilities.isEmpty)) ...[
                                          Text(
                                            'Detection Result',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: scheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          ..._buildResultDetails(
                                              result, scheme),
                                        ],
                                        if (prediction != null &&
                                            result == null &&
                                            (probabilities == null ||
                                                probabilities.isEmpty)) ...[
                                          Text(
                                            'Detection Result',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: scheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          _buildSinglePrediction(
                                            prediction.toString(),
                                            upload['confidence'],
                                            scheme,
                                          ),
                                        ],
                                        if (prediction == null &&
                                            result == null &&
                                            (probabilities == null ||
                                                probabilities.isEmpty)) ...[
                                          Text(
                                            'No detailed results available',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: scheme.onSurface
                                                  .withValues(alpha: 0.6),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          )
        ],
      ),
    );
  }

  // build ui section
  Widget _buildFilterChip(
      String filter, String label, IconData icon, ColorScheme scheme) {
    final isSelected = _selectedFilter == filter;
    final count = filter == 'all'
        ? uploads.length
        : uploads
            .where((u) =>
                (u['type'] ?? u['fileType'] ?? '').toString().toLowerCase() ==
                filter)
            .length;

    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.2)
              : scheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? scheme.primary.withValues(alpha: 0.3)
                      : scheme.onSurface.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static const Map<String, int> _eventSeverity = {
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

  static const Map<String, List<String>> _sceneEventMap = {
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

  String _severityLabel(String? predictedClass) {
    if (predictedClass == null) return 'N/A';
    final key = predictedClass.toLowerCase().replaceAll(' ', '_');

    if (_eventSeverity.containsKey(key)) {
      final s = _eventSeverity[key]!;
      if (s >= 5) return 'CRITICAL';
      if (s >= 4) return 'HIGH';
      if (s >= 3) return 'MEDIUM';
      return 'LOW';
    }

    if (_sceneEventMap.containsKey(key)) {
      final events = _sceneEventMap[key]!;
      int maxSev = 0;
      for (final e in events) {
        maxSev = maxSev > (_eventSeverity[e] ?? 0)
            ? maxSev
            : (_eventSeverity[e] ?? 0);
      }
      if (maxSev >= 5) return 'CRITICAL';
      if (maxSev >= 4) return 'HIGH';
      if (maxSev >= 3) return 'MEDIUM';
      if (maxSev >= 2) return 'LOW';
    }
    return 'N/A';
  }

  Color _severityColor(String label) {
    switch (label) {
      case 'CRITICAL':
        return const Color(0xFFFF1744);
      case 'HIGH':
        return const Color(0xFFFF9100);
      case 'MEDIUM':
        return const Color(0xFFFFB300);
      case 'LOW':
        return const Color(0xFF00E676);
      default:
        return Colors.grey;
    }
  }

  // build ui section
  Widget _buildInfoBadge(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // build ui section
  Widget _buildSeverityBadge(String? eventType, ColorScheme scheme) {
    final label = _severityLabel(eventType);
    final color = _severityColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield_rounded, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // build widget list
  List<Widget> _buildEventTags(String? primaryEvent, ColorScheme scheme,
      Map<String, dynamic> upload, Map<String, dynamic>? sceneProbabilities) {
    final eventDetectionEnabled = upload['eventDetectionEnabled'] == true;
    if (!eventDetectionEnabled) {
      return [];
    }

    List<String> detectedEvents = [];
    Map<String, double>? eventProbabilities;

    final result = upload['result'];
    if (result is Map) {
      final eventDet = result['eventDetection'];
      if (eventDet is Map) {
        final probs =
            eventDet['probabilities'] ?? eventDet['eventProbabilities'];
        if (probs is Map) {
          eventProbabilities = <String, double>{};
          for (final entry in probs.entries) {
            final val = entry.value;
            if (val is num) {
              eventProbabilities[entry.key.toString()] = val.toDouble();
            }
          }
        }

        final eventConfs = eventDet['eventConfidences'];
        if (eventConfs is Map && eventConfs.isNotEmpty) {
          final ranked = <MapEntry<String, double>>[];
          for (final entry in eventConfs.entries) {
            final val = entry.value;
            if (val is num) {
              ranked.add(MapEntry(entry.key.toString(), val.toDouble()));
            }
          }
          ranked.sort((a, b) => b.value.compareTo(a.value));
          if (ranked.isNotEmpty) {
            detectedEvents = [ranked.first.key];
          }
        }

        if (detectedEvents.isEmpty) {
          final events = eventDet['events'];
          if (events is List && events.isNotEmpty) {
            detectedEvents = [events.first.toString()];
          }

          if (detectedEvents.isEmpty) {
            final highest = eventDet['highestSeverityEvent'];
            if (highest is Map && highest['type'] != null) {
              detectedEvents = [highest['type'].toString()];
            } else if (highest != null &&
                highest.toString().isNotEmpty &&
                highest is! Map) {
              detectedEvents = [highest.toString()];
            }
          }
        }
      }
    }

    if (detectedEvents.isEmpty) {
      final eventType = upload['eventType'] ?? upload['detectedEventType'];
      if (eventType != null && eventType.toString().isNotEmpty) {
        detectedEvents = [eventType.toString()];
      }
    }

    if (detectedEvents.isEmpty && primaryEvent != null) {
      detectedEvents = [primaryEvent];
    }

    if (detectedEvents.isEmpty) {
      final result = upload['result'];
      final hasEventDetectionData =
          result is Map && result['eventDetection'] is Map;

      if (hasEventDetectionData) {
        final eventDet = result['eventDetection'] as Map;
        final confs = eventDet['eventConfidences'];
        if (confs is Map && confs.isNotEmpty) {
          eventProbabilities = <String, double>{};
          for (final entry in confs.entries) {
            final val = entry.value;
            if (val is num) {
              eventProbabilities![entry.key.toString()] = val.toDouble();
            }
          }
          final ranked = eventProbabilities!.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          if (ranked.isNotEmpty) {
            detectedEvents = [ranked.first.key];
          }
        }
      }

      if (detectedEvents.isEmpty) {
        return [
          Row(
            children: [
              Icon(Icons.verified_rounded,
                  size: 16, color: Colors.green.shade400),
              const SizedBox(width: 6),
              Text(
                'Event detection complete \u2014 no threats detected',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ];
      }
    }

    final widgets = <Widget>[
      Text(
        'Detected Events',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: detectedEvents.map((e) {
          final sev = _eventSeverity[e.toLowerCase().replaceAll(' ', '_')] ?? 3;
          final sevLabel = sev >= 5
              ? 'CRITICAL'
              : sev >= 4
                  ? 'HIGH'
                  : sev >= 3
                      ? 'MEDIUM'
                      : 'LOW';
          final color = _severityColor(sevLabel);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              e.replaceAll('_', ' ').toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 16),
    ];

    Map<String, double>? displayProbabilities = eventProbabilities;

    if ((displayProbabilities == null || displayProbabilities.isEmpty) &&
        sceneProbabilities != null &&
        sceneProbabilities.isNotEmpty) {
      displayProbabilities =
          _inferEventProbabilitiesFromScenes(sceneProbabilities);
    }

    if (displayProbabilities != null && displayProbabilities.isNotEmpty) {
      final sceneClass =
          (result is Map ? result['predictedClass'] : null)?.toString();
      displayProbabilities = _applyMotionPatternWeighting(
        displayProbabilities,
        result is Map ? result['eventDetection'] : null,
        sceneClass,
      );

      final total = displayProbabilities.values.fold(0.0, (a, b) => a + b);
      if (total > 0) {
        displayProbabilities =
            displayProbabilities.map((k, v) => MapEntry(k, v / total));
      }

      final sorted = displayProbabilities.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top3 = sorted.take(3).toList();

      widgets.addAll([
        Text(
          'Event Prediction Distribution',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        ...top3.map((entry) {
          final eventName = entry.key;
          final prob = entry.value;
          final percentage = (prob * 100);
          final sev =
              _eventSeverity[eventName.toLowerCase().replaceAll(' ', '_')] ?? 3;
          final color = sev >= 5
              ? const Color(0xFFFF1744)
              : sev >= 4
                  ? const Color(0xFFFF9100)
                  : sev >= 3
                      ? const Color(0xFFFFB300)
                      : const Color(0xFF00E676);

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 140,
                  child: Text(
                    eventName.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: scheme.onSurface.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: prob.clamp(0.0, 1.0),
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 50,
                  child: Text(
                    '${percentage.toStringAsFixed(1)}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        const SizedBox(height: 16),
      ]);
    }

    return widgets;
  }

  String? _bestEventFromConfidenceMap(Map? confs) {
    if (confs == null || confs.isEmpty) return null;
    String? best;
    double bestConf = -1;
    for (final entry in confs.entries) {
      final double val =
          entry.value is num ? (entry.value as num).toDouble() : -1.0;
      if (val > bestConf) {
        best = entry.key.toString();
        bestConf = val;
      }
    }
    return best;
  }

  String? _extractPrimaryEvent(Map<String, dynamic> upload, String? prediction,
      Map<String, dynamic>? sceneProbabilities) {
    final result = upload['result'];
    if (result is Map) {
      final eventDet = result['eventDetection'];
      if (eventDet is Map) {
        final bestFromConfs =
            _bestEventFromConfidenceMap(eventDet['eventConfidences'] as Map?);
        if (bestFromConfs != null) return bestFromConfs;

        final probs =
            eventDet['probabilities'] ?? eventDet['eventProbabilities'];
        if (probs is Map && probs.isNotEmpty) {
          final bestFromProbs = _bestEventFromConfidenceMap(probs);
          if (bestFromProbs != null) return bestFromProbs;
        }

        final highest = eventDet['highestSeverityEvent'];
        if (highest is Map && highest['type'] != null) {
          return highest['type'].toString();
        } else if (highest != null &&
            highest.toString().isNotEmpty &&
            highest is! Map) {
          return highest.toString();
        }
        final events = eventDet['events'];
        if (events is List && events.isNotEmpty) {
          return events.first.toString();
        }
      }
    }

    final eventType = upload['eventType'] ?? upload['detectedEventType'];
    if (eventType != null && eventType.toString().isNotEmpty) {
      return eventType.toString();
    }

    return null;
  }

  String _normalizeSceneClassKey(String value) {
    final base = value
        .toLowerCase()
        .replaceAll('(', '_')
        .replaceAll(')', '')
        .replaceAll('-', '_')
        .replaceAll('/', '_')
        .replaceAll(' ', '_')
        .replaceAll('__', '_');

    if (base == 'metro_underground' || base == 'metro__underground') {
      return 'metro';
    }
    if (base == 'street__traffic') return 'street_traffic';
    if (base == 'street__pedestrian') return 'street_pedestrian';
    return base;
  }

  Map<String, double> _inferEventProbabilitiesFromScenes(
      Map<String, dynamic>? sceneProbabilities) {
    if (sceneProbabilities == null || sceneProbabilities.isEmpty) {
      return {};
    }

    final eventScores = <String, double>{};
    sceneProbabilities.forEach((scene, probValue) {
      final parsed = probValue is num
          ? probValue.toDouble()
          : double.tryParse(probValue.toString());
      if (parsed == null) return;

      final sceneKey = _normalizeSceneClassKey(scene);
      final mappedEvents = _sceneEventMap[sceneKey];
      if (mappedEvents == null || mappedEvents.isEmpty) return;

      final sceneProbability = parsed;

      double totalSeverity = 0;
      for (final event in mappedEvents) {
        totalSeverity += (_eventSeverity[event] ?? 1).toDouble();
      }

      for (int idx = 0; idx < mappedEvents.length; idx++) {
        final event = mappedEvents[idx];
        final severityWeight =
            (_eventSeverity[event] ?? 1).toDouble() / totalSeverity;

        final positionBoost = 1.0 + (idx * 0.05);
        final contribution = sceneProbability * severityWeight * positionBoost;
        eventScores[event] = (eventScores[event] ?? 0.0) + contribution;
      }
    });

    return eventScores;
  }

  Map<String, double> _applyMotionPatternWeighting(
      Map<String, double> eventProbabilities,
      Map<String, dynamic>? avslowfastResult,
      String? sceneClass) {
    if (avslowfastResult == null || eventProbabilities.isEmpty) {
      return eventProbabilities;
    }

    final eventConfidences = avslowfastResult['event_confidences'] as Map?;
    if (eventConfidences == null || eventConfidences.isEmpty) {
      return eventProbabilities;
    }

    final Map<String, Map<String, double>> motionEventBoosts = {
      'street_traffic': {
        'accident': 1.8,
        'vehicle_crash': 1.9,
        'fire': 1.1,
        'explosion': 1.2,
      },
      'bus': {
        'accident': 1.7,
        'fire': 1.3,
        'explosion': 1.4,
        'riot': 1.1,
      },
      'metro': {
        'explosion': 1.9,
        'fire_alarm': 1.6,
        'evacuation': 1.5,
        'riot': 1.2,
      },
      'street_pedestrian': {
        'fight': 1.8,
        'accident': 1.5,
        'riot': 1.6,
        'explosion': 1.3,
      },
      'park': {
        'riot': 1.7,
        'fight': 1.8,
        'fire': 1.2,
      },
      'airport': {
        'evacuation': 1.7,
        'explosion': 1.9,
        'fire_alarm': 1.5,
        'riot': 1.1,
      },
    };

    final sceneKey =
        sceneClass != null ? _normalizeSceneClassKey(sceneClass) : null;
    final boosts = sceneKey != null ? motionEventBoosts[sceneKey] : null;

    if (boosts == null) {
      return eventProbabilities;
    }

    final result = <String, double>{};
    eventProbabilities.forEach((event, prob) {
      final motionBoost = boosts[event] ?? 1.0;

      final avConfidence = eventConfidences[event] != null
          ? (eventConfidences[event] as num).toDouble()
          : 0.5;

      final weightedProb = prob * motionBoost * (0.7 + avConfidence * 0.3);
      result[event] = weightedProb;
    });

    return result;
  }

  // build widget list
  List<Widget> _buildTagsList(
      Map<String, dynamic> probabilities, ColorScheme scheme) {
    final sortedEntries = probabilities.entries.toList()
      ..sort((a, b) {
        final aVal = a.value is num ? (a.value as num).toDouble() : 0.0;
        final bVal = b.value is num ? (b.value as num).toDouble() : 0.0;
        return bVal.compareTo(aVal);
      });

    return sortedEntries.map((entry) {
      final label = entry.key.toString().toUpperCase();
      final probability =
          entry.value is num ? (entry.value as num).toDouble() : 0.0;
      final percentage = (probability * 100);

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 180,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: probability.clamp(0.0, 1.0),
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: _getBarColor(probability),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 50,
              child: Text(
                '${percentage.toStringAsFixed(1)}%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // build ui section
  Widget _buildMultiSceneHistoryLayout(
    ColorScheme scheme,
    Map<String, dynamic> upload,
    Map<String, dynamic>? result,
    List detectedClasses,
    Map<String, dynamic> probabilities,
  ) {
    final sceneColors = [
      scheme.primary,
      const Color(0xFFE65100),
      const Color(0xFF00796B),
      const Color(0xFFC2185B),
      const Color(0xFF283593),
      const Color(0xFFFF8F00),
    ];

    String formatTimestamp(double seconds) {
      final rounded = (seconds * 10).round() / 10;
      if (rounded < 0.1) return '0s';
      final mins = (rounded / 60).floor();
      final secs = (rounded % 60);
      if (mins > 0) {
        return '${mins}m ${secs.toStringAsFixed(0)}s';
      }

      return secs >= 1
          ? '${secs.toStringAsFixed(0)}s'
          : '${secs.toStringAsFixed(1)}s';
    }

    final segmentPredictions = result?['segmentPredictions'] as List? ?? [];
    final durationSeconds = (result?['durationSeconds'] ?? 0).toDouble();
    final totalSegments = result?['totalSegments'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.layers_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              'Multi-Scene Detection',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${detectedClasses.length} scenes',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ),
            if (durationSeconds > 0) ...[
              const Spacer(),
              Text(
                '${durationSeconds.toStringAsFixed(2)}s · $totalSegments segs',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Builder(builder: (context) {
          final sortedByTime = List<Map<String, dynamic>>.from(
            detectedClasses.map(
                (c) => c is Map<String, dynamic> ? c : <String, dynamic>{}),
          )..sort((a, b) {
              final aT = ((a['firstDetectedAt'] ?? 0) as num).toDouble();
              final bT = ((b['firstDetectedAt'] ?? 0) as num).toDouble();
              return aT.compareTo(bT);
            });
          final sceneDurations = <String, double>{};
          for (int i = 0; i < sortedByTime.length; i++) {
            final cls = (sortedByTime[i]['class'] ?? '').toString();
            final start =
                ((sortedByTime[i]['firstDetectedAt'] ?? 0) as num).toDouble();
            final nextStart = (i + 1 < sortedByTime.length)
                ? ((sortedByTime[i + 1]['firstDetectedAt'] ?? 0) as num)
                    .toDouble()
                : durationSeconds;
            sceneDurations[cls] = (nextStart - start).clamp(0, durationSeconds);
          }

          return Column(
            children: detectedClasses.asMap().entries.map((entry) {
              final idx = entry.key;
              final cls = entry.value as Map<String, dynamic>? ?? {};
              final color = sceneColors[idx % sceneColors.length];
              final className = (cls['class'] ?? 'Unknown').toString();
              final confidence =
                  ((cls['maxConfidence'] ?? 0) as num).toDouble() * 100;
              final percentage =
                  ((cls['percentageOfVideo'] ?? 0) as num).toDouble();
              final occurrences = cls['occurrences'] ?? 0;
              final firstAt = ((cls['firstDetectedAt'] ?? 0) as num).toDouble();
              final sceneDuration = sceneDurations[className] ?? 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: color.withOpacity(0.25), width: 1),
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
                              className.toUpperCase(),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${confidence.toStringAsFixed(1)}%',
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (confidence / 100).clamp(0.0, 1.0),
                          backgroundColor: scheme.onSurface.withOpacity(0.1),
                          color: color,
                          minHeight: 5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.schedule,
                              size: 11,
                              color: scheme.onSurface.withOpacity(0.5)),
                          const SizedBox(width: 4),
                          Text(
                            'First at ${formatTimestamp(firstAt)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurface.withOpacity(0.7),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (sceneDuration > 0) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.timelapse,
                                size: 11,
                                color: scheme.onSurface.withOpacity(0.5)),
                            const SizedBox(width: 4),
                            Text(
                              '${formatTimestamp(sceneDuration)} dur',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurface.withOpacity(0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(width: 12),
                          Icon(Icons.repeat,
                              size: 11,
                              color: scheme.onSurface.withOpacity(0.5)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '$occurrences segs · ${percentage.toStringAsFixed(0)}% of video',
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
                ),
              );
            }).toList(),
          );
        }),
        if (segmentPredictions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Segment Timeline',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 6),
          _buildHistoryTimeline(scheme, segmentPredictions, sceneColors),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  // build ui section
  Widget _buildHistoryTimeline(
    ColorScheme scheme,
    List segmentPredictions,
    List<Color> sceneColors,
  ) {
    final uniqueClasses = segmentPredictions
        .map((s) => (s['predictedClass'] ?? s['fusedClass'] ?? '').toString())
        .toSet()
        .toList();

    return Column(
      children: [
        SizedBox(
          height: 20,
          child: Row(
            children: segmentPredictions.map((segment) {
              final cls =
                  (segment['predictedClass'] ?? segment['fusedClass'] ?? '')
                      .toString();
              final classIndex = uniqueClasses.indexOf(cls);
              final color = sceneColors[classIndex % sceneColors.length];
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 0.5),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: uniqueClasses.asMap().entries.map((e) {
            final color = sceneColors[e.key % sceneColors.length];
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  e.value.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface.withOpacity(0.6),
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
  Widget _buildTopPrediction(
      Map<String, dynamic> probabilities, ColorScheme scheme) {
    final sortedEntries = probabilities.entries.toList()
      ..sort((a, b) {
        final aVal = a.value is num ? (a.value as num).toDouble() : 0.0;
        final bVal = b.value is num ? (b.value as num).toDouble() : 0.0;
        return bVal.compareTo(aVal);
      });

    if (sortedEntries.isEmpty) return const SizedBox.shrink();

    final topEntry = sortedEntries.first;
    final label = topEntry.key.toString().toUpperCase();
    final probability =
        topEntry.value is num ? (topEntry.value as num).toDouble() : 0.0;
    final percentage = (probability * 100);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.label_rounded, size: 14, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: probability.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: scheme.onSurface.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation(_getBarColor(probability)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${percentage.toStringAsFixed(1)}%',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // build widget list
  List<Widget> _buildRemainingTagsList(
      Map<String, dynamic> probabilities, ColorScheme scheme) {
    final sortedEntries = probabilities.entries.toList()
      ..sort((a, b) {
        final aVal = a.value is num ? (a.value as num).toDouble() : 0.0;
        final bVal = b.value is num ? (b.value as num).toDouble() : 0.0;
        return bVal.compareTo(aVal);
      });

    final remainingEntries = sortedEntries.skip(1).take(4).toList();

    return remainingEntries.map((entry) {
      final label = entry.key.toString().toUpperCase();
      final probability =
          entry.value is num ? (entry.value as num).toDouble() : 0.0;
      final percentage = (probability * 100);

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _getBarColor(probability),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 180,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: probability.clamp(0.0, 1.0),
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: _getBarColor(probability),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 50,
              child: Text(
                '${percentage.toStringAsFixed(1)}%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // build ui section
  Widget _buildSinglePrediction(
      String prediction, dynamic confidence, ColorScheme scheme) {
    final conf = confidence is num ? confidence.toDouble() : 0.0;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          prediction.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: scheme.primary,
          ),
        ),
        const Spacer(),
        if (conf > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C4DFF).withValues(alpha: 0.4),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              '${(conf * 100).toStringAsFixed(1)}%',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  Map<String, dynamic>? _safeCastMap(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return Map<String, dynamic>.from(
        value.map((key, val) => MapEntry(key.toString(), val)),
      );
    }
    return null;
  }

  Map<String, dynamic>? _extractProbabilitiesFromResult(
      Map<String, dynamic> result) {
    if (result.containsKey('probabilities') && result['probabilities'] is Map) {
      return Map<String, dynamic>.from(result['probabilities'] as Map);
    }

    if (result.containsKey('class_probabilities') &&
        result['class_probabilities'] is Map) {
      return Map<String, dynamic>.from(result['class_probabilities'] as Map);
    }

    if (result.containsKey('top_predictions') &&
        result['top_predictions'] is List) {
      final preds = result['top_predictions'] as List;
      final Map<String, dynamic> probMap = {};
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

    if (result.containsKey('topPredictions') &&
        result['topPredictions'] is List) {
      final preds = result['topPredictions'] as List;
      final Map<String, dynamic> probMap = {};
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

  // build widget list
  List<Widget> _buildResultDetails(
      Map<String, dynamic> result, ColorScheme scheme) {
    final widgets = <Widget>[];

    final prediction = result['prediction'] ??
        result['predictedClass'] ??
        result['predicted_class'] ??
        result['class'];
    if (prediction != null) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Prediction: ',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              Text(
                prediction.toString().toUpperCase(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final confidence = result['confidence'] ?? result['probability'];
    if (confidence != null && confidence is num) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF7C4DFF),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Confidence: ',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '${(confidence.toDouble() * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7C4DFF),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (result.containsKey('labels') && result['labels'] is List) {
      final labels = result['labels'] as List;
      for (final label in labels) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  label.toString().toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    if (result.containsKey('topPredictions') &&
        result['topPredictions'] is List) {
      final preds = result['topPredictions'] as List;
      if (preds.isNotEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              'Generated Tags',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
        );
        for (final pred in preds) {
          if (pred is Map) {
            final label = pred['class'] ?? pred['label'] ?? pred['name'];
            final prob =
                pred['probability'] ?? pred['confidence'] ?? pred['score'];
            if (label != null && prob is num) {
              final percentage = prob.toDouble();
              widgets.add(
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _getBarColor(percentage),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 160,
                        child: Text(
                          label.toString().toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: scheme.onSurface.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: percentage.clamp(0.0, 1.0),
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _getBarColor(percentage),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 50,
                        child: Text(
                          '${(percentage * 100).toStringAsFixed(1)}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          }
        }
      }
    }

    if (result.containsKey('top_predictions') &&
        result['top_predictions'] is List) {
      final preds = result['top_predictions'] as List;
      if (preds.isNotEmpty && !result.containsKey('topPredictions')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              'Generated Tags',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
        );
        for (final pred in preds) {
          if (pred is Map) {
            final label = pred['class'] ?? pred['label'] ?? pred['name'];
            final prob =
                pred['probability'] ?? pred['confidence'] ?? pred['score'];
            if (label != null && prob is num) {
              final percentage = prob.toDouble();
              widgets.add(
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _getBarColor(percentage),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 160,
                        child: Text(
                          label.toString().toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: scheme.onSurface.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: percentage.clamp(0.0, 1.0),
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _getBarColor(percentage),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 50,
                        child: Text(
                          '${(percentage * 100).toStringAsFixed(1)}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          }
        }
      }
    }

    if (widgets.isEmpty) {
      result.forEach((key, value) {
        if (value != null && key != 'error') {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$key: ',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      });
    }

    return widgets;
  }

  Color _getBarColor(double probability) {
    if (probability >= 0.7) return const Color(0xFF7C4DFF);
    if (probability >= 0.3) return const Color(0xFF9C27B0);
    if (probability >= 0.1) return const Color(0xFFAB47BC);
    return const Color(0xFF7E57C2);
  }

  String _formatDateTime(String? timestamp) {
    if (timestamp == null) return 'Just now';
    try {
      final date = DateTime.parse(timestamp).toLocal();
      final month = date.month;
      final day = date.day;
      final year = date.year;
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$month/$day/$year $hour:$minute';
    } catch (e) {
      return timestamp;
    }
  }


 Color _getTypeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'audio':        return const Color(0xFF9C27B0);
      case 'video':        return const Color(0xFF7C4DFF);
      case 'video_stream': return const Color(0xFF00BCD4);
      case 'fusion':       return const Color(0xFFAB47BC);
      default:             return Colors.grey;
    }
  }

  IconData _getTypeIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'audio':        return Icons.graphic_eq_rounded;
      case 'video':        return Icons.movie_rounded;
      case 'video_stream': return Icons.developer_board_rounded;
      case 'fusion':       return Icons.layers_rounded;
      default:             return Icons.insert_drive_file_rounded;
    }
  }
}

 
class _GlassNavbar extends StatelessWidget {
  final VoidCallback? onClear;
  final VoidCallback? onRefresh;

  const _GlassNavbar({required this.onClear, this.onRefresh});

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
            'Tag History',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const Spacer(),
          if (onRefresh != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 22),
              color: scheme.onSurface,
              onPressed: onRefresh,
            ),
          if (onClear != null)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, size: 22),
              color: scheme.onSurface,
              onPressed: onClear,
            ),
          IconButton(
            icon: Icon(
              theme.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: theme.toggleTheme,
          ),
        ],
      ),
    );
  }
}
