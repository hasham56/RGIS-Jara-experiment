import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_router.dart';
import '../../../detection/presentation/providers/detection_providers.dart';
import '../../../detection/presentation/providers/detection_state_provider.dart';
import '../providers/ticket_providers.dart';

/// The app's entry screen: collects the scan header before the camera opens.
///
/// More fields are expected here. To add one, add a controller, a
/// [_LabeledField] row, and a line in [_continue] — plus the matching field
/// on `TicketInfo` and a setter on `TicketNotifier`.
class TicketFormScreen extends ConsumerStatefulWidget {
  const TicketFormScreen({super.key});

  @override
  ConsumerState<TicketFormScreen> createState() => _TicketFormScreenState();
}

class _TicketFormScreenState extends ConsumerState<TicketFormScreen> {
  late final TextEditingController _ticketNumber;

  @override
  void initState() {
    super.initState();
    // Seeded so returning to the form to fix a typo shows what was entered.
    _ticketNumber = TextEditingController(
      text: ref.read(ticketProvider).ticketNumber,
    );
  }

  @override
  void dispose() {
    _ticketNumber.dispose();
    super.dispose();
  }

  bool get _canContinue => _ticketNumber.text.trim().isNotEmpty;

  void _continue() {
    ref.read(ticketProvider.notifier).setTicketNumber(_ticketNumber.text);
    // The detection state is app-scoped and outlives this screen, so a
    // previous capture would otherwise still be sitting in review when the
    // camera opens for this new ticket.
    ref.read(detectionStateProvider.notifier).reset();
    Navigator.of(context).pushNamed(AppRoutes.camera);
  }

  @override
  Widget build(BuildContext context) {
    // Warm the ONNX session while the user types, so Continue usually lands
    // on a ready camera instead of a spinner. The result is handled on the
    // camera screen; watching it here only starts the load early.
    ref.watch(modelLoaderProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppConstants.appName)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _LabeledField(
              label: 'RGIS Ticket Number',
              controller: _ticketNumber,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_canContinue) _continue();
              },
            ),

            // Add further fields here.
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _canContinue ? _continue : null,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A label above a text input — the same "label, then control" idiom the
/// settings screen uses.
class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ],
    );
  }
}
