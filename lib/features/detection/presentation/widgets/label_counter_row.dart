import 'package:flutter/material.dart';

import '../../domain/entities/label_count.dart';

/// One `Small  [-] 12 [+]` row in the post-capture count editor.
class LabelCounterRow extends StatelessWidget {
  const LabelCounterRow({
    super.key,
    required this.labelCount,
    required this.onIncrement,
    required this.onDecrement,
  });

  final LabelCount labelCount;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canDecrement = labelCount.count > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              labelCount.displayName,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          // Show the model's original figure once the user has overridden it,
          // so a hand-corrected number is never mistaken for a detection.
          if (labelCount.isEdited)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'was ${labelCount.detected}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          IconButton(
            onPressed: canDecrement ? onDecrement : null,
            icon: const Icon(Icons.remove_circle_outline),
            visualDensity: VisualDensity.compact,
            tooltip: 'Decrease ${labelCount.displayName}',
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${labelCount.count}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: onIncrement,
            icon: const Icon(Icons.add_circle_outline),
            visualDensity: VisualDensity.compact,
            tooltip: 'Increase ${labelCount.displayName}',
          ),
        ],
      ),
    );
  }
}
