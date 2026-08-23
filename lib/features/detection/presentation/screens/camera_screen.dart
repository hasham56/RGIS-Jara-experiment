import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_router.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../domain/entities/detection_result.dart';
import '../providers/detection_providers.dart';
import '../providers/detection_state_provider.dart';
import '../widgets/capture_button.dart';
import '../widgets/detection_overlay_painter.dart';
import '../widgets/label_counts_panel.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  String? _permissionError;
  String? _cameraError;

  /// Guards against two `_initCamera()` runs overlapping — iOS can emit
  /// resume events in quick succession, and two in-flight initialisations
  /// would leave one orphaned controller holding the device.
  bool _initializing = false;

  /// Guards the capture path, which now spans an autofocus settle delay
  /// before the shutter — `isTakingPicture` does not cover that window.
  bool _capturing = false;

  /// Where the user last tapped to focus, in normalised (0..1) preview
  /// coordinates. Re-applied just before the shutter fires.
  Offset? _focusPoint;

  final GlobalKey _captureBoundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeFuture = _initCamera();
  }

  Future<void> _initCamera() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final status = await Permission.camera.request();
      if (!mounted) return;
      if (!status.isGranted) {
        setState(() {
          _permissionError =
              'Camera permission is required to use the detector.';
        });
        return;
      }
      // Clear any error from a previous attempt so Retry can actually recover
      // — the old code set `_permissionError` once and never unset it, which
      // wedged the screen until the app was force-quit.
      setState(() {
        _permissionError = null;
        _cameraError = null;
      });

      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No camera available on this device.');
        return;
      }
      final rearCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // Release anything still held before acquiring again (Retry path).
      final previous = _controller;
      if (previous != null) {
        _controller = null;
        unawaited(previous.dispose());
      }

      // veryHigh (1920x1080) rather than high (1280x720): the detector runs at
      // 960px, so a 720p still leaves it starved of detail on small labels.
      final controller = CameraController(
        rearCamera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _applyFocusDefaults(controller);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      // Previously these were swallowed: the future was handed to a
      // FutureBuilder that never read its snapshot, so any failure showed as
      // a spinner that never resolved.
      if (mounted) {
        setState(() {
          _cameraError =
              'Could not start the camera (${e.code}). ${e.description ?? ''}'
                  .trim();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cameraError = 'Could not start the camera: $e');
      }
    } finally {
      _initializing = false;
    }
  }

  /// Focus and exposure were never configured at all before, leaving whatever
  /// the platform defaulted to. Continuous AF metered on the centre is the
  /// sane default for shelf labels; the preview also supports tap-to-focus.
  /// Must be re-applied after every re-initialisation — it does not survive.
  Future<void> _applyFocusDefaults(CameraController controller) async {
    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setFocusPoint(_focusPoint ?? const Offset(0.5, 0.5));
      await controller.setExposureMode(ExposureMode.auto);
      await controller.setExposurePoint(_focusPoint ?? const Offset(0.5, 0.5));
    } on CameraException {
      // Focus/exposure control is unavailable on some devices; that must not
      // take down an otherwise working preview.
    }
  }

  Future<void> _focusAt(Offset localPosition, Size previewSize) async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        previewSize.width <= 0 ||
        previewSize.height <= 0) {
      return;
    }
    final point = Offset(
      (localPosition.dx / previewSize.width).clamp(0.0, 1.0).toDouble(),
      (localPosition.dy / previewSize.height).clamp(0.0, 1.0).toDouble(),
    );
    setState(() => _focusPoint = point);
    try {
      await controller.setFocusPoint(point);
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposurePoint(point);
    } on CameraException {
      // Ignore — tapping to focus is a convenience, not a requirement.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    // `inactive` fires for transient interruptions on iOS — Control Centre,
    // a notification banner, the app switcher, the permission dialog. Tearing
    // the camera down for those is why a two-second glance killed the preview,
    // so only a real background triggers teardown now.
    if (appState == AppLifecycleState.paused ||
        appState == AppLifecycleState.hidden ||
        appState == AppLifecycleState.detached) {
      _teardownCamera();
    } else if (appState == AppLifecycleState.resumed) {
      // Re-acquire when there is no controller. The previous version guarded
      // on `_controller != null` at the top of this method while its own
      // teardown branch nulled the field — making this path unreachable and
      // leaving the camera dead until the app was force-quit. That was the
      // "sometimes it doesn't open" bug.
      if (_controller == null && !_initializing) {
        setState(() => _initializeFuture = _initCamera());
      }
    }
  }

  void _teardownCamera() {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    // Rebuild before disposing, so CameraPreview stops pointing at a
    // controller that is about to be torn down.
    if (mounted) setState(() {});
    unawaited(controller.dispose());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    // `isTakingPicture` alone is not enough: it only goes true once
    // takePicture() is in flight, leaving the autofocus settle below as a
    // window where a second tap could start a parallel capture.
    if (_capturing ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }
    _capturing = true;
    try {
      // Trigger AF and let it converge before the shutter. Previously
      // takePicture() fired the instant the button was tapped, so captures
      // were taken mid-hunt and came out soft.
      try {
        await controller.setFocusPoint(_focusPoint ?? const Offset(0.5, 0.5));
        await controller.setFocusMode(FocusMode.auto);
        await Future<void>.delayed(AppConstants.autofocusSettleDelay);
      } on CameraException {
        // Shoot anyway if focus control is unavailable.
      }
      if (!mounted) return;

      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await ref.read(detectionStateProvider.notifier).processCapture(bytes);
    } on CameraException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture failed (${e.code}).')),
      );
    } finally {
      _capturing = false;
    }
  }

  /// Placeholder for the upload flow — deliberately does nothing for now.
  ///
  /// When implemented this will post the ticket number (`ticketProvider`),
  /// the user-corrected counts (`DetectionUiState.countsPayload`) and the
  /// annotated capture, which can be rasterised from [_captureBoundaryKey].
  void _send(DetectionFrame frame) {
    // TODO(rgis): wire up the real send.
  }

  @override
  Widget build(BuildContext context) {
    final modelState = ref.watch(modelLoaderProvider);
    final detectionState = ref.watch(detectionStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('RGIS Detector'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.gallery),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.settings),
          ),
        ],
      ),
      body: modelState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Failed to load model:\n$err',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (_) => _buildBody(detectionState),
      ),
    );
  }

  Widget _buildBody(DetectionUiState state) {
    if (_permissionError != null) {
      return _ErrorPane(
        message: _permissionError!,
        primaryLabel: 'Open app settings',
        onPrimary: openAppSettings,
        // Coming back from Settings having granted permission used to leave
        // the screen stuck; Retry gives it a way out.
        onRetry: () => setState(() => _initializeFuture = _initCamera()),
      );
    }

    if (_cameraError != null) {
      return _ErrorPane(
        message: _cameraError!,
        onRetry: () => setState(() => _initializeFuture = _initCamera()),
      );
    }

    if (state.imageBytes != null) {
      return _buildReview(state);
    }

    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        final controller = _controller;
        if (controller == null || !controller.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        // CameraController.value.aspectRatio is always reported in the
        // sensor's landscape orientation (width > height), regardless of
        // the device's current orientation. Used as-is in a portrait
        // layout it produces a short, wide box with large empty gaps above
        // and below; inverting it in portrait makes the preview fill the
        // available space correctly.
        final isPortrait =
            MediaQuery.of(context).orientation == Orientation.portrait;
        final previewAspectRatio = isPortrait
            ? 1 / controller.value.aspectRatio
            : controller.value.aspectRatio;

        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: previewAspectRatio,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) => _focusAt(
                        details.localPosition,
                        constraints.biggest,
                      ),
                      child: CameraPreview(controller),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(child: CaptureButton(onPressed: _capture)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReview(DetectionUiState state) {
    final frame = state.frame;
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(detectionStateProvider.notifier);
    // Bound the panel so four rows plus the button bar cannot push the image
    // off-screen at large text scales; it scrolls internally past that.
    final panelMaxHeight = (MediaQuery.sizeOf(context).height * 0.42)
        .clamp(140.0, 340.0)
        .toDouble();

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: (frame != null && frame.imageHeight > 0)
                  ? frame.imageWidth / frame.imageHeight
                  : 1,
              child: RepaintBoundary(
                key: _captureBoundaryKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(state.imageBytes!, fit: BoxFit.contain),
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
        ),
        if (state.isProcessing) const LinearProgressIndicator(),
        if (state.labelCounts.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: panelMaxHeight),
            child: LabelCountsPanel(
              labelCounts: state.labelCounts,
              total: state.editedTotal,
              edited: state.countsEdited,
              frame: frame,
              onIncrement: notifier.increment,
              onDecrement: notifier.decrement,
            ),
          ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              state.error!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: notifier.reset,
                    child: const Text('Retake'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: frame == null ? null : () => _send(frame),
                    child: const Text('Send'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-screen message with a retry affordance, used for both the permission
/// and the camera-failure cases.
class _ErrorPane extends StatelessWidget {
  const _ErrorPane({
    required this.message,
    required this.onRetry,
    this.primaryLabel,
    this.onPrimary,
  });

  final String message;
  final VoidCallback onRetry;
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            if (primaryLabel != null && onPrimary != null) ...[
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel!)),
              const SizedBox(height: 8),
            ],
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
