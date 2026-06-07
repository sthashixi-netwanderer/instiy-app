import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_theme.dart';
import '../../services/report_service.dart';
import '../../utils/responsive.dart';

class ProductReportScreen extends StatefulWidget {
  final String productId;
  final String productTitle;
  final String sellerId;

  const ProductReportScreen({
    super.key,
    required this.productId,
    required this.productTitle,
    required this.sellerId,
  });

  @override
  State<ProductReportScreen> createState() => _ProductReportScreenState();
}

class _ProductReportScreenState extends State<ProductReportScreen> {
  String? _selectedCategory;
  final _descriptionCtrl = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

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
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final userData = await Supabase.instance.client
          .from('users')
          .select('full_name, email')
          .eq('id', user.id)
          .single();

      await ReportService.submitProductReport(
        productId: widget.productId,
        reportedUserId: widget.sellerId,
        category: _selectedCategory!,
        description: _descriptionCtrl.text,
        productTitle: widget.productTitle,
        reporterEmail: userData['email'] as String,
        reporterName: (userData['full_name'] as String?) ?? 'User',
      );

      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(
            title: Text('Report submitted'),
            description: Text(
              'Thank you for your report. We\'ll review it and notify you of the outcome.',
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
      backgroundColor: AppTheme.canvasWhite,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Report Listing'),
      ),
      body: SingleChildScrollView(
        padding: context.rAll(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product reference
            Container(
              padding: context.rAll(14),
              decoration: BoxDecoration(
                color: AppTheme.warmMist,
                borderRadius: BorderRadius.circular(context.rr(12)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.package, size: context.ri(20), color: AppTheme.mutedSteel),
                  SizedBox(width: context.rw(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reporting',
                          style: TextStyle(fontSize: context.rsp(11), color: AppTheme.mutedSteel),
                        ),
                        SizedBox(height: context.rh(2)),
                        Text(
                          widget.productTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: context.rsp(14),
                            color: AppTheme.charcoalInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: context.rh(24)),
            Text(
              'What\'s wrong with this listing?',
              style: TextStyle(
                fontSize: context.rsp(18),
                fontWeight: FontWeight.bold,
                color: AppTheme.charcoalInk,
              ),
            ),
            SizedBox(height: context.rh(4)),
            Text(
              'Select the reason that best describes the issue.',
              style: TextStyle(fontSize: context.rsp(13), color: AppTheme.mutedSteel),
            ),
            SizedBox(height: context.rh(20)),
            ...ReportService.productCategories.values.map((cat) => _CategoryTile(
              category: cat,
              isSelected: _selectedCategory == cat.id,
              onTap: () => setState(() => _selectedCategory = cat.id),
            )),
            SizedBox(height: context.rh(24)),
            Text(
              'Additional details (optional)',
              style: TextStyle(
                fontSize: context.rsp(14),
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
            SizedBox(height: context.rh(8)),
            ShadInput(
              controller: _descriptionCtrl,
              placeholder: const Text('Provide more context about the issue...'),
              maxLines: 4,
            ),
            SizedBox(height: context.rh(32)),
            SizedBox(
              width: double.infinity,
              child: ShadButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? SizedBox(
                        width: context.rw(18),
                        height: context.rh(18),
                        child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
      case 'shieldOff': return LucideIcons.shieldOff;
      case 'eyeOff': return LucideIcons.eyeOff;
      case 'ban': return LucideIcons.ban;
      case 'circleAlert': return LucideIcons.circleAlert;
      case 'eye': return LucideIcons.eye;
      case 'lock': return LucideIcons.lock;
      case 'trendingUp': return LucideIcons.trendingUp;
      case 'ellipsis': return LucideIcons.ellipsis;
      default: return LucideIcons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context;
    return Padding(
      padding: EdgeInsets.only(bottom: responsive.rh(8)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(responsive.rr(12)),
          child: Container(
            padding: responsive.rAll(14),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.accent.withValues(alpha: 0.06) : AppTheme.pureSurface,
              borderRadius: BorderRadius.circular(responsive.rr(12)),
              border: Border.all(
                color: isSelected ? AppTheme.accent : AppTheme.whisperBorder,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: responsive.rAll(10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.accent.withValues(alpha: 0.12)
                        : AppTheme.warmMist,
                    borderRadius: BorderRadius.circular(responsive.rr(10)),
                  ),
                  child: Icon(
                    _getIcon(category.icon),
                    size: responsive.ri(20),
                    color: isSelected ? AppTheme.accent : AppTheme.mutedSteel,
                  ),
                ),
                SizedBox(width: responsive.rw(14)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: responsive.rsp(14),
                          color: isSelected ? AppTheme.accent : AppTheme.charcoalInk,
                        ),
                      ),
                      SizedBox(height: responsive.rh(2)),
                      Text(
                        category.description,
                        style: TextStyle(fontSize: responsive.rsp(12), color: AppTheme.mutedSteel),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(LucideIcons.checkCircle, size: responsive.ri(20), color: AppTheme.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
