import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../data/datasources/model_asset_datasource.dart';
import '../../data/engines/detection_engine.dart';
import '../../data/engines/onnx_detection_engine.dart';
import '../../data/repositories/detection_repository_impl.dart';
import '../../domain/repositories/detection_repository.dart';
import '../../domain/usecases/run_detection_usecase.dart';

/// The active inference backend. This is the one line you'd change to swap
/// in `TFLiteDetectionEngine` once it's implemented.
final detectionEngineProvider = Provider<DetectionEngine>((ref) {
  final engine = OnnxDetectionEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

final modelAssetDatasourceProvider = Provider<ModelAssetDatasource>((ref) {
  return const ModelAssetDatasource();
});

final detectionRepositoryProvider = Provider<DetectionRepository>((ref) {
  return DetectionRepositoryImpl(
    engine: ref.watch(detectionEngineProvider),
    datasource: ref.watch(modelAssetDatasourceProvider),
  );
});

final runDetectionUseCaseProvider = Provider<RunDetectionUseCase>((ref) {
  return RunDetectionUseCase(ref.watch(detectionRepositoryProvider));
});

/// Loads the model once and resolves to its class names. The UI watches this
/// to gate the camera screen on readiness and surface load errors (e.g.
/// missing asset files).
///
/// Returning the labels (rather than `void`) means the post-capture count
/// editor can seed one row per class synchronously — by the time a capture is
/// possible this provider has necessarily resolved. Falls back to
/// [AppConstants.fallbackClassNames] only if `labels.txt` yields nothing.
final modelLoaderProvider = FutureProvider<List<String>>((ref) async {
  final repository = ref.watch(detectionRepositoryProvider);
  await repository.loadModel();
  final labels = await ref.watch(modelAssetDatasourceProvider).loadLabels();
  return labels.isEmpty ? AppConstants.fallbackClassNames : labels;
});