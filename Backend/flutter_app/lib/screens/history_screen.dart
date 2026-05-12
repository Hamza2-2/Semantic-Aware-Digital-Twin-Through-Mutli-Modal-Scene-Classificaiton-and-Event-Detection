// file header note
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/theme_controller.dart';
import '../widgets/glass_container.dart';
import '../widgets/background_blobs.dart';
import '../services/prediction_history_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final PredictionHistoryService _historyService = PredictionHistoryService();
  List<Map<String, dynamic>> uploads = [];
  bool isLoading = false;
  Set<String> expandedItems = {};
  bool _hasMigrated = false;

  @override
  void initState() {
    super.initState();
    _loadUploadHistory();
  }

  Future<void> _loadUploadHistory() async {
    setState(() => isLoading = true);
    try {
      
      if (!_hasMigrated) {
        await _migrateOldHistory();
        _hasMigrated = true;
      }

      
      final history = await _historyService.getHistory();

      setState(() {
        uploads = history;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading history: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  
  Future<void> _migrateOldHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final oldUploadsList = prefs.getStringList('uploads') ?? [];

      if (oldUploadsList.isEmpty) return;

      print('Migrating ${oldUploadsList.length} old entries to MongoDB...');

      for (final uploadJson in oldUploadsList) {
        try {
          final upload = jsonDecode(uploadJson) as Map<String, dynamic>;

          
          await _historyService.saveToHistory(
            type: upload['type'] ?? upload['fileType'] ?? 'video',
            fileName: upload['fileName'] ?? 'Unknown',
            result: upload['result'] ?? upload,
            filePath: upload['filePath'],
          );
        } catch (e) {
          print('Error migrating entry: $e');
        }
      }

      
      await prefs.remove('uploads');
      print('Migration complete, old data cleared');
    } catch (e) {
      print('Migration error: $e');
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History'),
        content:
            const Text('Are you sure you want to clear all upload history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _historyService.clearHistory();
      setState(() => uploads.clear());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('History cleared'),
          backgroundColor: Colors.green,
        ),
      );
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
                      onClear: uploads.isEmpty ? null : _clearHistory,
                      onRefresh: _loadUploadHistory),
                ),
                const SizedBox(height: 20),
                if (isLoading)
                  Expanded(
                    child: Center(
                      child: CircularProgressIndicator(
                        color: scheme.primary,
                      ),
                    ),
                  )
                else if (uploads.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.analytics_outlined,
                            size: 80,
                            color: scheme.primary.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'No Prediction History',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your analysis results will appear here',
                            style: TextStyle(
                              fontSize: 14,
                              color: scheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: uploads.length,
                      itemBuilder: (context, index) {
                        final upload = uploads[index];
                        final id = upload['id']?.toString() ?? index.toString();
                        final type = upload['type'] ?? upload['fileType'];
                        final prediction = upload['prediction'];
                        final result = _safeCastMap(upload['result']);
                        final displayResult = result != null
                            ? {
                                ...result,
                                if (upload['eventType'] != null)
                                  'eventType': upload['eventType'],
                                if (upload['eventDetectionEnabled'] != null)
                                  'eventDetectionEnabled':
                                      upload['eventDetectionEnabled'],
                              }
                            : null;

                        
                        Map<String, dynamic>? probabilities =
                            _safeCastMap(upload['probabilities']);
                        if (probabilities == null && displayResult != null) {
                          probabilities =
                              _extractProbabilitiesFromResult(displayResult);
                        }

                        
                        int tagsCount =
                            upload['tags'] ?? probabilities?.length ?? 0;
                        if (tagsCount == 0 && displayResult != null) {
                          
                          final topPreds = displayResult['topPredictions'] ??
                              displayResult['top_predictions'];
                          if (topPreds is List) {
                            tagsCount = topPreds.length;
                          }
                        }

                        final isCompleted = true;
                        final isExpanded = expandedItems.contains(id);
                        final eventDetection = displayResult != null &&
                                displayResult['eventDetection'] is Map
                            ? displayResult['eventDetection'] as Map
                            : null;
                        final eventDetected = (upload['eventType'] != null &&
                                upload['eventType'].toString().isNotEmpty) ||
                            (eventDetection != null &&
                                eventDetection['eventsDetected'] == true);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassContainer(
                            opacity: 0.1,
                            padding: const EdgeInsets.all(16),
                            borderRadius: BorderRadius.circular(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                              upload['fileName'] ?? 'Unknown',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: scheme.onSurface,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _formatDateTime(
                                                  upload['timestamp'] ??
                                                      upload['uploadTime']),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: scheme.onSurface
                                                    .withValues(alpha: 0.6),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: eventDetected
                                              ? Colors.red
                                                  .withValues(alpha: 0.2)
                                              : Colors.green
                                                  .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          eventDetected ? 'ALERT' : 'COMPLETED',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: eventDetected
                                                ? Colors.red
                                                : Colors.green,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      
                                      if (tagsCount > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: scheme.primary
                                                .withValues(alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '$tagsCount tags',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: scheme.primary,
                                            ),
                                          ),
                                        ),
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
                                
                                if (isExpanded &&
                                    probabilities != null &&
                                    probabilities.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  Divider(
                                    color:
                                        scheme.onSurface.withValues(alpha: 0.1),
                                    height: 1,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Generated Tags',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ..._buildTagsList(probabilities, scheme),
                                ] else if (isExpanded &&
                                    displayResult != null) ...[
                                  const SizedBox(height: 16),
                                  Divider(
                                    color:
                                        scheme.onSurface.withValues(alpha: 0.1),
                                    height: 1,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Detection Result',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ..._buildResultDetails(displayResult, scheme),
                                ] else if (isExpanded &&
                                    prediction != null) ...[
                                  const SizedBox(height: 16),
                                  Divider(
                                    color:
                                        scheme.onSurface.withValues(alpha: 0.1),
                                    height: 1,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Detection Result',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _buildSinglePrediction(prediction.toString(),
                                      upload['confidence'], scheme),
                                ] else if (isExpanded) ...[
                                  const SizedBox(height: 16),
                                  Divider(
                                    color:
                                        scheme.onSurface.withValues(alpha: 0.1),
                                    height: 1,
                                  ),
                                  const SizedBox(height: 16),
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
                            ),
                          ),
                        );
                      },
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
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${(conf * 100).toStringAsFixed(1)}%',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.green,
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

  
  List<Widget> _buildResultDetails(
      Map<String, dynamic> result, ColorScheme scheme) {
    final widgets = <Widget>[];

    
    final prediction =
        result['prediction'] ?? result['predicted_class'] ?? result['class'];
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
                  color: Colors.green,
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
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${(confidence.toDouble() * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final eventDetection = result['eventDetection'] is Map
        ? result['eventDetection'] as Map
        : null;
    final highestSeverityEvent =
        eventDetection != null && eventDetection['highestSeverityEvent'] is Map
            ? eventDetection['highestSeverityEvent'] as Map
            : null;
    String? detectedEventType;
    num? detectedEventConfidence;
    final eventConfs = eventDetection?['eventConfidences'];
    if (eventConfs is Map && eventConfs.isNotEmpty) {
      String? bestType;
      double bestConf = -1;
      for (final entry in eventConfs.entries) {
        final double val =
            entry.value is num ? (entry.value as num).toDouble() : -1.0;
        if (val > bestConf) {
          bestType = entry.key.toString();
          bestConf = val;
        }
      }
      if (bestType != null) {
        detectedEventType = bestType;
        detectedEventConfidence = bestConf;
      }
    }
    detectedEventType ??= highestSeverityEvent?['type'] ??
        result['eventType'] ??
        result['event_type'];
    if (detectedEventType != null) {
      final eventConfidence =
          detectedEventConfidence ?? highestSeverityEvent?['confidence'];
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Detected Event: ',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              Text(
                detectedEventType.toString().replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.red,
                ),
              ),
              if (eventConfidence is num) ...[
                const SizedBox(width: 8),
                Text(
                  '(${(eventConfidence.toDouble() * 100).toStringAsFixed(1)}%)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ],
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
    if (probability >= 0.7) return Colors.green;
    if (probability >= 0.3) return Colors.purple;
    if (probability >= 0.1) return Colors.blue;
    return Colors.grey;
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
      case 'audio':
        return Colors.blue;
      case 'video':
      case 'video_stream':
        return Colors.purple;
      case 'multimodal':
      case 'fusion':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'audio':
        return Icons.graphic_eq_rounded;
      case 'video':
        return Icons.movie_rounded;
      case 'video_stream':
        return Icons.videocam_rounded;
      case 'multimodal':
      case 'fusion':
        return Icons.layers_rounded;
      default:
        return Icons.insert_drive_file_rounded;
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
