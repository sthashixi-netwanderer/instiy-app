import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../services/policy_service.dart';
import '../../utils/responsive.dart';

class AcceptPolicyScreen extends ConsumerStatefulWidget {
  const AcceptPolicyScreen({super.key});

  @override
  ConsumerState<AcceptPolicyScreen> createState() => _AcceptPolicyScreenState();
}

class _AcceptPolicyScreenState extends ConsumerState<AcceptPolicyScreen> {
  String _privacyContent = '';
  String _termsContent = '';
  bool _isLoading = true;
  bool _acceptedPrivacy = false;
  bool _acceptedTerms = false;

  @override
  void initState() {
    super.initState();
    _loadPolicies();
  }

  Future<void> _loadPolicies() async {
    try {
      final results = await Future.wait([
        PolicyService.getPolicyContent('privacy_policy'),
        PolicyService.getPolicyContent('terms_conditions'),
      ]);
      if (mounted) {
        setState(() {
          _privacyContent = results[0];
          _termsContent = results[1];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _allAccepted => _acceptedPrivacy && _acceptedTerms;

  void _handleContinue() {
    if (!_allAccepted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context,
        title: const Text('Terms & Privacy'),
        leading: ShadIconButton.ghost(
          icon: Icon(LucideIcons.arrowLeft, size: context.ri(24)),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(context.rw(16), MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(16), context.rw(16), context.rh(16)),
                    children: [
                      // Privacy Policy
                      _buildSectionHeader('Privacy Policy', LucideIcons.shield),
                      SizedBox(height: context.rh(8)),
                      _buildPolicyCard(_privacyContent),
                      SizedBox(height: context.rh(12)),
                      _buildCheckbox(
                        value: _acceptedPrivacy,
                        onChanged: (v) => setState(() => _acceptedPrivacy = v ?? false),
                        label: 'I have read and accept the Privacy Policy',
                      ),
                      SizedBox(height: context.rh(24)),

                      // Terms & Conditions
                      _buildSectionHeader('Terms & Conditions', LucideIcons.fileText),
                      SizedBox(height: context.rh(8)),
                      _buildPolicyCard(_termsContent),
                      SizedBox(height: context.rh(12)),
                      _buildCheckbox(
                        value: _acceptedTerms,
                        onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                        label: 'I have read and accept the Terms & Conditions',
                      ),
                      SizedBox(height: context.rh(24)),
                    ],
                  ),
                ),
                // Bottom button
                Container(
                  padding: context.rAll(16),
                  decoration: BoxDecoration(
                    color: AppTheme.pureSurface,
                    border: Border(top: BorderSide(color: AppTheme.whisperBorder)),
                  ),
                  child: SizedBox(
                    height: context.rh(50),
                    width: double.infinity,
                    child: ShadButton(
                      onPressed: _allAccepted ? _handleContinue : null,
                      child: const Text('Continue'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: context.rAll(8),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(context.rr(10)),
          ),
          child: Icon(icon, color: AppTheme.accent, size: context.ri(20)),
        ),
        SizedBox(width: context.rw(12)),
        Text(
          title,
          style: TextStyle(
            fontSize: context.rsp(18),
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoalInk,
          ),
        ),
      ],
    );
  }

  Widget _buildPolicyCard(String content) {
    return Container(
      constraints: BoxConstraints(maxHeight: context.rh(300)),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(16)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.rr(16)),
        child: Markdown(
          data: content.isEmpty ? 'No content available.' : content,
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          padding: context.rAll(16),
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(fontSize: context.rsp(13), color: AppTheme.charcoalInk, height: 1.5),
            h1: TextStyle(fontSize: context.rsp(20), fontWeight: FontWeight.bold, color: AppTheme.charcoalInk),
            h2: TextStyle(fontSize: context.rsp(16), fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
            h3: TextStyle(fontSize: context.rsp(14), fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
            listBullet: TextStyle(fontSize: context.rsp(13), color: AppTheme.charcoalInk),
            em: TextStyle(fontStyle: FontStyle.italic, color: AppTheme.mutedSteel, fontSize: context.rsp(13)),
            blockquoteDecoration: BoxDecoration(
              border: Border(left: BorderSide(color: AppTheme.accent, width: 3)),
              color: AppTheme.accent.withValues(alpha: 0.05),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckbox({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String label,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: context.rw(24),
            height: context.rh(24),
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: AppTheme.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.rr(4))),
            ),
          ),
          SizedBox(width: context.rw(12)),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: context.rsp(14),
                fontWeight: value ? FontWeight.w500 : FontWeight.w400,
                color: value ? AppTheme.charcoalInk : AppTheme.mutedSteel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
