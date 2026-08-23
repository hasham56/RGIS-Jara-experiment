import 'detection_result.dart';

/// One editable row in the post-capture count editor: what the model found
/// for a class, and what the user says the real number is.
///
/// [detected] is the model's raw tally and never changes; [count] starts equal
/// to it and is what the +/- buttons move. Keeping both lets the UI show that
/// a number was hand-corrected, and lets a future Send payload report the
/// model's figure alongside the human's.
class LabelCount {
  const LabelCount({
    required this.classId,
    required this.label,
    required this.detected,
    required this.count,
  });

  /// Index into the label list — the same id the engine emits.
  final int classId;

  /// Raw class name as it appears in `labels.txt` (e.g. `price_label`).
  final String label;

  /// How many boxes the model produced for this class.
  final int detected;

  /// The current, possibly user-corrected, count.
  final int count;

  bool get isEdited => count != detected;

  /// `price_label` -> `Price label`, for display only. The raw [label] stays
  /// the key in anything machine-readable.
  String get displayName {
    final spaced = label.replaceAll('_', ' ');
    if (spaced.isEmpty) return spaced;
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  LabelCount copyWith({int? count}) {
    return LabelCount(
      classId: classId,
      label: label,
      detected: detected,
      count: count ?? this.count,
    );
  }
}

/// Builds one row per known class, in `labels.txt` order, filled in with the
/// tallies from [frame].
///
/// Rows come from [labels], never from the detections, so a class the model
/// found nothing for still gets a row showing 0 for the user to correct
/// upward. Counting keys on `classId` rather than `Detection.label` because
/// the label is derived from the id inside the engine (with a `class_N`
/// fallback) and can degrade, while the id cannot.
List<LabelCount> seedLabelCounts(DetectionFrame? frame, List<String> labels) {
  final tallies = <int, int>{};
  if (frame != null) {
    for (final detection in frame.detections) {
      tallies[detection.classId] = (tallies[detection.classId] ?? 0) + 1;
    }
  }

  return <LabelCount>[
    for (var i = 0; i < labels.length; i++)
      LabelCount(
        classId: i,
        label: labels[i],
        detected: tallies[i] ?? 0,
        count: tallies[i] ?? 0,
      ),
  ];
}
