// Glass style snackbar helper
import 'dart:ui';
import 'package:flutter/material.dart';

void showGlassSnackBar(
  BuildContext context,
  String message, {
  IconData? icon,
  Color? iconColor,
  Duration duration = const Duration(seconds: 3),
  bool isError = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final screenWidth = MediaQuery.of(context).size.width;

  final effectiveIcon = icon ??
      (isError ? Icons.error_outline_rounded : Icons.check_circle_rounded);
  final effectiveIconColor = iconColor ??
      (isError
          ? Colors.redAccent
          : (isDark ? Colors.greenAccent : Colors.green));

  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: (screenWidth * 0.5).clamp(280, 480),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      (isDark ? const Color(0xFF1A1A2E) : Colors.white)
                          .withValues(alpha: isDark ? 0.7 : 0.85),
                      (isDark ? const Color(0xFF16213E) : Colors.white)
                          .withValues(alpha: isDark ? 0.4 : 0.6),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(effectiveIcon, color: effectiveIconColor, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message,
                        style: TextStyle(
                          color: isDark ? Colors.white : scheme.onSurface,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      duration: duration,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).size.height - 120,
        left: 0,
        right: 0,
      ),
    ),
  );
}
