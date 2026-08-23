import 'package:flutter/material.dart';

/// One colour per detection class, shared by the box overlay, the count
/// editor and the video annotator so a box on a frame and its row in the
/// tally read as the same thing.
///
/// Indexed by `classId`, i.e. the order in `labels.txt`
/// (small, medium, large, price_label). Hues are deliberately far apart
/// rather than a size ramp — on a dense shelf photo, telling the categories
/// apart at a glance matters more than implying an ordering. All four are
/// bright enough to take black label text on top.
///
/// Stored as raw RGB triples because the video path draws with
/// `package:image`, which has its own colour type and cannot take a Flutter
/// [Color].
class LabelColors {
  LabelColors._();

  static const List<List<int>> rgbPalette = <List<int>>[
    <int>[0x00, 0xE5, 0xFF], // small       — cyan
    <int>[0xC6, 0xFF, 0x00], // medium      — lime
    <int>[0xFF, 0x91, 0x00], // large       — orange
    <int>[0xE0, 0x40, 0xFB], // price_label — magenta
  ];

  /// `[r, g, b]` for a class id, wrapping if a model ever ships more classes
  /// than the palette has entries.
  static List<int> rgbForClassId(int classId) {
    if (rgbPalette.isEmpty) return const <int>[0x00, 0xE6, 0x76];
    final index = classId % rgbPalette.length;
    return rgbPalette[index < 0 ? index + rgbPalette.length : index];
  }

  /// Flutter colour for a class id.
  static Color forClassId(int classId) {
    final rgb = rgbForClassId(classId);
    return Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
  }
}
