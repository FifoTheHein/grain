import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ado_instance_provider.dart';
import '../providers/assignment_provider.dart';
import '../providers/calendar_import_provider.dart';
import '../providers/mapping_rule_provider.dart';
import '../providers/meeting_rule_provider.dart';
import '../providers/project_category_provider.dart';
import '../providers/quick_template_provider.dart';
import '../providers/theme_mode_provider.dart';
import '../providers/theme_palette_provider.dart';
import '../providers/time_entry_provider.dart';
import '../theme/harvest_tokens.dart';
import 'settings/account_settings.dart';
import 'settings/ado_settings.dart';
import 'settings/appearance_settings.dart';
import 'settings/calendar_settings.dart';
import 'settings/maintenance_settings.dart';
import 'settings/time_tracking_settings.dart';

/// The groups Settings is split into, in display order.
enum SettingsGroup {
  account('Harvest account', Icons.person_outline),
  timeTracking('Time tracking', Icons.timer_outlined),
  ado('Azure DevOps', Icons.link),
  calendar('Calendar', Icons.event_outlined),
  appearance('Appearance', Icons.palette_outlined),
  maintenance('Maintenance', Icons.build_outlined);

  final String title;
  final IconData icon;
  const SettingsGroup(this.title, this.icon);

  Widget page() => switch (this) {
        SettingsGroup.account => const AccountSettingsPage(),
        SettingsGroup.timeTracking => const TimeTrackingSettingsPage(),
        SettingsGroup.ado => const AdoSettingsPage(),
        SettingsGroup.calendar => const CalendarSettingsPage(),
        SettingsGroup.appearance => const AppearanceSettingsPage(),
        SettingsGroup.maintenance => const MaintenanceSettingsPage(),
      };
}

/// Settings: a short list of groups, each opening its own page.
///
/// Narrow, the list and a page take turns, with a back arrow (and the system
/// back gesture) returning to the list. Wide, the list is a sidebar beside the
/// selected page. Every page saves as you change it, except the Harvest
/// credentials, which have their own button.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// The open page; null shows the list on a narrow screen.
  SettingsGroup? _selected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= HarvestTokens.kWideBreakpoint;
      return wide ? _buildWide(context) : _buildNarrow(context);
    });
  }

  Widget _buildNarrow(BuildContext context) {
    final selected = _selected;
    if (selected == null) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: _groupTiles(context, selected: null),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _selected = null);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PageHeader(
            group: selected,
            onBack: () => setState(() => _selected = null),
          ),
          const Divider(height: 1),
          Expanded(child: KeyedSubtree(key: ValueKey(selected), child: selected.page())),
        ],
      ),
    );
  }

  Widget _buildWide(BuildContext context) {
    final selected = _selected ?? SettingsGroup.account;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 240,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: _groupTiles(context, selected: selected),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: KeyedSubtree(key: ValueKey(selected), child: selected.page()),
        ),
      ],
    );
  }

  List<Widget> _groupTiles(BuildContext context, {SettingsGroup? selected}) {
    final tiles = <Widget>[];
    for (final group in SettingsGroup.values) {
      if (group == SettingsGroup.maintenance) {
        tiles.add(const Divider(indent: 16, endIndent: 16));
      }
      tiles.add(_GroupTile(
        group: group,
        summary: _summaryFor(context, group),
        selected: group == selected,
        onTap: () => setState(() => _selected = group),
      ));
    }
    return tiles;
  }

  /// One line under each group, so the list says where things stand without
  /// opening anything.
  String _summaryFor(BuildContext context, SettingsGroup group) {
    switch (group) {
      case SettingsGroup.account:
        final projects = context.watch<AssignmentProvider>().projects.length;
        final every = context.watch<TimeEntryProvider>().refreshIntervalMinutes;
        return '${_plural(projects, 'project')} · refresh every '
            '${every == 60 ? 'hour' : '$every min'}';
      case SettingsGroup.timeTracking:
        final cats = context.watch<ProjectCategoryProvider>();
        final goal = cats.weeklyGoalHours;
        final templates = context.watch<QuickTemplateProvider>().templates.length;
        return '${goal == goal.truncateToDouble() ? goal.toInt() : goal}h week · '
            '${cats.workDayStart.format(context)}–${cats.workDayEnd.format(context)} · '
            '${_plural(templates, 'template')}';
      case SettingsGroup.ado:
        final instances = context.watch<AdoInstanceProvider>().instances.length;
        final rules = context.watch<MappingRuleProvider>().rules.length;
        return '${_plural(instances, 'instance')} · ${_plural(rules, 'rule')}';
      case SettingsGroup.calendar:
        final calendar = context.watch<CalendarImportProvider>();
        final rules = context.watch<MeetingRuleProvider>().rules.length;
        final mode = !CalendarImportProvider.canFetchUrl
            ? 'Upload .ics'
            : calendar.icsUrl.isEmpty
                ? 'Not set up'
                : calendar.autoLog
                    ? 'Auto-log on'
                    : 'Auto-log off';
        return '$mode · ${_plural(rules, 'meeting rule')}';
      case SettingsGroup.appearance:
        final palette = context.watch<ThemePaletteProvider>().palette.label;
        final mode = switch (context.watch<ThemeModeProvider>().mode) {
          ThemeMode.system => 'System',
          ThemeMode.light => 'Light',
          ThemeMode.dark => 'Dark',
        };
        return '$palette · $mode';
      case SettingsGroup.maintenance:
        return 'Clear cache, migrate references, reset';
    }
  }

  static String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
}

class _GroupTile extends StatelessWidget {
  final SettingsGroup group;
  final String summary;
  final bool selected;
  final VoidCallback onTap;

  const _GroupTile({
    required this.group,
    required this.summary,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return ListTile(
      leading: Icon(group.icon, color: selected ? palette.brand : palette.text2),
      title: Text(
        group.title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: selected ? palette.brand : palette.text,
        ),
      ),
      subtitle: Text(
        summary,
        // Two lines, so the summary survives the narrow wide-layout sidebar.
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: palette.text3),
      ),
      trailing: Icon(Icons.chevron_right, color: palette.text3),
      selected: selected,
      selectedTileColor: palette.brandTint,
      onTap: onTap,
    );
  }
}

class _PageHeader extends StatelessWidget {
  final SettingsGroup group;
  final VoidCallback onBack;

  const _PageHeader({required this.group, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'All settings',
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          Icon(group.icon, size: 20, color: palette.text2),
          const SizedBox(width: 8),
          Text(
            group.title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
        ],
      ),
    );
  }
}
