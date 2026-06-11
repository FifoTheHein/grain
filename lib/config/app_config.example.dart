// Template for the required (gitignored) app config.
//
// Setup:
//   1. Copy this file to lib/config/app_config.dart
//   2. Fill in your own values below
//
// Never commit lib/config/app_config.dart — it contains your credentials.

import '../models/time_entry.dart';

class AppConfig {
  // Harvest personal access token — create one at https://id.getharvest.com/developers
  static const String defaultToken = 'YOUR_HARVEST_TOKEN';

  // Harvest account ID — shown next to the token on the developers page
  static const String defaultAccountId = 'YOUR_ACCOUNT_ID';

  // Your numeric Harvest user ID — GET https://api.harvestapp.com/v2/users/me
  static const int userId = 0;

  // Identifies the app to the Harvest API (any "Name (email)" string)
  static const String userAgent = 'YourName (your@email.com)';

  // Harvest API root — leave as is
  static const String baseUrl = 'https://api.harvestapp.com/v2';

  // Azure DevOps project URLs to pre-load on first run. Optional — leave the
  // list empty if you don't use ADO; instances can also be added at runtime
  // in Settings. Only the project base URL is needed (no /_workitems suffix).
  static const List<AdoInstance> defaultAdoInstances = [
    // AdoInstance(
    //   label: 'My Project',
    //   baseUrl: 'https://dev.azure.com/my-org/My%20Project',
    // ),
  ];
}
