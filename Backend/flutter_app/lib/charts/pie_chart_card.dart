// file header note
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/prediction_history_service.dart';

class PieChartCard extends StatefulWidget {
  const PieChartCard({super.key});

  @override
  State<PieChartCard> createState() => PieChartCardState();
}

class PieChartCardState extends State<PieChartCard>
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
    
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
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

  Future<void> _loadData() async {
    try {
      final history = await _historyService.getHistory();
      final Map<String, int> counts = {};

      for (final entry in history) {
        final prediction = entry['prediction']?.toString() ??
            entry['predictedClass']?.toString() ??
            'Unknown';
        counts[prediction] = (counts[prediction] ?? 0) + 1;
      }

      if (mounted) {
        setState(() {
          _classCounts = counts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
              Icons.pie_chart_outline,
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
    final dataValues = _classCounts.values.toList();
    final total = dataValues.reduce((a, b) => a + b);

    final colors = [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.error,
      scheme.secondaryContainer,
      scheme.primaryContainer,
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
        final size = constraints.biggest.shortestSide * 0.95;

        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: PieChart(
              PieChartData(
                centerSpaceRadius: size * 0.22,
                sectionsSpace: 3,
                sections: List.generate(classNames.length, (i) {
                  final percentage = (dataValues[i] / total) * 100;

                  final bgColor = colors[i % colors.length];
                  final luminance = bgColor.computeLuminance();
                  final textColor =
                      luminance > 0.5 ? Colors.black87 : Colors.white;

                  return PieChartSectionData(
                    value: dataValues[i].toDouble(),
                    title: "${percentage.toStringAsFixed(1)}%",
                    color: bgColor,
                    radius: size * 0.30,
                    titleStyle: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
  }
}
