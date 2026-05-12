// App entry point and theme setup
import 'package:flutter/material.dart';
import 'theme/theme_controller.dart';
import 'screens/splash_screen.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

// app entry point
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ThemeController.instance.loadTheme();

  runApp(const MVATSApp());
}

class MVATSApp extends StatefulWidget {
  const MVATSApp({super.key});

  @override
  State<MVATSApp> createState() => _MVATSAppState();

  static ThemeController of(BuildContext context) => ThemeController.instance;
}

class _MVATSAppState extends State<MVATSApp> {
  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_themeChanged);
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_themeChanged);
    super.dispose();
  }

  void _themeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.instance.isDarkMode;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sematic Aware Digital Twin- Mutli-Modal Scene Classification',
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      navigatorObservers: [routeObserver],
      home: const SplashScreen(),
    );
  }
}
