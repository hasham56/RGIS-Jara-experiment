/// Selectable values for [TicketInfo.category]. Order is the order shown in
/// the dropdown.
const List<String> ticketCategories = <String>[
  'Ambient',
  'Freezers',
  'Frozen',
  'Stationary',
  'Books',
  'Breads',
  'Back Asile',
];

/// Header data collected before a scan starts, carried alongside the counts
/// when the capture is eventually sent.
///
/// To add another field (more are expected): add it here, add it to
/// [copyWith], add a setter on `TicketNotifier`, and add one row to
/// `TicketFormScreen`. Extend [isComplete] only if the new field is required.
class TicketInfo {
  const TicketInfo({this.ticketNumber = '', this.category});

  final String ticketNumber;

  /// One of [ticketCategories], or null until the user picks one.
  final String? category;

  /// Whether the form has enough to proceed to the camera.
  bool get isComplete => ticketNumber.isNotEmpty && category != null;

  TicketInfo copyWith({String? ticketNumber, String? category}) {
    return TicketInfo(
      ticketNumber: ticketNumber ?? this.ticketNumber,
      category: category ?? this.category,
    );
  }
}
