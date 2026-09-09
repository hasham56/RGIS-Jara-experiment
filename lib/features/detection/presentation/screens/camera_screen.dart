import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/label_colors.dart';
import '../../../scan/presentation/providers/scan_session_provider.dart';
import '../providers/detection_providers.dart';
import '../widgets/capture_button.dart';

/// Continuous capture for a scan run: the preview stays up, every tap adds a
/// photo, and detection happens in the background while the operator keeps
/// shooting. Counts are reviewed and corrected afterwards, per photo, on the
/// scan review screen.
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

  /// Where the user last tapped to focus, in normalised (0..1) preview
  /// coordinates. Re-applied just before the shutter fires.
  Offset? _focusPoint;

  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

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
      // Clear any error from a previous attempt so Retry can actually recover.
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
      // Without this these were swallowed: the future went to a FutureBuilder
      // that never read its snapshot, so failures showed as a spinner that
      // never resolved.
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

  /// Continuous AF metered on the centre, plus tap-to-focus on the preview.
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
    // the camera down for those killed the preview for a momentary glance,
    // so only a real background triggers teardown.
    if (appState == AppLifecycleState.paused ||
        appState == AppLifecycleState.hidden ||
        appState == AppLifecycleState.detached) {
      _teardownCamera();
    } else if (appState == AppLifecycleState.resumed) {
      // Re-acquire when there is no controller. Guarding on
      // `_controller != null` here while the teardown branch nulled it made
      // this path unreachable, leaving the camera dead until force-quit.
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
    setState(() => _capturing = true);
    try {
      // Trigger AF and let it converge before the shutter — otherwise the
      // photo is taken mid-hunt and comes out soft.
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
      // Hands off to the queue and returns — detection happens in the
      // background so the operator can keep shooting.
      await ref.read(scanSessionProvider.notifier).addShot(bytes);
    } on CameraException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture failed (${e.code}).')),
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelState = ref.watch(modelLoaderProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture'),
        actions: [
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
        data: (_) => _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_permissionError != null) {
      return _ErrorPane(
        message: _permissionError!,
        primaryLabel: 'Open app settings',
        onPrimary: openAppSettings,
        onRetry: () => setState(() => _initializeFuture = _initCamera()),
      );
    }

    if (_cameraError != null) {
      return _ErrorPane(
        message: _cameraError!,
        onRetry: () => setState(() => _initializeFuture = _initCamera()),
      );
    }

    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        final controller = _controller;
        if (controller == null || !controller.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        // CameraController.value.aspectRatio is always reported in the
        // sensor's landscape orientation (width > height), regardless of the
        // device's current orientation. Inverting it in portrait makes the
        // preview fill the available space correctly.
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
              top: 8,
              left: 0,
              right: 0,
              child: SafeArea(bottom: false, child: _buildRunningTally()),
            ),
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_maxZoom > _minZoom) _buildZoomSlider(),
                    const SizedBox(height: 8),
                    _buildShutterRow(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Running per-class totals across every photo taken so far, plus how many
  /// are still being processed.
  Widget _buildRunningTally() {
    final session = ref.watch(scanSessionProvider);
    if (session.shotCount == 0) {
      return const _TallyCard(
        child: Text(
          'Tap the shutter for each shelf section',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return _TallyCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final row in session.globalCounts) ...[
                _ClassPill(classId: row.classId, count: row.count),
                const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${session.shotCount} photo(s) · ${session.globalTotal} labels',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              if (session.outstanding > 0) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'processing ${session.outstanding}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShutterRow() {
    final session = ref.watch(scanSessionProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        const SizedBox(width: 72),
        CaptureButton(onPressed: _capture),
        SizedBox(
          width: 72,
          child: session.shotCount == 0
              ? const SizedBox.shrink()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      onPressed: () => Navigator.of(context)
                          .pushNamed(AppRoutes.scanReview),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: const Text('Review'),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${session.shotCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
        ),
      ],
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
}

/// Dark rounded container used for the overlays on top of the preview.
class _TallyCard extends StatelessWidget {
  const _TallyCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

/// `S 12` in the class's own colour, matching the boxes drawn on review.
class _ClassPill extends StatelessWidget {
  const _ClassPill({required this.classId, required this.count});

  final int classId;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = LabelColors.forClassId(classId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
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
