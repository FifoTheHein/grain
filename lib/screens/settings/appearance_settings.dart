import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/project_assignment.dart';
import '../../models/project_category.dart';
import '../../providers/assignment_provider.dart';
import '../../providers/project_category_provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../providers/theme_palette_provider.dart';
import '../../theme/harvest_tokens.dart';
import '../../theme/theme_palettes.dart';
import 'settings_shared.dart';

/// Theme mode, colour palette, and the colour and code each project shows
/// with across the app.
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPageBody(children: [
      const SettingsSectionHeader(title: 'Theme'),
      const SizedBox(height: 12),
      const _ThemeModeSelector(),
      const SizedBox(height: 16),
      const _ThemePaletteSelector(),
      const SettingsSectionDivider(),
      const SettingsSectionHeader(title: 'Project Colours'),
      const SettingsHint(
          'The colour and short code each project shows on cards and charts.'),
      const SizedBox(height: 8),
      _buildProjectCategories(context),
    ]);
  }

  Widget _buildProjectCategories(BuildContext context) {
    final projects = context.watch<AssignmentProvider>().projects;
    final catProvider = context.watch<ProjectCategoryProvider>();

    if (projects.isEmpty) {
      return Text(
        'No projects loaded.',
        style: TextStyle(fontSize: 12, color: HarvestTokens.of(context).text3),
      );
    }

    return Column(
      children: [
        for (final project in projects)
          _ProjectCategoryRow(project: project, catProvider: catProvider),
      ],
    );
  }
}

class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThemeModeProvider>();
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
          value: ThemeMode.system,
          label: Text('System'),
          icon: Icon(Icons.brightness_auto),
        ),
        ButtonSegment(
          value: ThemeMode.light,
          label: Text('Light'),
          icon: Icon(Icons.light_mode_outlined),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          label: Text('Dark'),
          icon: Icon(Icons.dark_mode_outlined),
        ),
      ],
      selected: {provider.mode},
      onSelectionChanged: (s) =>
          context.read<ThemeModeProvider>().setMode(s.first),
    );
  }
}

/// Palette picker: a card per theme showing the colours it actually uses, in
/// the mode currently on screen, so the preview matches what tapping it does.
class _ThemePaletteSelector extends StatelessWidget {
  const _ThemePaletteSelector();

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final selectedId = context.watch<ThemePaletteProvider>().id;
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Colour palette',
          style: TextStyle(fontSize: 12, color: palette.text2),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final theme in kThemePalettes)
              _PaletteCard(
                theme: theme,
                brightness: brightness,
                selected: theme.id == selectedId,
                onTap: () =>
                    context.read<ThemePaletteProvider>().setPalette(theme.id),
              ),
          ],
        ),
      ],
    );
  }
}

class _PaletteCard extends StatelessWidget {
  final GrainThemePalette theme;
  final Brightness brightness;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteCard({
    required this.theme,
    required this.brightness,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final preview = theme.forBrightness(brightness);

    return SizedBox(
      width: 168,
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? preview.brand : palette.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A miniature of the app: canvas, card, accent, ink.
                Container(
                  height: 34,
                  decoration: BoxDecoration(
                    color: preview.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: preview.border),
                  ),
                  padding: const EdgeInsets.all(5),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        decoration: BoxDecoration(
                          color: preview.brand,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: preview.surface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: preview.border),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        width: 12,
                        decoration: BoxDecoration(
                          color: preview.brandTint,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        theme.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: palette.text,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle,
                          size: 15, color: preview.brand),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  theme.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: palette.text3, height: 1.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectCategoryRow extends StatelessWidget {
  final HarvestProject project;
  final ProjectCategoryProvider catProvider;

  const _ProjectCategoryRow({
    required this.project,
    required this.catProvider,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final cat = catProvider.categoryFor(
      project.id,
      fallbackCode: project.code.isNotEmpty ? project.code : '?',
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: cat.color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: cat.tint,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              cat.code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: cat.color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: palette.text),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16),
            color: palette.text3,
            tooltip: 'Edit category',
            onPressed: () =>
                _showEditCategoryDialog(context, project, cat, catProvider),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditCategoryDialog(
    BuildContext context,
    HarvestProject project,
    ProjectCategory current,
    ProjectCategoryProvider provider,
  ) async {
    final codeController = TextEditingController(text: current.code);
    Color selectedColor = current.color;
    Color selectedTint = current.tint;

    const palette = [
      (Color(0xFFFA5D24), Color(0xFFFEE6DA)),
      (Color(0xFF7C5CFF), Color(0xFFEEE9FF)),
      (Color(0xFF14B8A6), Color(0xFFD7F5F0)),
      (Color(0xFF8A837A), Color(0xFFF1ECE3)),
      (Color(0xFF2563EB), Color(0xFFDCEAFD)),
      (Color(0xFF16A34A), Color(0xFFDCFCE7)),
      (Color(0xFFC026D3), Color(0xFFF5D0FE)),
      (Color(0xFFD97706), Color(0xFFFEF3C7)),
      (Color(0xFFDC2626), Color(0xFFFEE2E2)),
      (Color(0xFF0891B2), Color(0xFFCFFAFE)),
      (Color(0xFF65A30D), Color(0xFFECFCCB)),
      (Color(0xFFDB2777), Color(0xFFFCE7F3)),
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('Edit category — ${project.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Color', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (c, t) in palette)
                    GestureDetector(
                      onTap: () => setDlgState(() {
                        selectedColor = c;
                        selectedTint = t;
                      }),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: selectedColor == c
                              ? Border.all(color: Colors.black, width: 2)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Code (up to 5 letters)',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: codeController,
                maxLength: 5,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'e.g. TFN',
                  counterText: '',
                ),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      await provider.setCategory(
        project.id,
        ProjectCategory(
          color: selectedColor,
          tint: selectedTint,
          code: codeController.text.trim().toUpperCase(),
        ),
      );
    }
  }
}
