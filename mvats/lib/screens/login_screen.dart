// Admin login screen
import 'package:flutter/material.dart';
import '../theme/theme_controller.dart';
import '../widgets/glass_container.dart';
import '../widgets/background_blobs.dart';
import '../services/auth_service.dart';
import '../utils/glass_snackbar.dart';
import 'landing_page.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeIn;
  late Animation<double> _slideIn;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeIn = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _slideIn = Tween<double>(begin: 30, end: 0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic),
    );
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // handle user action
  Future<void> _handleSubmit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      showGlassSnackBar(context, 'Please enter username and password',
          isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await AuthService.login(username, password);

      if (!mounted) return;
      final role = result['user']['role'];

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LandingPage()),
      );
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(context, e.toString().replaceFirst('Exception: ', ''),
          isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // show dialog or ui
  void _showForgotPassword() {
    final resetUsername = TextEditingController();
    final resetPassword = TextEditingController();
    final resetAdminKey = TextEditingController();
    bool resetObscure = true;
    bool keyObscure = true;
    bool resetLoading = false;

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final scheme = Theme.of(ctx).colorScheme;
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(28),
                  blur: 20,
                  opacity: 0.22,
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_reset_rounded,
                          size: 40, color: scheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        'Reset Password',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        controller: resetUsername,
                        hint: 'Username',
                        icon: Icons.person_outline_rounded,
                        scheme: scheme,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: resetAdminKey,
                        hint: 'Admin Secret Key',
                        icon: Icons.vpn_key_rounded,
                        scheme: scheme,
                        obscure: keyObscure,
                        suffixIcon: IconButton(
                          icon: Icon(
                            keyObscure
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 20,
                            color: scheme.onSurface.withValues(alpha: 0.5),
                          ),
                          onPressed: () =>
                              setDialogState(() => keyObscure = !keyObscure),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: resetPassword,
                        hint: 'New Password',
                        icon: Icons.lock_outline_rounded,
                        scheme: scheme,
                        obscure: resetObscure,
                        suffixIcon: IconButton(
                          icon: Icon(
                            resetObscure
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 20,
                            color: scheme.onSurface.withValues(alpha: 0.5),
                          ),
                          onPressed: () => setDialogState(
                              () => resetObscure = !resetObscure),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text('Cancel',
                                  style: TextStyle(
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.7))),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GlassContainer(
                              borderRadius: BorderRadius.circular(999),
                              opacity: 0.25,
                              padding: EdgeInsets.zero,
                              child: TextButton(
                                onPressed: resetLoading
                                    ? null
                                    : () async {
                                        if (resetUsername.text.trim().isEmpty ||
                                            resetPassword.text.trim().isEmpty ||
                                            resetAdminKey.text.trim().isEmpty) {
                                          showGlassSnackBar(
                                              ctx, 'Fill in all fields',
                                              isError: true);
                                          return;
                                        }
                                        setDialogState(
                                            () => resetLoading = true);
                                        try {
                                          await AuthService.resetPassword(
                                            resetUsername.text.trim(),
                                            resetPassword.text.trim(),
                                            resetAdminKey.text.trim(),
                                          );
                                          if (ctx.mounted) {
                                            Navigator.pop(ctx);
                                            showGlassSnackBar(context,
                                                'Password reset successfully');
                                          }
                                        } catch (e) {
                                          if (ctx.mounted) {
                                            showGlassSnackBar(
                                                ctx,
                                                e.toString().replaceFirst(
                                                    'Exception: ', ''),
                                                isError: true);
                                          }
                                        } finally {
                                          if (ctx.mounted)
                                            setDialogState(
                                                () => resetLoading = false);
                                        }
                                      },
                                child: resetLoading
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: scheme.onSurface))
                                    : Text('Reset',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: scheme.onSurface)),
                              ),
                            ),
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
      },
    );
  }

  // build ui section
  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required ColorScheme scheme,
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      opacity: 0.12,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: TextStyle(color: scheme.onSurface),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.4)),
          prefixIcon: Icon(icon,
              size: 20, color: scheme.onSurface.withValues(alpha: 0.5)),
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeCtrl = ThemeController.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          BackgroundBlobs(isDark: isDark),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  GlassContainer(
                    opacity: 0.16,
                    borderRadius: BorderRadius.circular(22),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, size: 22),
                          color: scheme.onSurface,
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Admin Access',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(themeCtrl.isDarkMode
                              ? Icons.light_mode
                              : Icons.dark_mode),
                          onPressed: themeCtrl.toggleTheme,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _fadeCtrl,
                        builder: (_, child) => Opacity(
                          opacity: _fadeIn.value,
                          child: Transform.translate(
                            offset: Offset(0, _slideIn.value),
                            child: child,
                          ),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: SingleChildScrollView(
                            child: GlassContainer(
                              borderRadius: BorderRadius.circular(28),
                              opacity: 0.18,
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 70,
                                    height: 70,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          const Color(0xFF7C4DFF)
                                              .withValues(alpha: 0.3),
                                          const Color(0xFF9C27B0)
                                              .withValues(alpha: 0.3),
                                        ],
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.admin_panel_settings_rounded,
                                      size: 36,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'Admin Login',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Sign in to access the full admin panel',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  _buildTextField(
                                    controller: _usernameController,
                                    hint: 'Username',
                                    icon: Icons.person_outline_rounded,
                                    scheme: scheme,
                                  ),
                                  const SizedBox(height: 14),
                                  _buildTextField(
                                    controller: _passwordController,
                                    hint: 'Password',
                                    icon: Icons.lock_outline_rounded,
                                    scheme: scheme,
                                    obscure: _obscurePassword,
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_rounded
                                            : Icons.visibility_rounded,
                                        size: 20,
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.5),
                                      ),
                                      onPressed: () => setState(() =>
                                          _obscurePassword = !_obscurePassword),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _showForgotPassword,
                                      child: Text(
                                        'Forgot Password?',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: const Color(0xFF7C4DFF),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: GlassContainer(
                                      borderRadius: BorderRadius.circular(999),
                                      opacity: 0.25,
                                      padding: EdgeInsets.zero,
                                      child: TextButton(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 16),
                                          foregroundColor: scheme.onSurface,
                                          textStyle: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600),
                                        ),
                                        onPressed:
                                            _isLoading ? null : _handleSubmit,
                                        child: _isLoading
                                            ? SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: scheme.onSurface,
                                                ),
                                              )
                                            : const Text('Sign In'),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
