import 'package:web/web.dart' as web;

Future<void> openUrl(String url) async {
  web.window.open(url, '_blank', 'noopener,noreferrer');
}
