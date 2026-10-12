import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';
import '../../providers/assignment_provider.dart';
import '../../providers/time_entry_provider.dart';
import '../../theme/harvest_tokens.dart';
import 'settings_shared.dart';

/// Harvest credentials and the background refresh.
///
/// The credentials are the one thing in Settings that does not save as you
/// type: a half-typed token would fail every request, so they wait for
/// "Save & reconnect", which also reloads projects and entries with them.
class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final _tokenController = TextEditingController();
  final _accountIdController = TextEditingController();
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _accountIdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _tokenController.text =
          prefs.getString('harvest_token') ?? AppConfig.defaultToken;
      _accountIdController.text =
          prefs.getString('harvest_account_id') ?? AppConfig.defaultAccountId;
    });
  }

  Future<void> _save(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('harvest_token', _tokenController.text.trim());
    await prefs.setString(
        'harvest_account_id', _accountIdController.text.trim());
    if (!context.mounted) return;
    context.read<AssignmentProvider>().load();
    context.read<TimeEntryProvider>().loadRecentEntries();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Credentials saved — reconnecting'),
        backgroundColor: HarvestTokens.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final entries = context.watch<TimeEntryProvider>();

    return SettingsPageBody(children: [
      const SettingsSectionHeader(title: 'Harvest Credentials'),
      const SizedBox(height: 12),
      TextField(
        controller: _tokenController,
        obscureText: _obscureToken,
        decoration: InputDecoration(
          labelText: 'API Token',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(
              _obscureToken ? Icons.visibility : Icons.visibility_off,
            ),
            onPressed: () => setState(() => _obscureToken = !_obscureToken),
          ),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _accountIdController,
        decoration: const InputDecoration(
          labelText: 'Account ID',
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
      ),
      const SettingsHint('User ID: ${AppConfig.userId}'),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () => _save(context),
        icon: const Icon(Icons.save_outlined),
        label: const Text('Save & reconnect'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: palette.brand,
        ),
      ),
      const SettingsSectionDivider(),
      const SettingsSectionHeader(title: 'Background Refresh'),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        initialValue: entries.refreshIntervalMinutes,
        decoration: const InputDecoration(
          labelText: 'Refresh interval',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: 5, child: Text('Every 5 minutes')),
          DropdownMenuItem(value: 15, child: Text('Every 15 minutes')),
          DropdownMenuItem(value: 30, child: Text('Every 30 minutes')),
          DropdownMenuItem(value: 60, child: Text('Every hour')),
        ],
        onChanged: (v) {
          if (v != null) context.read<TimeEntryProvider>().setRefreshInterval(v);
        },
      ),
      const SettingsHint(
          'Silently re-fetches the current week in the background. Calendar '
          'auto-log runs on the same refresh.'),
    ]);
  }
}
