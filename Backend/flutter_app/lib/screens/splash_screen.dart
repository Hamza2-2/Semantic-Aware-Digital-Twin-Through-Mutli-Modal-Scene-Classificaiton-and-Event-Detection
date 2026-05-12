// file header note
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';
import 'landing_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> progress;
  late Animation<double> textOpacity;
  late Animation<double> textOffset;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.60, 1.0, curve: Curves.easeInOut),
    );

    textOffset = Tween<double>(begin: 18, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.60, 1.0, curve: Curves.easeOutQuad),
      ),
    );

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 3400), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 650),
          pageBuilder: (_, __, ___) => const LandingPage(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            );
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? SorhusColors.softBackgroundDark
        : SorhusColors.softBackgroundLight;

    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        return Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: bg),
              
              Positioned(
                left: -90,
                top: -60,
                child: _blob(
                  isDark
                      ? SorhusColors.purple.withValues(alpha: 0.60)
                      : SorhusColors.purple.withValues(alpha: 0.25),
                  260,
                ),
              ),
              Positioned(
                right: -70,
                bottom: -70,
                child: _blob(
                  isDark
                      ? SorhusColors.teal.withValues(alpha: 0.60)
                      : SorhusColors.teal.withValues(alpha: 0.25),
                  260,
                ),
              ),
              Center(
                child: GlassContainer(
                  blur: 22,
                  opacity: isDark ? 0.28 : 0.20,
                  borderRadius: BorderRadius.circular(40),
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CustomPaint(
                        size: const Size(260, 260),
                        painter: _SmoothSplashPainter(t: progress.value),
                      ),
                      const SizedBox(height: 24),
                      Opacity(
                        opacity: textOpacity.value,
                        child: Transform.translate(
                          offset: Offset(0, textOffset.value),
                          child: Column(
                            children: const [
                              Text(
                                'Sematic Aware Digital Digital Twin',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Mutli-Modal Scene Classification',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _blob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.9),
            blurRadius: 60,
            spreadRadius: 20,
          ),
        ],
      ),
    );
  }
}

class _SmoothSplashPainter extends CustomPainter {
  final double t;
  _SmoothSplashPainter({required this.t});

  static const int dropletCount = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final s = size.shortestSide;

    final logoRadius = s * 0.36;
    final dropletRadius = s * 0.075;
    final dropletMaxDist = s * 0.33;

    double logoScale;
    if (t < 0.30) {
      logoScale = Tween(begin: 0.7, end: 1.3).transform(t / 0.30);
    } else if (t < 0.60) {
      logoScale = 1.3 + sin((t - 0.30) * pi * 3) * 0.04;
    } else {
      logoScale = Tween(begin: 1.3, end: 0.42)
          .transform((t - 0.60) / 0.25)
          .clamp(0.42, 1.3);
    }

    double logoOpacity;
    if (t < 0.55) {
      logoOpacity = 1.0;
    } else if (t < 0.75) {
      logoOpacity = Tween(begin: 1.0, end: 0.0).transform((t - 0.55) / 0.20);
    } else {
      logoOpacity = 0.0;
    }

    final rotation = t * pi * 1.2;

    if (logoOpacity > 0) {
      final logoPaint = Paint()
        ..shader = const LinearGradient(
          colors: [
            SorhusColors.teal,
            SorhusColors.brightBlue,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(
          Rect.fromCircle(center: center, radius: logoRadius),
        )
        ..colorFilter = ColorFilter.mode(
          Colors.white.withValues(alpha: logoOpacity),
          BlendMode.modulate,
        );

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation);
      canvas.scale(logoScale);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawCircle(center, logoRadius, logoPaint);
      canvas.restore();

      final iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(Icons.analytics_outlined.codePoint),
          style: TextStyle(
            fontFamily: Icons.analytics_outlined.fontFamily,
            package: Icons.analytics_outlined.fontPackage,
            fontSize: 48,
            color: Colors.white.withValues(alpha: logoOpacity),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      iconPainter.paint(
        canvas,
        center - Offset(iconPainter.width / 2, iconPainter.height / 2),
      );
    }

    double distFactor;
    if (t < 0.35) {
      distFactor = 0.0;
    } else if (t < 0.60) {
      distFactor = Curves.easeOut.transform((t - 0.35) / 0.25);
    } else if (t < 0.80) {
      distFactor = 1.0;
    } else if (t < 0.95) {
      distFactor = Curves.easeIn.transform(1 - (t - 0.80) / 0.15);
    } else {
      distFactor = 0.0;
    }

    final dropletDist = dropletMaxDist * distFactor;

    if (dropletDist > 0) {
      final trailPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.20)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      for (int i = 0; i < dropletCount; i++) {
        final base = (2 * pi / dropletCount) * i;
        final spin = t * 2 * pi * 1.2;
        final angle = base + spin;

        final pos = Offset(
          center.dx + cos(angle) * dropletDist,
          center.dy + sin(angle) * dropletDist,
        );

        canvas.drawLine(Offset.lerp(center, pos, 0.25)!, pos, trailPaint);

        final color = [
          SorhusColors.hotPink,
          SorhusColors.fuchsia,
          SorhusColors.purple,
          SorhusColors.blue,
          SorhusColors.brightBlue,
          SorhusColors.teal,
        ][i % 6];

        canvas.drawCircle(
          pos,
          dropletRadius,
          Paint()..color = color.withValues(alpha: 0.95),
        );
      }
    }

    if (t > 0.88) {
      final flashT = (t - 0.88) / 0.12;
      final flashPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * (1 - flashT)
        ..color = Colors.white.withValues(alpha: (1 - flashT) * 0.85);
      canvas.drawCircle(
        center,
        dropletMaxDist * (1 + flashT * 0.6),
        flashPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SmoothSplashPainter oldDelegate) =>
      oldDelegate.t != t;
}
