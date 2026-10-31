// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/tasks/create_task_screen.dart';
import 'screens/tasks/tasks_screen.dart';
import 'screens/admin/users_screen.dart';
import 'services/task_service.dart';
import 'models/user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'config/supabase_config.dart';
import 'services/auth_service.dart';
import 'services/firestore_task_service.dart';
import 'services/notification_service.dart';
import 'services/theme_service.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase (database & auth backend)
  try {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
    debugPrint('Supabase initialized successfully');
  } catch (e) {
    debugPrint('Supabase initialization notice: $e');
  }

  // Initialize local notification system
  try {
    NotificationService.setNavigatorKey(appNavigatorKey);
    await NotificationService.init();
    await NotificationService.requestPermissions();
  } catch (e) {
    debugPrint('NotificationService initialization failed: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TaskService()),
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => FirestoreTaskService()),
        ChangeNotifierProvider(create: (_) => ThemeService()),
      ],
      child: MyApp(navigatorKey: appNavigatorKey),
    ),
  );
}

class MyApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  const MyApp({super.key, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'KeiTask Student Progress Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB3E5FC),
          surface: const Color(0xFFFFFFFF),
        ).copyWith(
          primary: const Color(0xFF42A5F5),
          secondary: const Color(0xFF90CAF9),
          primaryContainer: const Color(0xFFEFF8FF),
        ),
        scaffoldBackgroundColor: const Color(0xFFEFF8FF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFEFF8FF),
          foregroundColor: Color(0xFF0F1724),
          elevation: 0,
          iconTheme: IconThemeData(color: Color(0xFF0F1724)),
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: const Color(0xFF0F1724),
          displayColor: const Color(0xFF0F1724),
        ),
        cardColor: const Color(0xFFFFFFFF),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5EA8FF),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF222831),
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFF222831),
          secondary: const Color(0xFF393E46),
          primaryContainer: const Color(0xFF1E2933),
        ),
        scaffoldBackgroundColor: const Color(0xFF222831),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF222831),
          foregroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
        ),
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
        cardColor: const Color(0xFF393E46),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF00ADB5),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00ADB5),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      themeMode: Provider.of<ThemeService>(context).themeMode,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/dashboard': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args is User) {
            return DashboardScreen(user: args);
          }
          if (args is Map && args['user'] is User) {
            return DashboardScreen(user: args['user'] as User);
          }
          return const DashboardScreen();
        },
        '/tasks': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args is User) {
            return TasksScreen(user: args);
          }
          if (args is Map && args['user'] is User) {
            return TasksScreen(user: args['user'] as User);
          }
          final currentUser = Provider.of<AuthService>(context, listen: false).appUser;
          if (currentUser != null) return TasksScreen(user: currentUser);
          return const DashboardScreen();
        },
        '/create-task': (context) {
          return const CreateTaskScreen();
        },
        '/admin/users': (context) {
          return const UsersScreen();
        },
      },
    );
  }
}
