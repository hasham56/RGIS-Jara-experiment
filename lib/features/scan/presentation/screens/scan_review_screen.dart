import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/label_colors.dart';
import '../../../detection/domain/entities/label_count.dart';
import '../../../detection/presentation/widgets/detection_overlay_painter.dart';
import '../../../detection/presentation/widgets/label_counter_row.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../../ticket/presentation/providers/ticket_providers.dart';
import '../../domain/entities/captured_shot.dart';
import '../providers/scan_session_provider.dart';

/// Walk the run photo by photo, correct any counts, then submit.
class ScanReviewScreen extends ConsumerStatefulWidget {
  const ScanReviewScreen({super.key});

  @override
  ConsumerState<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends ConsumerState<ScanReviewScreen> {
  final PageController _pages = PageController();
  int _page = 0;
  bool _submitting = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    // TODO(rgis): replace this delay with the real upload — ticket number,
    // bay, category, per-photo counts and the photos themselves.
    await Future<void>.delayed(AppConstants.sendSimulationDelay);
    if (!mounted) return;
    setState(() => _submitting = false);
    await ref.read(scanSessionProvider.notifier).reset();
    if (!mounted) return;
    // Back to the ticket form, ready for the next bay.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _confirmDelete(CapturedShot shot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this photo?'),
        content: Text(
          'Photo ${shot.index} and its ${shot.total} label(s) will be '
          'dropped from the run.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(scanSessionProvider.notifier).removeShot(shot.id);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(scanSessionProvider);
    final ticket = ref.watch(ticketProvider);
    final shots = session.shots;

    if (shots.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review')),
        body: const Center(child: Text('No photos in this run yet.')),
      );
    }

    final safePage = _page.clamp(0, shots.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: Text('Review ${safePage + 1} of ${shots.length}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: _GlobalTally(
            counts: session.globalCounts,
            total: session.globalTotal,
            outstanding: session.outstanding,
            subtitle: 'Ticket ${ticket.ticketNumber} · Bay ${ticket.bay}'
                '${ticket.category == null ? '' : ' · ${ticket.category}'}',
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: shots.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) => _ShotPage(shot: shots[i]),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _submitting
                              ? null
                              : () => _confirmDelete(shots[safePage]),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          // Submitting mid-inference would post counts that
                          // are still incomplete.
                          onPressed: (_submitting || session.outstanding > 0)
                              ? null
                              : _submit,
                          child: Text(
                            session.outstanding > 0
                                ? 'Processing ${session.outstanding}…'
                                : 'Submit ${session.globalTotal} label(s)',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_submitting)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        'Submitting…',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One page: the photo with its boxes, and its own editable counts.
class _ShotPage extends ConsumerWidget {
  const _ShotPage({required this.shot});

  final CapturedShot shot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(scanSessionProvider.notifier);
    final frame = shot.frame;

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                minScale: 1.0,
                maxScale: AppConstants.reviewMaxZoom,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: (frame != null && frame.imageHeight > 0)
                        ? frame.imageWidth / frame.imageHeight
                        : 1,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(shot.path),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                        if (frame != null)
                          CustomPaint(
                            painter: DetectionOverlayPainter(
                              frame: frame,
                              showLabels: settings.showLabels,
                              minimizeLabels: settings.minimizeLabels,
                              showConfidence: settings.showConfidence,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!shot.isSettled)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black38,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
        if (shot.status == ShotStatus.failed)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Detection failed for this photo.\n${shot.error ?? ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        if (shot.counts.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (MediaQuery.sizeOf(context).height * 0.34)
                  .clamp(140.0, 300.0)
                  .toDouble(),
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Text(
                  'Photo ${shot.index} · ${shot.total} label(s)'
                  '${shot.edited ? ' (adjusted)' : ''}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Divider(height: 12),
                for (final row in shot.counts)
                  LabelCounterRow(
                    labelCount: row,
                    onIncrement: () =>
                        notifier.adjustCount(shot.id, row.classId, 1),
                    onDecrement: () =>
                        notifier.adjustCount(shot.id, row.classId, -1),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The run-wide totals strip pinned under the app bar.
class _GlobalTally extends StatelessWidget {
  const _GlobalTally({
    required this.counts,
    required this.total,
    required this.outstanding,
    required this.subtitle,
  });

  final List<LabelCount> counts;
  final int total;
  final int outstanding;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final row in counts) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: LabelColors.forClassId(row.classId),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text('${row.count}', style: theme.textTheme.labelLarge),
                const SizedBox(width: 12),
              ],
              Text('= $total', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            outstanding > 0 ? '$subtitle · processing $outstanding' : subtitle,
            style: theme.textTheme.labelSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
