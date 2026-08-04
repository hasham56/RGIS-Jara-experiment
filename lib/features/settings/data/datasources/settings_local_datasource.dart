import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_constants.dart';

class SettingsLocalDatasource {
  const SettingsLocalDatasource(this._prefs);

  final SharedPreferences _prefs;

  double? getConfidenceThreshold() =>
      _prefs.getDouble(AppConstants.prefsConfidenceKey);

  double? getIouThreshold() => _prefs.getDouble(AppConstants.prefsIouKey);

  Future<void> setConfidenceThreshold(double value) =>
      _prefs.setDouble(AppConstants.prefsConfidenceKey, value);

  Future<void> setIouThreshold(double value) =>
      _prefs.setDouble(AppConstants.prefsIouKey, value);
}