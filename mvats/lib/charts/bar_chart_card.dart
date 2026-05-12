// Bar chart widget for stats
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/prediction_history_service.dart';

class BarChartCard extends StatefulWidget {
  const BarChartCard({super.key});

  @override
  State<BarChartCard> createState() => BarChartCardState();
}

class BarChartCardState extends State<BarChartCard>
    with WidgetsBindingObserver {
  final PredictionHistoryService _historyService = PredictionHistoryService();
  Map<String, int> _classCounts = {};
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();

    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadData();
    }
  }

  void refresh() => _loadData();

  // load data
  Future<void> _loadData() async {
    try {
      final history = await _historyService.getHistory();
      final Map<String, int> counts = {};

      for (final entry in history) {
        final detectedClasses = entry['detectedClasses'];
        if (detectedClasses is List && detectedClasses.isNotEmpty) {
          for (final cls in detectedClasses) {
            final className = (cls is Map ? cls['class'] : cls)?.toString();
            if (className != null &&
                className.isNotEmpty &&
                className.toLowerCase() != 'unknown' &&
                className.toLowerCase() != 'null') {
              counts[className] = (counts[className] ?? 0) + 1;
            }
          }
          continue;
        }

        final prediction = entry['prediction']?.toString() ??
            entry['predictedClass']?.toString();

        if (prediction == null ||
            prediction.isEmpty ||
            prediction.toLowerCase() == 'unknown' ||
            prediction.toLowerCase() == 'null') {
          continue;
        }
        counts[prediction] = (counts[prediction] ?? 0) + 1;
      }

      final sortedEntries = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (mounted) {
        setState(() {
          _classCounts = Map.fromEntries(sortedEntries);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _shortenClassName(String name) {
    final Map<String, String> shortNames = {
      'Shopping Mall': 'Mall',
      'Metro Station': 'Metro St.',
      'Street Pedestrian': 'Street Ped.',
      'Public Square': 'Square',
      'Street Traffic': 'Traffic',
      'Metro (Underground)': 'Metro',
    };
    return shortNames[name] ??
        (name.length > 10 ? '${name.substring(0, 8)}.' : name);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: scheme.primary),
      );
    }

    if (_classCounts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart_outlined,
              size: 48,
              color: scheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'No prediction data yet',
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Run some predictions to see charts',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      );
    }

    final classNames = _classCounts.keys.toList();
    final occurrences = _classCounts.values.toList();
    final maxY = (occurrences.reduce((a, b) => a > b ? a : b) + 3).toDouble();

    final colors = [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.error,
      scheme.surfaceTint,
      scheme.inversePrimary,
      scheme.outline,
      scheme.secondary.withValues(alpha: 0.7),
      Colors.teal,
      Colors.amber,
      Colors.indigo,
      Colors.pink,
      Colors.cyan,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.maxWidth * 0.05;

        return BarChart(
          BarChartData(
            minY: 0,
            maxY: maxY,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) => FlLine(
                color: scheme.outline.withValues(alpha: 0.25),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  getTitlesWidget: (value, meta) {
                    if (value.toInt() < 0 ||
                        value.toInt() >= classNames.length) {
                      return const SizedBox.shrink();
                    }

                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      child: Text(
                        _shortenClassName(classNames[value.toInt()]),
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  interval: maxY > 10 ? 5 : 1,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                tooltipBgColor: scheme.surfaceContainerHighest,
                tooltipRoundedRadius: 8,
                tooltipPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  return BarTooltipItem(
                    '${classNames[group.x]}\n',
                    TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    children: [
                      TextSpan(
                        text: '${rod.toY.toInt()} occurrences',
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w400,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            barGroups: List.generate(classNames.length, (i) {
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: occurrences[i].toDouble(),
                    color: colors[i % colors.length],
                    width: barWidth,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              );
            }),
          ),
        );
      },
    );
  }
}
