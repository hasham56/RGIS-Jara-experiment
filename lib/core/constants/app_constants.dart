/// App-wide constants: asset locations and detector defaults.
class AppConstants {
  AppConstants._();

  static const String appName = 'RGIS Detector';

  // Model assets. Drop your exported files at these exact paths.
  static const String modelAssetPath = 'assets/models/model.onnx';
  static const String labelsAssetPath = 'assets/models/labels.txt';

  /// Square input side the bundled model was exported with
  /// (`yolo export imgsz=960` — model.onnx declares `[1, 3, 960, 960]`).
  static const int modelInputSize = 960;

  static const double defaultConfidenceThreshold = 0.5;
  static const double defaultIouThreshold = 0.45;

  /// Class names used only if `labels.txt` cannot be read. `labels.txt`
  /// remains the source of truth — this exists so the count editor can still
  /// render its rows if the asset load fails. Order must match training
  /// (index == classId).
  static const List<String> fallbackClassNames = <String>[
    'small',
    'medium',
    'large',
    'price_label',
  ];

  /// How long to let one-shot autofocus converge before firing the shutter.
  /// The capture path triggers AF, waits this long, then takes the picture —
  /// without it the photo is taken mid-hunt and comes out soft.
  static const Duration autofocusSettleDelay = Duration(milliseconds: 450);

  /// How long the Send button shows its progress state before returning to
  /// the camera. Stands in for the real upload, which is not wired up yet.
  static const Duration sendSimulationDelay = Duration(milliseconds: 750);

  /// Upper bound for pinch-zoom on a reviewed capture. Enough to inspect a
  /// single shelf label and read which category it was boxed as.
  static const double reviewMaxZoom = 8.0;

  /// Ceiling for the live preview's zoom slider. Devices can report much
  /// higher (digital) maxima that are useless for label detection.
  static const double previewMaxZoom = 8.0;

  static const String capturesDirName = 'captures';
  static const String capturesIndexFileName = 'captures_index.json';

  static const String prefsConfidenceKey = 'settings.confidenceThreshold';
  static const String prefsIouKey = 'settings.iouThreshold';
  static const String prefsShowLabelsKey = 'settings.showLabels';
  static const String prefsMinimizeLabelsKey = 'settings.minimizeLabels';
  static const String prefsShowConfidenceKey = 'settings.showConfidence';
}