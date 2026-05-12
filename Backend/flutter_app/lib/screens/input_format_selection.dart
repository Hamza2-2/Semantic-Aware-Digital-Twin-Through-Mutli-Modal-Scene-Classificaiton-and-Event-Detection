import 'package:flutter/material.dart';
import '../theme/theme_controller.dart';
import '../widgets/glass_container.dart';
import 'audio_testing_screen.dart';
import 'video_testing_screen.dart';
import 'multimodal_testing_screen.dart';

class InputFormatSelection extends StatelessWidget {
  const InputFormatSelection({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final options = [
      _FormatOption(
        label: "Audio Only",
        icon: Icons.graphic_eq,
        gradient: const [
          Color(0xFF7F5AF0),
          Color(0xFF4EA8DE),
        ],
        targetScreen: const AudioTestingScreen(),
      ),
      _FormatOption(
        label: "Video Only (No Audio)",
        icon: Icons.videocam_rounded,
        gradient: const [
          Color(0xFFE254FF),
          Color(0xFF7F5AF0),
        ],
        targetScreen: const VideoTestingScreen(),
      ),
      _FormatOption(
        label: "Multimodal (Audio + Video)",
        icon: Icons.multitrack_audio_rounded,
        gradient: const [
          Color(0xFFFF5592),
          Color(0xFFE254FF),
        ],
        targetScreen: const MultimodalTestingScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        children: [
          _BackgroundBlobs(isDark: isDark),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 10),
                const _GlassNavbar(),
                const SizedBox(height: 30),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth > 700;

                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Wrap(
                            spacing: 30,
                            runSpacing: 30,
                            alignment: WrapAlignment.center,
                            children: options.map((opt) {
                              return _FormatTile(
                                option: opt,
                                width: wide ? 260 : 220,
                                height: wide ? 210 : 190,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => opt.targetScreen,
                                    ),
                                  );
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _GlassNavbar extends StatelessWidget {
  const _GlassNavbar();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.of(context);
    final scheme = Theme.of(context).colorScheme;

    return GlassContainer(
      borderRadius: BorderRadius.circular(22),
      opacity: 0.16,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
            color: scheme.onSurface,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 10),
          const Text(
            "Select Input Format",
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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
    );
  }
}

class _FormatOption {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final Widget targetScreen;

  _FormatOption({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.targetScreen,
  });
}

class _FormatTile extends StatefulWidget {
  final _FormatOption option;
  final double width;
  final double height;
  final VoidCallback onTap;

  const _FormatTile({
    required this.option,
    required this.width,
    required this.height,
    required this.onTap,
  });

  @override
  State<_FormatTile> createState() => _FormatTileState();
}

class _FormatTileState extends State<_FormatTile> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedScale(
        scale: hovered ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 180),
        child: GestureDetector(
          onTap: widget.onTap,
          child: GlassContainer(
            opacity: 0.18,
            borderRadius: BorderRadius.circular(26),
            padding: EdgeInsets.zero,
            child: Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(
                  colors: widget.option.gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.option.gradient.first
                        .withOpacity(hovered ? 0.40 : 0.25),
                    blurRadius: hovered ? 32 : 14,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.option.icon, size: 54, color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    widget.option.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackgroundBlobs extends StatelessWidget {
  final bool isDark;

  const _BackgroundBlobs({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: -100,
          top: -60,
          child: _blob(
            isDark
                ? const Color(0xFF7F5AF0).withOpacity(0.45)
                : const Color(0xFF7F5AF0).withOpacity(0.25),
            280,
          ),
        ),
        Positioned(
          right: -120,
          bottom: -90,
          child: _blob(
            isDark
                ? const Color(0xFF2CB67D).withOpacity(0.45)
                : const Color(0xFF2CB67D).withOpacity(0.22),
            300,
          ),
        ),
      ],
    );
  }

  Widget _blob(Color c, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: c.withOpacity(0.6),
            blurRadius: 80,
            spreadRadius: 30,
          ),
        ],
      ),
    );
  }
}
