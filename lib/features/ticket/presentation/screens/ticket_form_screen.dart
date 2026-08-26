import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_router.dart';
import '../../../detection/presentation/providers/detection_providers.dart';
import '../../../detection/presentation/providers/detection_state_provider.dart';
import '../../domain/entities/ticket_info.dart';
import '../providers/ticket_providers.dart';

/// The app's entry screen: collects the scan header before the camera opens.
///
/// More fields are expected here. To add one, add a controller (or a piece of
/// local state), a [_LabeledField] / [_LabeledDropdown] row, and a line in
/// [_continue] — plus the matching field on [TicketInfo] and a setter on
/// `TicketNotifier`.
class TicketFormScreen extends ConsumerStatefulWidget {
  const TicketFormScreen({super.key});

  @override
  ConsumerState<TicketFormScreen> createState() => _TicketFormScreenState();
}

class _TicketFormScreenState extends ConsumerState<TicketFormScreen> {
  late final TextEditingController _ticketNumber;
  String? _category;

  @override
  void initState() {
    super.initState();
    // Seeded from the provider so returning here after a send (or to fix a
    // typo) shows what was already entered.
    final ticket = ref.read(ticketProvider);
    _ticketNumber = TextEditingController(text: ticket.ticketNumber);
    _category = ticket.category;
  }

  @override
  void dispose() {
    _ticketNumber.dispose();
    super.dispose();
  }

  bool get _canContinue =>
      _ticketNumber.text.trim().isNotEmpty && _category != null;

  void _continue() {
    final notifier = ref.read(ticketProvider.notifier);
    notifier.setTicketNumber(_ticketNumber.text);
    notifier.setCategory(_category!);
    // The detection state is app-scoped and outlives this screen, so a
    // previous capture would otherwise still be sitting in review when the
    // camera opens for this new ticket.
    ref.read(detectionStateProvider.notifier).reset();
    Navigator.of(context).pushNamed(AppRoutes.camera);
  }

  @override
  Widget build(BuildContext context) {
    // Warm the ONNX session while the user fills the form, so Continue
    // usually lands on a ready camera instead of a spinner. The result is
    // handled on the camera screen; watching it here only starts the load.
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
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            _LabeledDropdown(
              label: 'Category',
              value: _category,
              hint: 'Select a category',
              options: ticketCategories,
              onChanged: (value) => setState(() => _category = value),
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

/// The dropdown counterpart to [_LabeledField], matching its framing.
class _LabeledDropdown extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              hint: hint == null ? null : Text(hint!),
              items: [
                for (final option in options)
                  DropdownMenuItem<String>(
                    value: option,
                    child: Text(option),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
