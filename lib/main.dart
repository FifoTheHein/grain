import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/ado_instance_provider.dart';
import 'providers/assignment_provider.dart';
import 'services/ado_service.dart';
import 'providers/time_entry_provider.dart';
import 'providers/project_category_provider.dart';
import 'providers/theme_mode_provider.dart';
import 'screens/home_screen.dart';
import 'services/harvest_service.dart';
import 'theme/grain_theme.dart';

void main() {
  runApp(const HarvestApp());
}

class HarvestApp extends StatelessWidget {
  const HarvestApp({super.key});

  @override
  Widget build(BuildContext context) {
    final service = HarvestService();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AdoService()..init(),
        ),
        ChangeNotifierProvider(
          create: (_) => AdoInstanceProvider()..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => AssignmentProvider(service)..load(),
        ),
        ChangeNotifierProvider(
          create: (_) {
            final provider = TimeEntryProvider(service);
            provider.loadRecentEntries().then((_) => provider.startAutoRefresh());
            return provider;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => ProjectCategoryProvider()..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => ThemeModeProvider()..load(),
        ),
      ],
      child: Consumer<ThemeModeProvider>(
        builder: (context, themeMode, _) => MaterialApp(
          title: 'Grain',
          theme: buildGrainTheme(Brightness.light),
          darkTheme: buildGrainTheme(Brightness.dark),
          themeMode: themeMode.mode,
          home: const HomeScreen(),
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
