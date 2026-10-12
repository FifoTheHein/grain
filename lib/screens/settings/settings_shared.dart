import 'package:flutter/material.dart';
import '../../theme/harvest_tokens.dart';

/// A titled block inside a settings page, with an optional trailing action
/// (usually an "Add" button).
class SettingsSectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const SettingsSectionHeader({super.key, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
        ),
        ?action,
      ],
    );
  }
}

/// The gap and rule between two sections on one settings page.
class SettingsSectionDivider extends StatelessWidget {
  const SettingsSectionDivider({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 24, bottom: 8),
        child: Divider(),
      );
}

/// Muted explanatory text under a control.
class SettingsHint extends StatelessWidget {
  final String text;
  const SettingsHint(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}

/// A settings page body: padded, scrollable, stretched to the column width.
class SettingsPageBody extends StatelessWidget {
  final List<Widget> children;
  const SettingsPageBody({super.key, required this.children});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}
