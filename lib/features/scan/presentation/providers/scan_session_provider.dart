import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../detection/domain/entities/label_count.dart';
import '../../../detection/presentation/providers/detection_providers.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../data/shot_preprocessor.dart';
import '../../domain/entities/captured_shot.dart';

class ScanSessionState {
  const ScanSessionState({
    this.shots = const <CapturedShot>[],
    this.labels = const <String>[],
  });

  final List<CapturedShot> shots;
  final List<String> labels;

  int get shotCount => shots.length;

  /// Shots still queued or mid-inference. Drives the capture screen's
  /// "processing N" indicator.
  int get outstanding => shots.where((s) => !s.isSettled).length;

  bool get isIdle => outstanding == 0;

  bool get hasFailures => shots.any((s) => s.status == ShotStatus.failed);

  /// Running per-class totals across every shot. A plain sum: each photo is
  /// treated as an independent section, so framing the same labels twice
  /// counts them twice.
  List<LabelCount> get globalCounts {
    final names = labels.isEmpty ? AppConstants.fallbackClassNames : labels;
    final detected = <int, int>{};
    final current = <int, int>{};
    for (final shot in shots) {
      for (final row in shot.counts) {
        detected[row.classId] = (detected[row.classId] ?? 0) + row.detected;
        current[row.classId] = (current[row.classId] ?? 0) + row.count;
      }
    }
    return <LabelCount>[
      for (var i = 0; i < names.length; i++)
        LabelCount(
          classId: i,
          label: names[i],
          detected: detected[i] ?? 0,
          count: current[i] ?? 0,
        ),
    ];
  }

  int get globalTotal =>
      shots.fold<int>(0, (sum, shot) => sum + shot.total);

  ScanSessionState copyWith({
    List<CapturedShot>? shots,
    List<String>? labels,
  }) {
    return ScanSessionState(
      shots: shots ?? this.shots,
      labels: labels ?? this.labels,
    );
  }
}

/// Owns a scan run: photos on disk, a strictly serialized inference queue,
/// and the per-shot and global counts.
class ScanSessionNotifier extends StateNotifier<ScanSessionState> {
  ScanSessionNotifier(this._ref) : super(const ScanSessionState());

  final Ref _ref;

  /// Only ever one inference in flight. The ONNX session is not reentrant,
  /// and running several at once would thrash the accelerator and stall the
  /// preview rather than finishing any sooner.
  bool _draining = false;

  Future<Directory> _shotDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/${AppConstants.scanShotsDirName}');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Persists the photo and queues it. Returns as soon as the file is on
  /// disk so the operator can take the next shot immediately.
  Future<void> addShot(Uint8List bytes) async {
    final dir = await _shotDir();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final file = File('${dir.path}/$id.jpg');
    await file.writeAsBytes(bytes, flush: true);

    state = state.copyWith(
      shots: <CapturedShot>[
        ...state.shots,
        CapturedShot(id: id, path: file.path, index: state.shots.length + 1),
      ],
    );
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      // Resolving the model also yields the class names, and guarantees the
      // session is ready before the first shot is processed.
      final labels = await _ref.read(modelLoaderProvider.future);
      if (!mounted) return;
      if (state.labels.isEmpty) {
        state = state.copyWith(labels: labels);
      }

      while (mounted) {
        final next = _nextPending();
        if (next == null) break;
        await _process(next, labels);
      }
    } catch (e) {
      // A failure to load the model marks everything outstanding as failed
      // rather than leaving shots stuck on "pending" forever.
      if (mounted) {
        state = state.copyWith(
          shots: <CapturedShot>[
            for (final shot in state.shots)
              shot.isSettled
                  ? shot
                  : shot.copyWith(
                      status: ShotStatus.failed,
                      error: e.toString(),
                    ),
          ],
        );
      }
    } finally {
      _draining = false;
    }
  }

  CapturedShot? _nextPending() {
    for (final shot in state.shots) {
      if (shot.status == ShotStatus.pending) return shot;
    }
    return null;
  }

  Future<void> _process(CapturedShot shot, List<String> labels) async {
    _replace(shot.id, (s) => s.copyWith(status: ShotStatus.processing));
    try {
      final engine = _ref.read(detectionEngineProvider);
      final settings = _ref.read(settingsNotifierProvider);
      final bytes = await File(shot.path).readAsBytes();

      // Decode + letterbox + tensor pack off the UI isolate, so the preview
      // keeps rendering while this runs.
      final pre = await compute(
        preprocessShot,
        ShotPreprocessArgs(bytes: bytes, inputSize: engine.inputSize),
      );

      final frame = await engine.runInferenceOnTensor(
        inputData: pre.inputData,
        scale: pre.scale,
        padX: pre.padX,
        padY: pre.padY,
        originalWidth: pre.originalWidth,
        originalHeight: pre.originalHeight,
        confidenceThreshold: settings.confidenceThreshold,
        iouThreshold: settings.iouThreshold,
      );

      _replace(
        shot.id,
        (s) => s.copyWith(
          status: ShotStatus.done,
          frame: frame,
          counts: seedLabelCounts(frame, labels),
        ),
      );
    } catch (e) {
      _replace(
        shot.id,
        (s) => s.copyWith(status: ShotStatus.failed, error: e.toString()),
      );
    }
  }

  void _replace(String id, CapturedShot Function(CapturedShot) update) {
    if (!mounted) return;
    state = state.copyWith(
      shots: <CapturedShot>[
        for (final shot in state.shots)
          if (shot.id == id) update(shot) else shot,
      ],
    );
  }

  /// Adjusts one class on one shot. [delta] of -1 clamps at zero.
  void adjustCount(String shotId, int classId, int delta) {
    _replace(
      shotId,
      (shot) => shot.copyWith(
        counts: <LabelCount>[
          for (final row in shot.counts)
            if (row.classId == classId)
              row.copyWith(count: (row.count + delta).clamp(0, 9999).toInt())
            else
              row,
        ],
      ),
    );
  }

  /// Drops a shot from the run and deletes its file — for a mis-framed or
  /// accidental capture.
  Future<void> removeShot(String id) async {
    CapturedShot? shot;
    for (final s in state.shots) {
      if (s.id == id) shot = s;
    }
    state = state.copyWith(
      shots: <CapturedShot>[
        for (final s in state.shots)
          if (s.id != id) s,
      ],
    );
    if (shot != null) {
      try {
        await File(shot.path).delete();
      } catch (_) {
        // Best effort — a leftover file is harmless.
      }
    }
  }

  /// Clears the run and removes every photo from disk. Called when a new
  /// scan starts and after a submission.
  Future<void> reset() async {
    final paths = state.shots.map((s) => s.path).toList();
    state = const ScanSessionState();
    for (final path in paths) {
      try {
        await File(path).delete();
      } catch (_) {
        // Best effort.
      }
    }
  }
}

final scanSessionProvider =
    StateNotifierProvider<ScanSessionNotifier, ScanSessionState>((ref) {
      return ScanSessionNotifier(ref);
    });
