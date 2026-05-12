import 'package:flutter/material.dart';

class BackgroundBlobs extends StatelessWidget {
  final bool isDark;

  const BackgroundBlobs({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final base = isDark ? const Color(0xFF050816) : const Color(0xFFF4F5FF);

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.2),
              radius: 1.4,
              colors: isDark
                  ? [
                      const Color(0xFF141726),
                      base,
                    ]
                  : [
                      Colors.white,
                      base,
                    ],
            ),
          ),
        ),
        Positioned(
          left: -140,
          top: -80,
          child: _blob(
            isDark
                ? const Color(0xFF7F5AF0).withValues(alpha: 0.55)
                : const Color(0xFF7F5AF0).withValues(alpha: 0.25),
            320,
          ),
        ),
        Positioned(
          right: -130,
          bottom: -90,
          child: _blob(
            isDark
                ? const Color(0xFF2CB67D).withValues(alpha: 0.55)
                : const Color(0xFF2CB67D).withValues(alpha: 0.22),
            310,
          ),
        ),
      ],
    );
  }

  Widget _blob(Color c, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: c.withValues(alpha: 0.7),
              blurRadius: 80,
              spreadRadius: 32,
            ),
          ],
        ),
      );
}
