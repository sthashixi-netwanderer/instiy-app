import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../services/report_service.dart';
import '../../utils/responsive.dart';

class ReportScreen extends StatefulWidget {
  final String reportedUserId;
  final String reportedUserName;
  final String? conversationId;

  const ReportScreen({
    super.key,
    required this.reportedUserId,
    required this.reportedUserName,
    this.conversationId,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String? _selectedCategory;
  final _descriptionCtrl = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _descriptionCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _selectedCategory != null &&
      (_selectedCategory != 'other' || _descriptionCtrl.text.trim().isNotEmpty);

  Future<void> _submit() async {
    if (_selectedCategory == null) {
      ShadToaster.of(context).show(
        const ShadToast(
          title: Text('Select a reason'),
          description: Text('Please choose a category for your report.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ReportService.submitReport(
        reportedUserId: widget.reportedUserId,
        category: _selectedCategory!,
        description: _descriptionCtrl.text,
        conversationId: widget.conversationId,
      );

      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(
            title: Text('Report submitted'),
            description: Text(
              'Our team will review your report. Thank you for helping keep Instiy safe.',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Error'),
            description: Text('Failed to submit report: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: Text('Report ${widget.reportedUserName}'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          context.rw(16),
          MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(16),
          context.rw(16),
          context.rh(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Why are you reporting this user?',
              style: TextStyle(
                fontSize: context.rsp(18),
                fontWeight: FontWeight.bold,
                color: AppTheme.charcoalInk,
              ),
            ),
            SizedBox(height: context.rh(4)),
            Text(
              'Select the reason that best describes the issue.',
              style: TextStyle(
                fontSize: context.rsp(13),
                color: AppTheme.mutedSteel,
              ),
            ),
            SizedBox(height: context.rh(20)),
            ...ReportService.categories.values.map(
              (cat) => _CategoryTile(
                category: cat,
                isSelected: _selectedCategory == cat.id,
                onTap: () => setState(() => _selectedCategory = cat.id),
              ),
            ),
            SizedBox(height: context.rh(24)),
            Text(
              'Additional details${_selectedCategory == 'other' ? ' (required)' : ' (optional)'}',
              style: TextStyle(
                fontSize: context.rsp(14),
                fontWeight: FontWeight.w600,
                color: _selectedCategory == 'other'
                    ? AppTheme.destructive
                    : AppTheme.charcoalInk,
              ),
            ),
            SizedBox(height: context.rh(8)),
            ShadInput(
              controller: _descriptionCtrl,
              placeholder: Text(
                _selectedCategory == 'other'
                    ? 'Please describe the issue...'
                    : 'Provide more context about the issue...',
              ),
              maxLines: 4,
            ),
            if (_selectedCategory == 'other' &&
                _descriptionCtrl.text.trim().isEmpty)
              Padding(
                padding: EdgeInsets.only(top: context.rh(4)),
                child: Text(
                  'You must provide details when selecting Other.',
                  style: TextStyle(
                    fontSize: context.rsp(12),
                    color: AppTheme.destructive,
                  ),
                ),
              ),
            SizedBox(height: context.rh(32)),
            SizedBox(
              width: double.infinity,
              child: ShadButton(
                enabled: _canSubmit,
                onPressed: (_isSubmitting || !_canSubmit) ? null : _submit,
                child: _isSubmitting
                    ? SizedBox(
                        width: context.rw(18),
                        height: context.rh(18),
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit Report'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final ReportCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  IconData _getIcon(String name) {
    switch (name) {
      case 'mail':
        return LucideIcons.mail;
      case 'alertTriangle':
        return LucideIcons.alertTriangle;
      case 'circleAlert':
        return LucideIcons.circleAlert;
      case 'eye':
        return LucideIcons.eye;
      case 'user':
        return LucideIcons.user;
      case 'messageSquare':
        return LucideIcons.messageSquare;
      case 'flame':
        return LucideIcons.flame;
      case 'shield':
        return LucideIcons.shield;
      case 'ellipsis':
        return LucideIcons.ellipsis;
      default:
        return LucideIcons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.rh(8)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(context.rr(12)),
          child: Container(
            padding: context.rAll(14),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.accent.withValues(alpha: 0.06)
                  : AppTheme.pureSurface,
              borderRadius: BorderRadius.circular(context.rr(12)),
              border: Border.all(
                color: isSelected ? AppTheme.accent : AppTheme.whisperBorder,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: context.rAll(10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.accent.withValues(alpha: 0.12)
                        : AppTheme.warmMist,
                    borderRadius: BorderRadius.circular(context.rr(10)),
                  ),
                  child: Icon(
                    _getIcon(category.icon),
                    size: context.ri(20),
                    color: isSelected ? AppTheme.accent : AppTheme.mutedSteel,
                  ),
                ),
                SizedBox(width: context.rw(14)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? AppTheme.accent
                              : AppTheme.charcoalInk,
                        ),
                      ),
                      SizedBox(height: context.rh(2)),
                      Text(
                        category.description,
                        style: TextStyle(
                          fontSize: context.rsp(12),
                          color: AppTheme.mutedSteel,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(
                    LucideIcons.checkCircle,
                    size: context.ri(20),
                    color: AppTheme.accent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
