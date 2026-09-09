import '../../../detection/domain/entities/detection_result.dart';
import '../../../detection/domain/entities/label_count.dart';

enum ShotStatus { pending, processing, done, failed }

/// One photo taken during a scan run.
///
/// The JPEG itself lives on disk at [path] and is never held in memory — a
/// bay can run to a couple of hundred shots, and decoded frames at capture
/// resolution would exhaust memory long before that.
class CapturedShot {
  const CapturedShot({
    required this.id,
    required this.path,
    required this.index,
    this.status = ShotStatus.pending,
    this.frame,
    this.counts = const <LabelCount>[],
    this.error,
  });

  final String id;
  final String path;

  /// 1-based position in the run, for display ("Photo 3 of 12").
  final int index;

  final ShotStatus status;
  final DetectionFrame? frame;

  /// Per-class counts for this shot: seeded from [frame], then owned by the
  /// operator's +/- edits.
  final List<LabelCount> counts;

  final String? error;

  bool get isSettled =>
      status == ShotStatus.done || status == ShotStatus.failed;

  int get total => counts.fold<int>(0, (sum, row) => sum + row.count);

  bool get edited => counts.any((row) => row.isEdited);

  CapturedShot copyWith({
    ShotStatus? status,
    DetectionFrame? frame,
    List<LabelCount>? counts,
    String? error,
  }) {
    return CapturedShot(
      id: id,
      path: path,
      index: index,
      status: status ?? this.status,
      frame: frame ?? this.frame,
      counts: counts ?? this.counts,
      error: error ?? this.error,
    );
  }
}
