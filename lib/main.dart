import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/ado_instance_provider.dart';
import 'providers/assignment_provider.dart';
import 'services/ado_service.dart';
import 'providers/time_entry_provider.dart';
import 'providers/mapping_rule_provider.dart';
import 'providers/project_category_provider.dart';
import 'providers/quick_template_provider.dart';
import 'providers/theme_mode_provider.dart';
import 'providers/theme_palette_provider.dart';
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
          create: (_) => MappingRuleProvider()..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => QuickTemplateProvider()..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => ThemeModeProvider()..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => ThemePaletteProvider()..load(),
        ),
      ],
      child: Consumer2<ThemeModeProvider, ThemePaletteProvider>(
        builder: (context, themeMode, themePalette, _) => MaterialApp(
          title: 'Grain',
          theme: buildGrainTheme(Brightness.light, themePalette.palette),
          darkTheme: buildGrainTheme(Brightness.dark, themePalette.palette),
          themeMode: themeMode.mode,
          home: const HomeScreen(),
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
