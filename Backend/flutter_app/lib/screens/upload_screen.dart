import 'package:flutter/material.dart';
import '../theme/theme_controller.dart';
import '../widgets/glass_container.dart';
import '../widgets/background_blobs.dart';

class UploadScreen extends StatelessWidget {
  final String type;

  const UploadScreen({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final isSmallScreen = screenWidth < 400;
    final isMediumScreen = screenWidth >= 400 && screenWidth < 600;
    final containerWidth = screenWidth < 500
        ? screenWidth * 0.9
        : (screenWidth < 800 ? screenWidth * 0.7 : 440.0);
    final containerPadding = isSmallScreen ? 18.0 : 26.0;
    final iconSize = isSmallScreen ? 58.0 : (isMediumScreen ? 68.0 : 78.0);
    final titleFontSize = isSmallScreen ? 16.0 : (isMediumScreen ? 18.0 : 20.0);
    final subtitleFontSize =
        isSmallScreen ? 11.0 : (isMediumScreen ? 12.0 : 13.0);
    final topSpacing = screenHeight < 600 ? 20.0 : 40.0;

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
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 8.0 : 0.0,
                  ),
                  child: _GlassNavbar(title: "Upload - $type"),
                ),
                SizedBox(height: topSpacing),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 12.0 : 16.0,
                        ),
                        child: GlassContainer(
                          opacity: 0.22,
                          padding: EdgeInsets.all(containerPadding),
                          borderRadius: BorderRadius.circular(28),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: containerWidth,
                              minWidth: 200,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.cloud_upload_outlined,
                                  size: iconSize,
                                  color: scheme.primary,
                                ),
                                SizedBox(height: isSmallScreen ? 14 : 20),
                                Text(
                                  "Drag & Drop or Locate File",
                                  style: TextStyle(
                                    fontSize: titleFontSize,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurface,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: isSmallScreen ? 8 : 10),
                                Text(
                                  "Supported formats depend on the selected mode.\n"
                                  "This is the upload step for your MVATS testing.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: subtitleFontSize,
                                    color: scheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                                SizedBox(height: isSmallScreen ? 18 : 26),
                                OutlinedButton.icon(
                                  onPressed: () {},
                                  icon: const Icon(Icons.folder_open),
                                  label: const Text("Browse Files"),
                                  style: OutlinedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isSmallScreen ? 18 : 26,
                                      vertical: isSmallScreen ? 12 : 15,
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
                      ),
                    ),
                  ),
                ),
                SizedBox(height: screenHeight < 600 ? 16 : 30),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _GlassNavbar extends StatelessWidget {
  final String title;

  const _GlassNavbar({required this.title});

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
            title,
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
    );
  }
}
