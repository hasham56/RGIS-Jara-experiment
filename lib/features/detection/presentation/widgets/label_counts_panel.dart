import 'package:flutter/material.dart';

import '../../domain/entities/detection_result.dart';
import '../../domain/entities/label_count.dart';
import 'fps_indicator.dart';
import 'label_counter_row.dart';

/// The expandable tray under a reviewed capture: one +/- row per class, plus
/// a confidence slider so the threshold can be tuned without leaving the
/// review.
///
/// Scrolls internally so the caller can cap its height — the captured image
/// above it must stay outside any scrollable, because the save path resolves
/// its `RepaintBoundary` through a `GlobalKey` and a lazily unmounted
/// boundary cannot be rasterised.
class LabelCountsPanel extends StatelessWidget {
  const LabelCountsPanel({
    super.key,
    required this.labelCounts,
    required this.onIncrement,
    required this.onDecrement,
    required this.confidence,
    required this.onConfidenceChanged,
    required this.onConfidenceSettled,
    this.frame,
  });

  final List<LabelCount> labelCounts;
  final void Function(int classId) onIncrement;
  final void Function(int classId) onDecrement;

  /// Current confidence threshold (0..1), mirroring the Settings screen.
  final double confidence;

  /// Fires continuously while dragging — update the stored value only.
  final ValueChanged<double> onConfidenceChanged;

  /// Fires once when the drag ends — the point at which it is worth re-running
  /// detection, since inference is far too costly to run per slider tick.
  final ValueChanged<double> onConfidenceSettled;

  final DetectionFrame? frame;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        for (final row in labelCounts)
          LabelCounterRow(
            labelCount: row,
            onIncrement: () => onIncrement(row.classId),
            onDecrement: () => onDecrement(row.classId),
          ),
        const Divider(height: 16),
        Row(
          children: [
            Text('Confidence', style: theme.textTheme.bodyMedium),
            Expanded(
              child: Slider(
                value: confidence.clamp(0.05, 0.95).toDouble(),
                min: 0.05,
                max: 0.95,
                divisions: 18,
                label: confidence.toStringAsFixed(2),
                onChanged: onConfidenceChanged,
                onChangeEnd: onConfidenceSettled,
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${(confidence * 100).round()}%',
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        if (frame != null)
          Align(
            alignment: Alignment.centerLeft,
            child: FpsIndicator(frame: frame!),
          ),
      ],
    );
  }
}
