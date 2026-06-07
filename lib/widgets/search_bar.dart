import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import '../utils/responsive.dart';

class InstiySearchBar extends StatefulWidget {
  final ValueChanged<String> onChanged;

  const InstiySearchBar({super.key, required this.onChanged});

  @override
  State<InstiySearchBar> createState() => _InstiySearchBarState();
}

class _InstiySearchBarState extends State<InstiySearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadInput(
      controller: _controller,
      placeholder: const Text('Search products...'),
      leading: Icon(LucideIcons.search, size: context.ri(20), color: AppTheme.mutedSteel),
      trailing: _controller.text.isNotEmpty
          ? ShadIconButton.ghost(
              onPressed: () {
                _controller.clear();
                widget.onChanged('');
              },
              icon: Icon(LucideIcons.x, size: context.ri(18)),
            )
          : null,
      onChanged: widget.onChanged,
    );
  }
}
