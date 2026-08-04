import '../../../../core/constants/app_constants.dart';

class AppSettings {
  const AppSettings({
    required this.confidenceThreshold,
    required this.iouThreshold,
  });

  final double confidenceThreshold;
  final double iouThreshold;

  static const defaults = AppSettings(
    confidenceThreshold: AppConstants.defaultConfidenceThreshold,
    iouThreshold: AppConstants.defaultIouThreshold,
  );

  AppSettings copyWith({double? confidenceThreshold, double? iouThreshold}) {
    return AppSettings(
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      iouThreshold: iouThreshold ?? this.iouThreshold,
    );
  }
}