import 'dart:async';
import 'dart:math' as math;

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

  /// Guards the capture path, which spans an autofocus settle delay before
  /// the shutter — `isTakingPicture` does not cover that window.
  bool _capturing = false;

  /// True while the Send placeholder is running.
  bool _sending = false;

  /// Whether the counts/confidence tray under a reviewed capture is open.
  /// Starts shut so the photo gets the full screen.
  bool _panelOpen = false;

  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  /// Where the user last tapped to focus, in normalised (0..1) preview
  /// coordinates. Re-applied just before the shutter fires.
  Offset? _focusPoint;

  /// Pan/zoom state for inspecting a reviewed capture.
  final TransformationController _reviewZoom = TransformationController();

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
      // Rebuild as part of clearing it so no frame can paint a CameraPreview
      // over a controller that is being torn down.
      final previous = _controller;
      if (previous != null) {
        setState(() => _controller = null);
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
      await _readZoomRange(controller);
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

  Future<void> _readZoomRange(CameraController controller) async {
    try {
      final min = await controller.getMinZoomLevel();
      final max = await controller.getMaxZoomLevel();
      // Devices can report very large digital-zoom maxima; past a few x the
      // image is too degraded to detect anything, so cap what we offer.
      _minZoom = min;
      _maxZoom = math.min(max, AppConstants.previewMaxZoom);
      _zoom = _minZoom;
      await controller.setZoomLevel(_minZoom);
    } on CameraException {
      _minZoom = 1.0;
      _maxZoom = 1.0;
      _zoom = 1.0;
    }
  }

  Future<void> _setZoom(double value) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() => _zoom = value);
    try {
      await controller.setZoomLevel(value);
    } on CameraException {
      // Out-of-range on some devices; the slider is already clamped.
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
    _reviewZoom.dispose();
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
      _reviewZoom.value = Matrix4.identity();
      _panelOpen = false;
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

  void _retake() {
    _reviewZoom.value = Matrix4.identity();
    _panelOpen = false;
    ref.read(detectionStateProvider.notifier).reset();
  }

  /// Placeholder for the upload flow: shows a progress state, then returns to
  /// the ticket form. Nothing is transmitted yet.
  ///
  /// When implemented this will post the ticket number and category
  /// (`ticketProvider`), the user-corrected counts
  /// (`DetectionUiState.countsPayload`) and the annotated capture, which can
  /// be rasterised from [_captureBoundaryKey].
  Future<void> _send(DetectionFrame frame) async {
    if (_sending) return;
    setState(() => _sending = true);
    // TODO(rgis): replace this delay with the real upload.
    await Future<void>.delayed(AppConstants.sendSimulationDelay);
    if (!mounted) return;
    setState(() => _sending = false);
    _reviewZoom.value = Matrix4.identity();
    _panelOpen = false;
    ref.read(detectionStateProvider.notifier).reset();
    // Back to the ticket form, which is the first route. Its fields are still
    // populated — the screen stays alive underneath this one, and it also
    // re-seeds from `ticketProvider` if it is ever rebuilt.
    Navigator.of(context).popUntil((route) => route.isFirst);
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
            onPressed: () async {
              await Navigator.of(context).pushNamed(AppRoutes.settings);
              if (!mounted) return;
              // The thresholds are applied during inference, so a capture
              // already under review would otherwise keep showing boxes from
              // the old values until it was re-shot.
              await ref
                  .read(detectionStateProvider.notifier)
                  .reprocessIfThresholdsChanged();
            },
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
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_maxZoom > _minZoom) _buildZoomSlider(),
                    const SizedBox(height: 12),
                    CaptureButton(onPressed: _capture),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildZoomSlider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          const Icon(Icons.zoom_out, color: Colors.white, size: 20),
          Expanded(
            child: Slider(
              value: _zoom.clamp(_minZoom, _maxZoom).toDouble(),
              min: _minZoom,
              max: _maxZoom,
              onChanged: _setZoom,
            ),
          ),
          const Icon(Icons.zoom_in, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              '${_zoom.toStringAsFixed(1)}x',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// The always-visible bar between the capture and the action buttons.
  /// Doubles as the collapsed summary, so the headline total stays on screen
  /// even when the tray is shut.
  Widget _buildPanelHandle(DetectionUiState state) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => setState(() => _panelOpen = !_panelOpen),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${state.editedTotal} label(s)'
                '${state.countsEdited ? ' (adjusted)' : ''}',
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              _panelOpen ? 'Hide' : 'Adjust',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            Icon(
              _panelOpen
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_up,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  /// Live drag: store the value only. Inference is far too costly to re-run
  /// on every tick of the slider.
  void _onConfidenceChanged(double value) {
    ref.read(settingsNotifierProvider.notifier).setConfidenceThreshold(value);
  }

  /// Drag finished — now it is worth re-running detection on the capture
  /// still under review so the new threshold is reflected immediately.
  Future<void> _onConfidenceSettled(double value) async {
    await ref
        .read(settingsNotifierProvider.notifier)
        .setConfidenceThreshold(value);
    if (!mounted) return;
    await ref
        .read(detectionStateProvider.notifier)
        .reprocessIfThresholdsChanged();
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

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              // The zoomable viewport is the WHOLE available area, with the
              // aspect-ratio'd photo centred inside it — not the other way
              // round. Nesting it the other way clipped zoom/pan to the
              // photo's own letterboxed column, so the screen's left and
              // right margins stayed unused no matter how far you zoomed.
              child: GestureDetector(
                onDoubleTap: () => _reviewZoom.value = Matrix4.identity(),
                child: InteractiveViewer(
                  transformationController: _reviewZoom,
                  minScale: 1.0,
                  maxScale: AppConstants.reviewMaxZoom,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: (frame != null && frame.imageHeight > 0)
                          ? frame.imageWidth / frame.imageHeight
                          : 1,
                      // The boxes live in the same subtree as the photo, so
                      // they scale with it; the RepaintBoundary sits below
                      // the transform, so a future Send still rasterises the
                      // canonical unzoomed frame.
                      child: RepaintBoundary(
                        key: _captureBoundaryKey,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              state.imageBytes!,
                              fit: BoxFit.contain,
                              // Keep detail crisp when magnified rather than
                              // smoothing the label text away.
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
                ),
              ),
            ),
            if (state.isProcessing) const LinearProgressIndicator(),
            if (state.labelCounts.isNotEmpty) ...[
              _buildPanelHandle(state),
              // Collapsed by default so the capture gets the full screen;
              // the handle above still shows the headline total.
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _panelOpen
                    ? ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: panelMaxHeight),
                        child: LabelCountsPanel(
                          labelCounts: state.labelCounts,
                          frame: frame,
                          onIncrement: notifier.increment,
                          onDecrement: notifier.decrement,
                          confidence: settings.confidenceThreshold,
                          onConfidenceChanged: _onConfidenceChanged,
                          onConfidenceSettled: _onConfidenceSettled,
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
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
                        onPressed: _sending ? null : _retake,
                        child: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: (frame == null || _sending)
                            ? null
                            : () => _send(frame),
                        child: const Text('Send'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_sending)
          const Positioned.fill(child: _SendingOverlay()),
      ],
    );
  }
}

/// Blocking progress state shown while Send runs.
class _SendingOverlay extends StatelessWidget {
  const _SendingOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              'Sending…',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
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
