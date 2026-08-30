import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../config/app_theme.dart';
import '../utils/responsive.dart';

/// "Enhance with AI" button that rewrites [controller]'s text through
/// [enhance] (e.g. [AIService.enhanceProviderBio]). Right-aligned so it
/// reads as attached to the bottom-right of its field; disabled while
/// running or when the field is empty.
class AiEnhanceButton extends StatefulWidget {
  final TextEditingController controller;
  final Future<String?> Function(String text) enhance;
  final String? failedMessage;

  const AiEnhanceButton({
    super.key,
    required this.controller,
    required this.enhance,
    this.failedMessage,
  });

  @override
  State<AiEnhanceButton> createState() => _AiEnhanceButtonState();
}

class _AiEnhanceButtonState extends State<AiEnhanceButton> {
  bool _enhancing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant AiEnhanceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {}); // refresh the enabled state
  }

  Future<void> _run() async {
    final original = widget.controller.text.trim();
    if (original.isEmpty || _enhancing) return;
    setState(() => _enhancing = true);
    try {
      final enhanced = await widget.enhance(original);
      if (enhanced == null || enhanced.trim().isEmpty) {
        throw Exception('empty response');
      }
      widget.controller.text = enhanced.trim();
    } catch (_) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(
            title: Text(
              widget.failedMessage ?? 'Couldn\'t enhance right now — try again',
            ),
          ),
        );
      }
    }
    if (mounted) setState(() => _enhancing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ShadButton.outline(
        size: ShadButtonSize.sm,
        onPressed: _enhancing || widget.controller.text.trim().isEmpty
            ? null
            : _run,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.sparkles,
              size: context.ri(14),
              color: AppTheme.accent,
            ),
            SizedBox(width: context.rw(6)),
            Text(_enhancing ? 'Enhancing…' : 'Enhance with AI'),
          ],
        ),
      ),
    );
  }
}
