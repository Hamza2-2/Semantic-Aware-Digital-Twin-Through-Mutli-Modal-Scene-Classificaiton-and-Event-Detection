// Admin dashboard landing page
import 'package:flutter/material.dart';
import '../charts/pie_chart_card.dart';
import '../charts/bar_chart_card.dart';
import '../theme/theme_controller.dart';
import '../widgets/glass_container.dart';
import 'input_format_selection.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'event_map_screen.dart';
import 'first_responder_home.dart';
import '../services/auth_service.dart';
import '../utils/glass_snackbar.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with SingleTickerProviderStateMixin {
  bool showCharts = true;

  late AnimationController _fadeCtrl;
  late Animation<double> fadeIn;
  late Animation<double> slideIn;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    fadeIn = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    slideIn = Tween<double>(begin: 18, end: 0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic),
    );

    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isLarge = width > 880;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          _BackgroundBlobs(isDark: isDark),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  const _GlassNavbar(),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      GlassContainer(
                        opacity: 0.16,
                        borderRadius: BorderRadius.circular(22),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 14),
                        child: Text(
                          showCharts
                              ? "Overview"
                              : "Model Metrics (F1, Accuracy, Precision, Recall)",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      const Spacer(),
                      GlassContainer(
                        opacity: 0.16,
                        borderRadius: BorderRadius.circular(22),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: () {
                            setState(() {
                              showCharts = !showCharts;
                              _fadeCtrl.forward(from: 0);
                            });
                          },
                          child: Row(
                            children: [
                              Icon(
                                showCharts
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                size: 20,
                                color: scheme.onSurface,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                showCharts ? "Hide charts" : "Show charts",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _fadeCtrl,
                      builder: (_, child) {
                        return Opacity(
                          opacity: fadeIn.value,
                          child: Transform.translate(
                            offset: Offset(0, slideIn.value),
                            child: child,
                          ),
                        );
                      },
                      child: showCharts
                          ? _buildCharts(isLarge)
                          : _buildModelMetrics(isLarge, scheme),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: GlassContainer(
                      borderRadius: BorderRadius.circular(999),
                      opacity: 0.22,
                      padding: EdgeInsets.zero,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 40, vertical: 16),
                          foregroundColor: scheme.onSurface,
                          textStyle: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const InputFormatSelection(),
                            ),
                          );
                        },
                        child: const Text("Perform Testing"),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  // build ui section
  Widget _buildCharts(bool isLarge) {
    return isLarge
        ? Row(
            children: const [
              Expanded(
                child: GlassContainer(
                  opacity: 0.16,
                  padding: EdgeInsets.all(20),
                  child: PieChartCard(),
                ),
              ),
              SizedBox(width: 20),
              Expanded(
                child: GlassContainer(
                  opacity: 0.16,
                  padding: EdgeInsets.all(20),
                  child: BarChartCard(),
                ),
              ),
            ],
          )
        : ListView(
            children: const [
              GlassContainer(
                opacity: 0.16,
                padding: EdgeInsets.all(20),
                child: SizedBox(height: 240, child: PieChartCard()),
              ),
              SizedBox(height: 20),
              GlassContainer(
                opacity: 0.16,
                padding: EdgeInsets.all(20),
                child: SizedBox(height: 240, child: BarChartCard()),
              ),
            ],
          );
  }

  // build ui section
  Widget _buildModelMetrics(bool isLarge, ColorScheme scheme) {
    return isLarge
        ? Row(
            children: [
              Expanded(
                child: GlassContainer(
                  opacity: 0.16,
                  padding: const EdgeInsets.all(20),
                  child: _metricBlock(
                    title: "Audio Model Metrics (PaSST)",
                    f1: 0.872,
                    acc: 0.8813,
                    precision: 0.879,
                    recall: 0.870,
                    scheme: scheme,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: GlassContainer(
                  opacity: 0.16,
                  padding: const EdgeInsets.all(20),
                  child: _metricBlock(
                    title: "Video Model Metrics",
                    f1: 0.92,
                    acc: 0.94,
                    precision: 0.90,
                    recall: 0.95,
                    scheme: scheme,
                  ),
                ),
              ),
            ],
          )
        : ListView(
            children: [
              GlassContainer(
                opacity: 0.16,
                padding: const EdgeInsets.all(20),
                child: _metricBlock(
                  title: "Audio Model Metrics (PaSST)",
                  f1: 0.872,
                  acc: 0.8813,
                  precision: 0.879,
                  recall: 0.870,
                  scheme: scheme,
                ),
              ),
              const SizedBox(height: 20),
              GlassContainer(
                opacity: 0.16,
                padding: const EdgeInsets.all(20),
                child: _metricBlock(
                  title: "Video Model Metrics",
                  f1: 0.92,
                  acc: 0.94,
                  precision: 0.90,
                  recall: 0.95,
                  scheme: scheme,
                ),
              ),
            ],
          );
  }

  Widget _metricBlock({
    required String title,
    required double f1,
    required double acc,
    required double precision,
    required double recall,
    required ColorScheme scheme,
  }) {
    Widget metric(String label, double value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 15,
                    color: scheme.onSurface.withValues(alpha: 0.75))),
            Text("${(value * 100).toStringAsFixed(1)}%",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface)),
        const SizedBox(height: 12),
        metric("F1 Score", f1),
        metric("Accuracy", acc),
        metric("Precision", precision),
        metric("Recall", recall),
      ],
    );
  }
}

class _GlassNavbar extends StatelessWidget {
  const _GlassNavbar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final themeCtrl = ThemeController.of(context);

    return GlassContainer(
      opacity: 0.16,
      borderRadius: BorderRadius.circular(22),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          _dot(Colors.redAccent),
          const SizedBox(width: 6),
          _dot(Colors.amber),
          const SizedBox(width: 6),
          _dot(Colors.greenAccent),
          const SizedBox(width: 12),
          Text(
            "DashBoard",
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.map_rounded),
            tooltip: 'Event Map',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EventMapScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Prediction History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.logout_rounded, color: scheme.error),
            tooltip: 'Logout',
            onPressed: () async {
              await AuthService.logout();
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const FirstResponderHome()),
                );
                showGlassSnackBar(context, 'Logged out successfully');
              }
            },
          ),
          IconButton(
            icon: Icon(
              themeCtrl.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: themeCtrl.toggleTheme,
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
        ),
      );
}

class _BackgroundBlobs extends StatelessWidget {
  final bool isDark;
  const _BackgroundBlobs({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(
        left: -140,
        top: -80,
        child: _blob(
          isDark
              ? const Color(0xFF7F5AF0).withValues(alpha: 0.45)
              : const Color(0xFF7F5AF0).withValues(alpha: 0.22),
          330,
        ),
      ),
      Positioned(
        right: -140,
        bottom: -90,
        child: _blob(
          isDark
              ? const Color(0xFF2CB67D).withValues(alpha: 0.45)
              : const Color(0xFF2CB67D).withValues(alpha: 0.22),
          330,
        ),
      ),
    ]);
  }

  Widget _blob(Color c, double size) => AnimatedContainer(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c,
          boxShadow: [
            BoxShadow(
              color: c.withValues(alpha: 0.55),
              blurRadius: 85,
              spreadRadius: 35,
            )
          ],
        ),
      );
}
