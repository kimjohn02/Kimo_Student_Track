import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../../services/notification_service.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../models/user_model.dart';
import '../../services/firestore_task_service.dart';
import 'package:keitask_management/widgets/circular_nav_bar.dart';
import '../auth/login_screen.dart';
import '../tasks/tasks_screen.dart';
import '../profile/profile_screen.dart';
import '../leaderboard/leaderboard_screen.dart';
import 'admin_dashboard.dart';
import 'user_dashboard.dart';
import '../tasks/admin_tasks_approval_screen.dart';
import '../admin/users_screen.dart';
import '../admin/task_statistics_screen.dart';

class DashboardScreen extends StatefulWidget {
  final User? user;

  const DashboardScreen({super.key, this.user});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  late final PageController _pageController;

  // Track known task IDs to detect new ones
  Set<String> _knownTaskIds = {};
  bool _isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _listenForNewTasks();
  }

  void _listenForNewTasks() {
    final firestore = Provider.of<FirestoreTaskService>(context, listen: false);
    firestore.tasksStream().listen((tasks) {
      if (!mounted) return;

      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = widget.user ?? authService.appUser;
      if (currentUser == null) return;

      // Filter tasks assigned to this user
      final myTasks = tasks
          .where((t) => t.assignees.contains(currentUser.id))
          .toList();

      if (_isFirstLoad) {
        _knownTaskIds = myTasks.map((t) => t.id).toSet();
        _isFirstLoad = false;
        return;
      }

      final userPrefs = currentUser.notificationsEnabled ?? true;
      for (var task in myTasks) {
        if (!_knownTaskIds.contains(task.id)) {
          _knownTaskIds.add(task.id);
          if (userPrefs) NotificationService.showTaskNotification(task);
        }
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabSelected(int index) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = widget.user ?? authService.appUser;
    if (currentUser == null) return;

    final role = currentUser.role.toLowerCase();
    if (role == 'professor' && index == 2) {
      // "New Task" action - Navigate to CreateTaskScreen
      Navigator.pushNamed(context, '/create-task', arguments: currentUser);
      return; // Do not update _currentIndex
    }

    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _backToHome() {
    setState(() => _currentIndex = 0);
    _pageController.jumpToPage(0);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final effectiveUser = widget.user ?? auth.appUser;

    // Gracefully handle cold start, page refresh, or missing session
    if (effectiveUser == null) {
      if (auth.supabaseUser != null) {
        return const Scaffold(
          backgroundColor: Color(0xFFEFF8FF),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Loading your dashboard...',
                  style: TextStyle(
                    color: Color(0xFF0F1724),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return const LoginScreen();
    }

    final role = effectiveUser.role.toLowerCase();
    final isAdmin = role == 'admin';
    final isProfessor = role == 'professor';

    List<Widget> screens;
    List<CircularNavBarItem> navItems;

    if (isAdmin) {
      screens = [
        AdminDashboard(user: effectiveUser),
        AdminTasksApprovalScreen(user: effectiveUser),
        const UsersScreen(showBackButton: false),
        const LeaderboardScreen(showBackButton: false),
        ProfileScreen(user: effectiveUser, onBackToHome: _backToHome),
      ];
      navItems = [
        const CircularNavBarItem(icon: Icons.home, label: 'Home'),
        const CircularNavBarItem(icon: Icons.check_circle, label: 'Approvals'),
        const CircularNavBarItem(
          icon: Icons.manage_accounts,
          label: 'Manage Users',
        ),
        const CircularNavBarItem(icon: Icons.leaderboard, label: 'Leaderboard'),
        const CircularNavBarItem(icon: Icons.person, label: 'Profile'),
      ];
    } else if (isProfessor) {
      screens = [
        UserDashboard(user: effectiveUser),
        AdminTasksApprovalScreen(
          user: effectiveUser,
        ), // Professors use this to approve/reject
        const SizedBox(), // Placeholder for "New Task" (handled in _onTabSelected)
        const TaskStatisticsScreen(showBackButton: false),
        ProfileScreen(user: effectiveUser, onBackToHome: _backToHome),
      ];
      navItems = [
        const CircularNavBarItem(icon: Icons.home, label: 'Home'),
        const CircularNavBarItem(icon: Icons.task, label: 'Tasks'),
        const CircularNavBarItem(icon: Icons.add_circle, label: 'New Task'),
        const CircularNavBarItem(icon: Icons.analytics, label: 'Analytics'),
        const CircularNavBarItem(icon: Icons.person, label: 'Profile'),
      ];
    } else {
      // Student
      screens = [
        UserDashboard(user: effectiveUser),
        TasksScreen(user: effectiveUser, showBackButton: false),
        const LeaderboardScreen(showBackButton: false),
        ProfileScreen(user: effectiveUser, onBackToHome: _backToHome),
      ];
      navItems = [
        const CircularNavBarItem(icon: Icons.home, label: 'Home'),
        const CircularNavBarItem(icon: Icons.task, label: 'Tasks'),
        const CircularNavBarItem(icon: Icons.leaderboard, label: 'Leaderboard'),
        const CircularNavBarItem(icon: Icons.person, label: 'Profile'),
      ];
    }

    // Keep current index within bounds
    if (_currentIndex >= screens.length) {
      _currentIndex = screens.length - 1;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentIndex);
      }
    }

    return Scaffold(
      floatingActionButton: kDebugMode
          ? FloatingActionButton(
              onPressed: () {
                final demoTask = Task(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  title: 'Demo Task',
                  description: 'This is a demo task notification',
                  status: 'approved',
                  assignees: [effectiveUser.id],
                  dueDate: DateTime.now().add(const Duration(days: 1)),
                );
                NotificationService.showTaskNotification(demoTask);
              },
              child: const Icon(Icons.notifications),
            )
          : null,
      extendBody: false,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (int idx) => setState(() => _currentIndex = idx),
        children: screens,
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 0.0),
        child: CircularNavBar(
          items: navItems,
          currentIndex: _currentIndex,
          onTap: _onTabSelected,
        ),
      ),
    );
  }
}
