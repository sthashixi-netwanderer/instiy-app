import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import '../utils/responsive.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onActionPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: context.rPadding(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: context.rAll(20),
              decoration: BoxDecoration(
                color: AppTheme.warmMist,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: context.ri(40),
                color: AppTheme.mutedSteel,
              ),
            ),
            SizedBox(height: context.rh(20)),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: context.rsp(18),
                fontWeight: FontWeight.bold,
                color: AppTheme.charcoalInk,
              ),
            ),
            SizedBox(height: context.rh(8)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.rw(16)),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: context.rsp(14),
                  color: AppTheme.mutedSteel,
                  height: 1.4,
                ),
              ),
            ),
            if (actionLabel != null && onActionPressed != null) ...[
              SizedBox(height: context.rh(24)),
              ShadButton(
                onPressed: onActionPressed,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
