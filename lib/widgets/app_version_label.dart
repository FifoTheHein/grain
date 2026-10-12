import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/harvest_tokens.dart';

/// `Grain 1.2.5 (build 8)`, or without the build when there is none.
///
/// On [android] the build is the APK's versionCode, which
/// `flutter build apk --split-per-abi` offsets by 1000 per processor type
/// (arm64-v8a's build 8 installs as 2008), so the thousands are dropped to
/// show the pubspec's build number. A universal APK has no offset, and the web
/// reads the pubspec's number from version.json untouched.
String formatAppVersion(String version, String buildNumber,
    {bool android = false}) {
  final v = version.trim();
  var b = buildNumber.trim();
  if (v.isEmpty) return 'Grain';
  final code = int.tryParse(b);
  if (android && code != null) b = '${code % 1000}';
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
            formatAppVersion(info.version, info.buildNumber,
                android: !kIsWeb &&
                    defaultTargetPlatform == TargetPlatform.android),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: palette.text3),
          ),
        );
      },
    );
  }
}
