import 'package:flutter/material.dart';
import '../models/log_time_prefill.dart';
import 'insights_screen.dart';
import 'log_time_screen.dart';
import 'recent_entries_screen.dart';
import 'settings_screen.dart';
import '../theme/harvest_tokens.dart';

/// Switches to Log Time on a date, optionally with the form pre-filled.
typedef LogTimeHandover = void Function(DateTime date,
    {LogTimePrefill? prefill});

/// Lets a screen under [HomeScreen] switch tabs, e.g. Recent's empty future
/// day opening Log Time on that date, or Insights' "Log this" opening it
/// pre-filled with an open stretch.
class HomeNavigation extends InheritedWidget {
  /// Switches to Log Time with the date preselected and, when given, the
  /// prefill applied.
  final LogTimeHandover logTimeFor;

  const HomeNavigation({
    super.key,
    required this.logTimeFor,
    required super.child,
  });

  /// Null outside a [HomeScreen], as in tests that pump a screen alone.
  static HomeNavigation? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HomeNavigation>();

  @override
  bool updateShouldNotify(HomeNavigation oldWidget) => false;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  /// The date Log Time opens on when another screen handed one over. Cleared
  /// by any ordinary tab change, so a later visit opens on today as usual.
  DateTime? _logTimeDate;
  LogTimePrefill? _logTimePrefill;

  static const _logTimeTab = 1;

  void _selectTab(int i) => setState(() {
        _tab = i;
        _logTimeDate = null;
        _logTimePrefill = null;
      });

  void _logTimeFor(DateTime date, {LogTimePrefill? prefill}) => setState(() {
        _tab = _logTimeTab;
        _logTimeDate = date;
        _logTimePrefill = prefill;
      });

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

  Widget get _screen => HomeNavigation(
        logTimeFor: _logTimeFor,
        child: switch (_tab) {
          0 => const RecentEntriesScreen(),
          _logTimeTab => LogTimeScreen(
              initialDate: _logTimeDate, prefill: _logTimePrefill),
          2 => const InsightsScreen(),
          _ => const SettingsScreen(),
        },
      );

  static const _settingsTab = 3;

  /// Content width on a wide window. Entry lists read best narrow; Settings
  /// puts a sidebar beside its page, so it gets room for both.
  double get _wideMaxWidth => _tab == _settingsTab ? 1200 : 760;

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
                  onDestinationSelected: _selectTab,
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
                                    color: palette.onBrand.withValues(alpha: 0.8))),
                          ],
                        ),
                        backgroundColor: palette.brand,
                        foregroundColor: palette.onBrand,
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
                                  BoxConstraints(maxWidth: _wideMaxWidth),
                              child: _screen,
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
                        color: palette.onBrand.withValues(alpha: 0.8))),
              ],
            ),
            backgroundColor: palette.brand,
            foregroundColor: palette.onBrand,
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
                child: _screen,
              ),
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _selectTab,
            destinations: _destinations,
          ),
        );
      },
    );
  }
}
