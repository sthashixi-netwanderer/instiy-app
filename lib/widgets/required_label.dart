import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Form label with a trailing red asterisk marking the field as required.
/// Use for every required field label so the convention stays consistent
/// across screens; optional fields stay unmarked.
class RequiredLabel extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const RequiredLabel(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: text,
        children: [
          TextSpan(
            text: ' *',
            style: TextStyle(
              color: AppTheme.destructive,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      style: style,
    );
  }
}
