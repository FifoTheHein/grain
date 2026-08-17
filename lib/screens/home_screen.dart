import 'package:flutter/material.dart';
import 'insights_screen.dart';
import 'log_time_screen.dart';
import 'recent_entries_screen.dart';
import 'settings_screen.dart';
import '../theme/harvest_tokens.dart';

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
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights),
      label: 'Insights',
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
    InsightsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= HarvestTokens.kWideBreakpoint;

        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  labelType: NavigationRailLabelType.all,
                  indicatorColor: palette.brandTint,
                  selectedIconTheme:
                      IconThemeData(color: palette.brand),
                  selectedLabelTextStyle: TextStyle(
                    color: palette.brand,
                    fontWeight: FontWeight.w600,
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.list_alt_outlined),
                      selectedIcon: Icon(Icons.list_alt),
                      label: Text('Recent'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.add_circle_outline),
                      selectedIcon: Icon(Icons.add_circle),
                      label: Text('Log Time'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.insights_outlined),
                      selectedIcon: Icon(Icons.insights),
                      label: Text('Insights'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      AppBar(
                        leading: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset('assets/icon.png'),
                          ),
                        ),
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Grain',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 18)),
                            Text('A better Harvest',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withValues(alpha: 0.8))),
                          ],
                        ),
                        backgroundColor: palette.brand,
                        foregroundColor: Colors.white,
                        elevation: 2,
                      ),
                      // NavigationRail insets itself and the in-column AppBar
                      // pads for the status bar, so this covers the right
                      // edge and the gesture bar.
                      Expanded(
                        child: SafeArea(
                          top: false,
                          left: false,
                          child: Center(
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 760),
                              child: _screens[_tab],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/icon.png'),
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Grain',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 18)),
                Text('A better Harvest',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.8))),
              ],
            ),
            backgroundColor: palette.brand,
            foregroundColor: Colors.white,
            elevation: 2,
          ),
          // AppBar and NavigationBar consume the top and bottom insets between
          // them; this covers the sides, for a landscape notch or rounded
          // corners.
          body: SafeArea(
            top: false,
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: _screens[_tab],
              ),
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: _destinations,
          ),
        );
      },
    );
  }
}
