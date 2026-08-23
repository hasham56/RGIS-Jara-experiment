import 'package:flutter/material.dart';

import '../../domain/entities/detection_result.dart';
import '../../domain/entities/label_count.dart';
import 'fps_indicator.dart';
import 'label_counter_row.dart';

/// The editable tally under the reviewed capture: a header with the running
/// total, then one +/- row per class.
///
/// Scrolls internally so it can be given a bounded height by the caller — the
/// captured image above it must stay outside any scrollable, because the save
/// path resolves its `RepaintBoundary` through a `GlobalKey` and a lazily
/// unmounted boundary cannot be rasterised.
class LabelCountsPanel extends StatelessWidget {
  const LabelCountsPanel({
    super.key,
    required this.labelCounts,
    required this.total,
    required this.edited,
    required this.onIncrement,
    required this.onDecrement,
    this.frame,
  });

  final List<LabelCount> labelCounts;
  final int total;
  final bool edited;
  final void Function(int classId) onIncrement;
  final void Function(int classId) onDecrement;
  final DetectionFrame? frame;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$total label(s)${edited ? ' (adjusted)' : ''}',
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (frame != null) FpsIndicator(frame: frame!),
          ],
        ),
        const Divider(height: 12),
        for (final row in labelCounts)
          LabelCounterRow(
            labelCount: row,
            onIncrement: () => onIncrement(row.classId),
            onDecrement: () => onDecrement(row.classId),
          ),
      ],
    );
  }
}
