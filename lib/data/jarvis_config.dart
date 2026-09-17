import 'package:minimalauncher/variables/strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Server address and credentials needed to reach the OpenJarvis API
/// through the Cloudflare Access-protected tunnel (see #6 and #19 on the
/// jarvis-hub wayfinder map).
class JarvisConfig {
  final String serverUrl;
  final String apiKey;
  final String cfAccessClientId;
  final String cfAccessClientSecret;

  const JarvisConfig({
    required this.serverUrl,
    required this.apiKey,
    required this.cfAccessClientId,
    required this.cfAccessClientSecret,
  });

  bool get isComplete =>
      serverUrl.isNotEmpty &&
      apiKey.isNotEmpty &&
      cfAccessClientId.isNotEmpty &&
      cfAccessClientSecret.isNotEmpty;

  Uri get chatCompletionsUri {
    final base = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    return Uri.parse('$base/v1/chat/completions');
  }

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'CF-Access-Client-Id': cfAccessClientId,
        'CF-Access-Client-Secret': cfAccessClientSecret,
        'Authorization': 'Bearer $apiKey',
      };

  static Future<JarvisConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return JarvisConfig(
      serverUrl: prefs.getString(prefsJarvisServerUrl) ?? '',
      apiKey: prefs.getString(prefsJarvisApiKey) ?? '',
      cfAccessClientId: prefs.getString(prefsJarvisCfAccessClientId) ?? '',
      cfAccessClientSecret:
          prefs.getString(prefsJarvisCfAccessClientSecret) ?? '',
    );
  }

  static Future<void> save(JarvisConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsJarvisServerUrl, config.serverUrl);
    await prefs.setString(prefsJarvisApiKey, config.apiKey);
    await prefs.setString(
        prefsJarvisCfAccessClientId, config.cfAccessClientId);
    await prefs.setString(
        prefsJarvisCfAccessClientSecret, config.cfAccessClientSecret);
  }
}
