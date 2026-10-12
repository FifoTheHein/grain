import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/harvest_tokens.dart';

/// `Grain 1.2.5 (build 8)`, or without the build when there is none.
String formatAppVersion(String version, String buildNumber) {
  final v = version.trim();
  final b = buildNumber.trim();
  if (v.isEmpty) return 'Grain';
  return b.isEmpty ? 'Grain $v' : 'Grain $v (build $b)';
}

/// The installed version, read from the platform: the Android package, or the
/// web build's `version.json`. Both come from pubspec.yaml at build time, so
/// this can't drift from what was released. Renders nothing until it loads,
/// or at all if it can't.
class AppVersionLabel extends StatefulWidget {
  const AppVersionLabel({super.key});

  @override
  State<AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<AppVersionLabel> {
  // Held across rebuilds so the list doesn't refetch every time it repaints.
  // package_info_plus caches the platform call itself, so a new list asking
  // again is cheap.
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            formatAppVersion(info.version, info.buildNumber),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: palette.text3),
          ),
        );
      },
    );
  }
}
