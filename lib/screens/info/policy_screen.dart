import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../config/app_theme.dart';
import '../../services/policy_service.dart';
import '../../widgets/skeleton.dart';

class PolicyScreen extends StatefulWidget {
  final String policyType;
  final String title;

  const PolicyScreen({
    super.key,
    required this.policyType,
    required this.title,
  });

  @override
  State<PolicyScreen> createState() => _PolicyScreenState();
}

class _PolicyScreenState extends State<PolicyScreen> {
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
      if (mounted) {
        setState(() {
          _content = content;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: Text(widget.title)),
      body: _isLoading
          ? Padding(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 200, height: 20),
                  const SizedBox(height: 16),
                  const ListSkeleton(count: 8),
                ],
              ),
            )
          : _content.isEmpty
              ? const Center(
                  child: Text(
                    'No content available.',
                    style: TextStyle(color: AppTheme.mutedSteel),
                  ),
                )
              : Markdown(
                  data: _content,
                  padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 16, 16, 16),
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.charcoalInk,
                      height: 1.6,
                    ),
                    h1: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.charcoalInk,
                    ),
                    h2: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                    h3: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                    listBullet: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.charcoalInk,
                    ),
                    em: const TextStyle(
                      fontStyle: FontStyle.italic,
                      color: AppTheme.mutedSteel,
                    ),
                    blockquoteDecoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: AppTheme.accent, width: 3),
                      ),
                      color: AppTheme.accent.withValues(alpha: 0.05),
                    ),
                  ),
                ),
    );
  }
}
