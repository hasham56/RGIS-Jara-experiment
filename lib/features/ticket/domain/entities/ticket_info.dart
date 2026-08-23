/// Header data collected before a scan starts, carried alongside the counts
/// when the capture is eventually sent.
///
/// To add another field (more are expected): add it here, add it to
/// [copyWith], add a setter on `TicketNotifier`, and add one row to
/// `TicketFormScreen`. Extend [isComplete] only if the new field is required.
class TicketInfo {
  const TicketInfo({this.ticketNumber = ''});

  final String ticketNumber;

  /// Whether the form has enough to proceed to the camera.
  bool get isComplete => ticketNumber.isNotEmpty;

  TicketInfo copyWith({String? ticketNumber}) {
    return TicketInfo(ticketNumber: ticketNumber ?? this.ticketNumber);
  }
}
