import 'package:flutter/material.dart';
import 'log_time_screen.dart';
import 'recent_entries_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.list_alt_outlined),
      selectedIcon: Icon(Icons.list_alt),
      label: 'Recent',
    ),
    NavigationDestination(
      icon: Icon(Icons.add_circle_outline),
      selectedIcon: Icon(Icons.add_circle),
      label: 'Log Time',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  final _screens = const [
    RecentEntriesScreen(),
    LogTimeScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Harvest Tracker 2.0'),
        backgroundColor: const Color(0xFFFA5D24),
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _screens[_tab],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: _destinations,
      ),
    );
  }
}
