import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_local_datasource.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  const SettingsRepositoryImpl(this._datasource);

  final SettingsLocalDatasource _datasource;

  @override
  AppSettings load() {
    return AppSettings(
      confidenceThreshold:
          _datasource.getConfidenceThreshold() ??
          AppSettings.defaults.confidenceThreshold,
      iouThreshold:
          _datasource.getIouThreshold() ?? AppSettings.defaults.iouThreshold,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    await _datasource.setConfidenceThreshold(settings.confidenceThreshold);
    await _datasource.setIouThreshold(settings.iouThreshold);
  }
}