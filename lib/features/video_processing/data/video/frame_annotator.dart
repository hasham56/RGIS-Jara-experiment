import 'package:image/image.dart' as img;

import '../../../../core/theme/label_colors.dart';
import '../../../live_tracking/data/tracking/box_smoother.dart';

final _labelTextColor = img.ColorRgb8(0, 0, 0);

/// Per-class box colours, matching the on-screen overlay so an exported video
/// is colour-coded the same way as a live capture. Cached because this runs
/// once per box per frame across a whole clip.
final _boxColorCache = <int, img.ColorRgb8>{};

img.ColorRgb8 _boxColorFor(int classId) {
  return _boxColorCache.putIfAbsent(classId, () {
    final rgb = LabelColors.rgbForClassId(classId);
    return img.ColorRgb8(rgb[0], rgb[1], rgb[2]);
  });
}

/// Burns each [DrawableTrack] onto [frame] in place (mutates and returns
/// it, mirroring `package:image`'s own drawing functions) — a box outline
/// plus an `id:N label conf%` label.
///
/// Uses `package:image`'s own [img.drawRect]/[img.drawString] rather than
/// a Flutter `Canvas`/`CustomPainter`: this runs inside a plain
/// `Future`-based loop with no widget tree, `BuildContext`, or
/// `RenderObject` nearby (see `VideoBatchRepositoryImpl`) — a
/// `CustomPainter` has nothing to attach to here.
img.Image annotateFrame({
  required img.Image frame,
  required List<DrawableTrack> drawables,
  required Map<int, int> displayIds,
  required Map<int, String> labelNames,
}) {
  for (final d in drawables) {
    final x1 = d.box.left.round().clamp(0, frame.width - 1);
    final y1 = d.box.top.round().clamp(0, frame.height - 1);
    final x2 = d.box.right.round().clamp(0, frame.width - 1);
    final y2 = d.box.bottom.round().clamp(0, frame.height - 1);
    final boxColor = _boxColorFor(d.classId);
    img.drawRect(frame, x1: x1, y1: y1, x2: x2, y2: y2, color: boxColor, thickness: 3);

    final displayId = displayIds[d.canonicalId] ?? 0;
    final label = labelNames[d.classId] ?? 'class_${d.classId}';
    final text = 'id:$displayId $label ${(d.confidence * 100).toStringAsFixed(0)}%';
    final labelTop = (y1 - 18).clamp(0, frame.height - 18);
    img.fillRect(
      frame,
      x1: x1,
      y1: labelTop,
      x2: (x1 + text.length * 9 + 6).clamp(0, frame.width - 1),
      y2: labelTop + 18,
      color: boxColor,
    );
    img.drawString(
      frame,
      text,
      font: img.arial14,
      x: x1 + 3,
      y: labelTop + 2,
      color: _labelTextColor,
    );
  }
  return frame;
}
