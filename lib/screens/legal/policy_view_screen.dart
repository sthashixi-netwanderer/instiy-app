import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../services/policy_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/skeleton.dart';

class PolicyViewScreen extends StatefulWidget {
  final String policyType;
  final String title;

  const PolicyViewScreen({
    super.key,
    required this.policyType,
    required this.title,
  });

  @override
  State<PolicyViewScreen> createState() => _PolicyViewScreenState();
}

class _PolicyViewScreenState extends State<PolicyViewScreen> {
  String _content = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPolicy();
  }

  Future<void> _loadPolicy() async {
    try {
      final content = await PolicyService.getPolicyContent(widget.policyType);
      if (mounted) setState(() { _content = content; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      appBar: AppTheme.glassAppBar(context: context, 
        title: Text(widget.title),
        leading: ShadIconButton.ghost(
          icon: Icon(LucideIcons.arrowLeft, size: context.ri(24)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? Padding(padding: context.rAll(16), child: const ListSkeleton(count: 6))
          : _content.isEmpty
              ? const Center(
                  child: Text(
                    'No content available.',
                    style: TextStyle(color: AppTheme.mutedSteel),
                  ),
                )
              : Markdown(
                  data: _content,
                  padding: context.rAll(16),
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(fontSize: context.rsp(14), color: AppTheme.charcoalInk, height: 1.6),
                    h1: TextStyle(fontSize: context.rsp(22), fontWeight: FontWeight.bold, color: AppTheme.charcoalInk),
                    h2: TextStyle(fontSize: context.rsp(18), fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
                    h3: TextStyle(fontSize: context.rsp(16), fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
                    listBullet: TextStyle(fontSize: context.rsp(14), color: AppTheme.charcoalInk),
                    em: TextStyle(fontStyle: FontStyle.italic, color: AppTheme.mutedSteel),
                    strong: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
                    blockquoteDecoration: BoxDecoration(
                      border: Border(left: BorderSide(color: AppTheme.accent, width: 3)),
                      color: AppTheme.accent.withValues(alpha: 0.05),
                    ),
                  ),
                ),
    );
  }
}
