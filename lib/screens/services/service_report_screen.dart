import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../utils/responsive.dart';
import '../../models/picked_media.dart';
import '../../services/background_submission.dart';
import '../../services/report_service.dart';
import '../../services/storage_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/image_picker_sheet.dart';

/// Report a service listing, optionally attaching up to 3 evidence images.
/// Mirrors the product report flow; evidence uploads go to R2 'reports'.
class ServiceReportScreen extends ConsumerStatefulWidget {
  final String serviceId;
  final String serviceTitle;
  final String providerId;

  const ServiceReportScreen({
    super.key,
    required this.serviceId,
    required this.serviceTitle,
    required this.providerId,
  });

  @override
  ConsumerState<ServiceReportScreen> createState() =>
      _ServiceReportScreenState();
}

class _ServiceReportScreenState extends ConsumerState<ServiceReportScreen> {
  String? _selectedCategory;
  final _descriptionCtrl = TextEditingController();
  final List<PickedMedia> _evidence = [];

  static const _maxEvidence = 3;

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _selectedCategory != null &&
      (_selectedCategory != 'other' || _descriptionCtrl.text.trim().isNotEmpty);

  Future<void> _addEvidence() async {
    if (_evidence.length >= _maxEvidence) return;
    final picked = await ImagePickerSheet.pickMultiple(context);
    if (picked.isNotEmpty) {
      // Cap at the overall limit if the user picked more than there's room for.
      setState(
        () => _evidence.addAll(
          picked.take(_maxEvidence - _evidence.length),
        ),
      );
    }
  }

