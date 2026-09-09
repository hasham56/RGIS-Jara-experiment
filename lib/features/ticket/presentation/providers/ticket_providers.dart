import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/ticket_info.dart';

/// Holds the scan header entered on the form so the detection flow — and the
/// eventual Send — can read it. Session-scoped only; nothing is persisted
/// yet, so there is no repository/datasource layer under this.
class TicketNotifier extends StateNotifier<TicketInfo> {
  TicketNotifier() : super(const TicketInfo());

  void setTicketNumber(String value) {
    state = state.copyWith(ticketNumber: value.trim());
  }

  void setBay(String value) {
    state = state.copyWith(bay: value.trim());
  }

  void setCategory(String value) {
    state = state.copyWith(category: value);
  }

  void clear() {
    state = const TicketInfo();
  }
}

final ticketProvider = StateNotifierProvider<TicketNotifier, TicketInfo>((ref) {
  return TicketNotifier();
});
