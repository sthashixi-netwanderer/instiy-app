import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../utils/responsive.dart';

/// A shared input field wrapper that ensures consistent width on desktop.
///
/// On mobile, fills the parent (same as today).
/// On tablet/desktop, caps at [maxWidth] and centers — matching the
/// AppButton width so fields and buttons look proportional.
class AppInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? id;
  final Widget? label;
  final Widget? placeholder;
  final Widget? leading;
  final Widget? trailing;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(dynamic)? validator;
  final int maxLines;
  final bool enabled;
  final double maxWidth;
  final VoidCallback? onTap;
  final bool readOnly;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  const AppInput({
    super.key,
    this.controller,
    this.id,
    this.label,
    this.placeholder,
    this.leading,
    this.trailing,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
    this.enabled = true,
    this.maxWidth = 400,
    this.onTap,
    this.readOnly = false,
    this.focusNode,
    this.onChanged,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = context.screenWidth >= 600;

    final field = ShadInputFormField(
      id: id ?? 'field_${hashCode.toRadixString(16)}',
      controller: controller,
      label: label,
      placeholder: placeholder,
      leading: leading,
      trailing: trailing,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      maxLines: maxLines,
      enabled: enabled,
      readOnly: readOnly,
      focusNode: focusNode,
      onChanged: onChanged,
      textInputAction: textInputAction,
    );

    if (!isWide) return field;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: field,
      ),
    );
  }
}
