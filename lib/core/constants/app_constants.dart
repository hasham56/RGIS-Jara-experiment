/// App-wide constants: asset locations and detector defaults.
class AppConstants {
  AppConstants._();

  static const String appName = 'RGIS Detector';

  // Model assets. Drop your exported files at these exact paths.
  static const String modelAssetPath = 'assets/models/model.onnx';
  static const String labelsAssetPath = 'assets/models/labels.txt';

  /// Square input side the model was exported with (`yolo export imgsz=640`).
  static const int modelInputSize = 640;

  static const double defaultConfidenceThreshold = 0.5;
  static const double defaultIouThreshold = 0.45;

  static const String capturesDirName = 'captures';
  static const String capturesIndexFileName = 'captures_index.json';

  static const String prefsConfidenceKey = 'settings.confidenceThreshold';
  static const String prefsIouKey = 'settings.iouThreshold';
}