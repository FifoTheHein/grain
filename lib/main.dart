import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/ado_instance_provider.dart';
import 'providers/assignment_provider.dart';
import 'services/ado_service.dart';
import 'providers/time_entry_provider.dart';
import 'providers/project_category_provider.dart';
import 'screens/home_screen.dart';
import 'services/harvest_service.dart';
import 'theme/harvest_tokens.dart';

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
      ],
      child: MaterialApp(
        title: 'Harvest Tracker 2.0',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: HarvestTokens.brand,
          ),
          scaffoldBackgroundColor: HarvestTokens.bg,
          cardTheme: const CardThemeData(
            color: HarvestTokens.surface,
            elevation: 0,
            margin: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              side: BorderSide(color: HarvestTokens.border),
            ),
          ),
          dividerColor: HarvestTokens.divider,
          useMaterial3: true,
        ),
        home: const HomeScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
