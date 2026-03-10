import 'package:shared_preferences/shared_preferences.dart';

class LaunchStateStore {
  static const String _hasLaunchedKey = 'ulinq.sdk.has_launched';

  Future<bool> markLaunchedAndCheckIfFirst() async {
    final prefs = await SharedPreferences.getInstance();
    final hasLaunched = prefs.getBool(_hasLaunchedKey) ?? false;
    if (!hasLaunched) {
      await prefs.setBool(_hasLaunchedKey, true);
    }
    return !hasLaunched;
  }

  Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final hasLaunched = prefs.getBool(_hasLaunchedKey) ?? false;
    return !hasLaunched;
  }
}
