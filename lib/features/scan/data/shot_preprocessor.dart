import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../../core/utils/image_utils.dart';

/// Input to [preprocessShot], bundled into one object because `compute()`
/// only forwards a single argument to its isolate entry point.
class ShotPreprocessArgs {
  const ShotPreprocessArgs({required this.bytes, required this.inputSize});

  final Uint8List bytes;
  final int inputSize;
}

/// Output of [preprocessShot]: the model-ready tensor plus the letterbox
/// scalars needed to map detections back to the original photo. Deliberately
/// omits the padded image itself — isolate messages are copied, and it is
/// dead weight once the tensor exists.
class ShotPreprocessResult {
  const ShotPreprocessResult({
    required this.inputData,
    required this.scale,
    required this.padX,
    required this.padY,
    required this.originalWidth,
    required this.originalHeight,
  });

  final Float32List inputData;
  final double scale;
  final int padX;
  final int padY;
  final int originalWidth;
  final int originalHeight;
}

/// JPEG bytes -> model input tensor (decode, letterbox, NCHW float32 pack),
/// as one pure function so the scan queue can dispatch it onto a background
/// isolate via `compute()`.
///
/// This is the CPU-heavy part of processing a shot. Run on the UI isolate it
/// stalls Flutter's frame scheduling for its whole duration, which would make
/// the camera preview stutter every time a photo finished — the operator is
/// still shooting while earlier shots are being processed, so keeping the
/// preview smooth matters here.
ShotPreprocessResult preprocessShot(ShotPreprocessArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) {
    throw const FormatException('Could not decode the captured photo.');
  }
  final letterboxed = letterboxResize(decoded, args.inputSize);
  return ShotPreprocessResult(
    inputData: imageToNchwFloat32(letterboxed.image),
    scale: letterboxed.scale,
    padX: letterboxed.padX,
    padY: letterboxed.padY,
    originalWidth: letterboxed.originalWidth,
    originalHeight: letterboxed.originalHeight,
  );
}
