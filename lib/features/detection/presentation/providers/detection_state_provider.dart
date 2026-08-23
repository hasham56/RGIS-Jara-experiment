import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../domain/entities/detection_result.dart';
import '../../domain/entities/label_count.dart';
import 'detection_providers.dart';

/// UI-facing state for the capture → detect → review flow on the camera
/// screen. `null` fields mean "no capture yet" (still showing the live
/// preview).
class DetectionUiState {
  const DetectionUiState({
    this.imageBytes,
    this.frame,
    this.isProcessing = false,
    this.error,
    this.labelCounts = const <LabelCount>[],
  });

  final Uint8List? imageBytes;
  final DetectionFrame? frame;
  final bool isProcessing;
  final String? error;

  /// One row per class, seeded from [frame] when the capture completes and
  /// then owned by the user's +/- edits. Empty until a capture is processed.
  final List<LabelCount> labelCounts;

  /// The user-facing total — the sum of the (possibly corrected) counts, not
  /// `frame.detections.length`.
  int get editedTotal =>
      labelCounts.fold<int>(0, (sum, row) => sum + row.count);

  /// True once any row has been nudged away from what the model reported.
  bool get countsEdited => labelCounts.any((row) => row.isEdited);

  /// Machine-readable payload for the eventual Send implementation, keyed by
  /// the raw label from `labels.txt`.
  Map<String, int> get countsPayload => <String, int>{
    for (final row in labelCounts) row.label: row.count,
  };

  DetectionUiState copyWith({
    Uint8List? imageBytes,
    DetectionFrame? frame,
    bool? isProcessing,
    String? error,
    bool clearError = false,
    List<LabelCount>? labelCounts,
  }) {
    return DetectionUiState(
      imageBytes: imageBytes ?? this.imageBytes,
      frame: frame ?? this.frame,
      isProcessing: isProcessing ?? this.isProcessing,
      error: clearError ? null : (error ?? this.error),
      labelCounts: labelCounts ?? this.labelCounts,
    );
  }
}

class DetectionNotifier extends StateNotifier<DetectionUiState> {
  DetectionNotifier(this._ref) : super(const DetectionUiState());

  final Ref _ref;

  /// Thresholds the current result was produced with, so a settings change
  /// can be detected without re-running inference needlessly.
  double? _lastConfidence;
  double? _lastIou;

  Future<void> processCapture(Uint8List imageBytes) async {
    state = DetectionUiState(imageBytes: imageBytes, isProcessing: true);
    try {
      final useCase = _ref.read(runDetectionUseCaseProvider);
      final settings = _ref.read(settingsNotifierProvider);
      _lastConfidence = settings.confidenceThreshold;
      _lastIou = settings.iouThreshold;
      final frame = await useCase(
        imageBytes,
        confidenceThreshold: settings.confidenceThreshold,
        iouThreshold: settings.iouThreshold,
      );
      // Seed the editable counts here — exactly once, as part of this state
      // transition. Deriving them in `build` (or re-seeding whenever the list
      // looks empty) would wipe the user's +/- edits on the next rebuild.
      state = state.copyWith(
        frame: frame,
        isProcessing: false,
        labelCounts: seedLabelCounts(frame, _labels()),
      );
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
    }
  }

  /// Re-runs detection on the capture already under review when the
  /// confidence or NMS thresholds have changed since it was produced.
  ///
  /// The thresholds are applied during inference, so a photo already on
  /// screen would otherwise keep showing boxes from the old values until the
  /// user re-shot it. Re-running is cheap enough for a single still and keeps
  /// both thresholds honest (filtering client-side would only fix
  /// confidence, not the NMS IoU). The counts re-seed as a result — the set
  /// of detections genuinely changed, so any manual +/- edits no longer
  /// describe what is on screen.
  Future<void> reprocessIfThresholdsChanged() async {
    final imageBytes = state.imageBytes;
    if (imageBytes == null || state.isProcessing) return;
    final settings = _ref.read(settingsNotifierProvider);
    if (settings.confidenceThreshold == _lastConfidence &&
        settings.iouThreshold == _lastIou) {
      return;
    }
    await processCapture(imageBytes);
  }

  /// Class names from the loaded model, or the bundled fallback if the loader
  /// has not resolved (it always has by the time a capture is possible).
  List<String> _labels() {
    return _ref.read(modelLoaderProvider).maybeWhen(
      data: (labels) => labels,
      orElse: () => AppConstants.fallbackClassNames,
    );
  }

  /// Bumps one class's count. [delta] of -1 clamps at zero.
  void adjustCount(int classId, int delta) {
    state = state.copyWith(
      labelCounts: <LabelCount>[
        for (final row in state.labelCounts)
          if (row.classId == classId)
            row.copyWith(count: (row.count + delta).clamp(0, 9999).toInt())
          else
            row,
      ],
    );
  }

  void increment(int classId) => adjustCount(classId, 1);

  void decrement(int classId) => adjustCount(classId, -1);

  /// Discards the current capture/result and returns to the live preview.
  /// `labelCounts` defaults to empty, so Retake clears the edits too.
  void reset() {
    state = const DetectionUiState();
  }
}

final detectionStateProvider =
    StateNotifierProvider<DetectionNotifier, DetectionUiState>((ref) {
      return DetectionNotifier(ref);
    });