  Future<void> _submit() async {
    final auth = SupabaseService.auth.currentUser;
    if (auth == null) {
      if (mounted) Navigator.of(context).pushNamed('/login');
      return;
    }

    // Capture ALL values before popping — the background submit must not
    // depend on this widget being alive.
    final serviceId = widget.serviceId;
    final reportedUserId = widget.providerId;
    final category = _selectedCategory!;
    final descriptionVal = _descriptionCtrl.text.trim().isEmpty
        ? null
        : _descriptionCtrl.text.trim();
    final serviceTitle = widget.serviceTitle;
    final evidence = List<PickedMedia>.from(_evidence);
    final reporterId = auth.id;

    ShadToaster.of(context).show(
      const ShadToast(title: Text('Sending report...')),
    );
    Navigator.of(context).pop();

    // Background submit — no widget dependency.
    BackgroundSubmission.run(
      task: () async {
        // Upload evidence images first.
        final urls = <String>[];
        for (final media in evidence) {
          final url = await StorageService.uploadImage(
            file: media,
            folder: 'reports',
          );
          urls.add(url);
        }

        // Reporter details for the confirmation email.
        final profile = await SupabaseService.table('users')
            .select('full_name, email')
            .eq('id', reporterId)
            .single();

        await ReportService.submitServiceReport(
          serviceId: serviceId,
          reportedUserId: reportedUserId,
          category: category,
          description: descriptionVal,
          evidenceUrls: urls,
          serviceTitle: serviceTitle,
          reporterEmail: profile['email'] as String,
          reporterName: profile['full_name'] as String? ?? 'Instiy user',
        );
      },
      successTitle: 'Report submitted',
      successDescription: 'Thank you — our team will review this service.',
      failureTitle: 'Failed to submit report',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Report Service')),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          context.rw(16),
          MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(16),
          context.rw(16),
          context.rh(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reporting "${widget.serviceTitle}"',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: context.rsp(15),
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
            SizedBox(height: context.rh(4)),
            Text(
              'Why are you reporting this service?',
              style: TextStyle(
                fontSize: context.rsp(13),
                color: AppTheme.mutedSteel,
              ),
            ),
            SizedBox(height: context.rh(16)),
            ...ReportService.serviceCategories.values.map(
              (category) => _CategoryTile(
                category: category,
                selected: _selectedCategory == category.id,
                onTap: () => setState(() => _selectedCategory = category.id),
              ),
            ),
            SizedBox(height: context.rh(16)),
            Text(
              'Additional details',
              style: TextStyle(
                fontSize: context.rsp(14),
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
            SizedBox(height: context.rh(4)),
            Text(
              _selectedCategory == 'other'
                  ? 'Required — tell us what\'s wrong'
                  : 'Optional — anything that helps us review faster',
              style: TextStyle(
                fontSize: context.rsp(12),
                color: AppTheme.mutedSteel,
              ),
            ),
            SizedBox(height: context.rh(8)),
            ShadInput(
              controller: _descriptionCtrl,
              placeholder: const Text('Describe the issue...'),
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              onChanged: (_) => setState(() {}),
            ),
            SizedBox(height: context.rh(16)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Evidence photos (${_evidence.length}/$_maxEvidence)',
                  style: TextStyle(
                    fontSize: context.rsp(14),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                if (_evidence.length < _maxEvidence)
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: _addEvidence,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.plus, size: 14),
                        SizedBox(width: 4),
                        Text('Add'),
                      ],
                    ),
                  ),
              ],
            ),
            SizedBox(height: context.rh(4)),
            Text(
              'Optional — screenshots that show the problem',
              style: TextStyle(
                fontSize: context.rsp(12),
                color: AppTheme.mutedSteel,
              ),
            ),
            SizedBox(height: context.rh(8)),
            if (_evidence.isEmpty)
              GestureDetector(
                onTap: _addEvidence,
                child: Container(
                  width: double.infinity,
                  padding: context.rAll(18),
                  decoration: BoxDecoration(
                    color: AppTheme.pureSurface,
                    borderRadius: BorderRadius.circular(context.rr(12)),
                    border: Border.all(color: AppTheme.whisperBorder),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        LucideIcons.imagePlus,
                        size: context.ri(24),
                        color: AppTheme.mutedSteel,
                      ),
                      SizedBox(height: context.rh(6)),
                      Text(
                        'Attach a screenshot',
                        style: TextStyle(
                          fontSize: context.rsp(13),
                          color: AppTheme.mutedSteel,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: _evidence.length,
                itemBuilder: (context, index) {
                  final media = _evidence[index];
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(context.rr(8)),
                        child: Image.memory(media.bytes, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _evidence.removeAt(index)),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              LucideIcons.x,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            SizedBox(height: context.rh(24)),
            SizedBox(
              width: double.infinity,
              child: ShadButton(
                onPressed: _canSubmit ? _submit : null,
                child: const Text(
                  'Submit Report',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
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
  final bool selected;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  IconData get _icon {
    switch (category.icon) {
      case 'file_question':
        return LucideIcons.fileQuestion;
      case 'shield_alert':
        return LucideIcons.shieldAlert;
      case 'ban':
        return LucideIcons.ban;
      case 'eye_off':
        return LucideIcons.eyeOff;
      case 'trending_up':
        return LucideIcons.trendingUp;
      default:
        return LucideIcons.helpCircle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: EdgeInsets.only(bottom: context.rh(10)),
        padding: context.rAll(14),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.08)
              : AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(12)),
          border: Border.all(
            color: selected
                ? AppTheme.accent.withValues(alpha: 0.5)
                : AppTheme.whisperBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: context.rAll(10),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.accent.withValues(alpha: 0.15)
                    : AppTheme.warmMist,
                borderRadius: BorderRadius.circular(context.rr(10)),
              ),
              child: Icon(
                _icon,
                size: context.ri(18),
                color: selected ? AppTheme.accent : AppTheme.mutedSteel,
              ),
            ),
            SizedBox(width: context.rw(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: context.rsp(14),
                      color: selected
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
            if (selected)
              Icon(
                LucideIcons.checkCircle,
                size: context.ri(20),
                color: AppTheme.accent,
              ),
          ],
        ),
      ),
    );
  }
}
