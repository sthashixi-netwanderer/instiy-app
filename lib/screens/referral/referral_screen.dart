import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../utils/responsive.dart';
import '../../utils/formatters.dart';
import '../../utils/share_helper.dart';
import '../../models/referral_model.dart';
import '../../providers/providers.dart';
import '../../services/referral_service.dart';

/// Referral hub — the user's code, points and history, plus share and
/// copy actions for spreading their referral link.
class ReferralScreen extends ConsumerStatefulWidget {
  const ReferralScreen({super.key});

  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen> {
  bool _isLoading = true;
  String? _error;
  ReferralSummary? _summary;
  ReferralProgramConfig _config = const ReferralProgramConfig();
  List<ReferralRecord> _history = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!ref.read(authProvider).isAuthenticated) {
      Navigator.of(context).pushNamed('/login');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ReferralService.getSummary(),
        ReferralService.getProgramConfig(),
        ReferralService.getHistory(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as ReferralSummary;
        _config = results[1] as ReferralProgramConfig;
        _history = results[2] as List<ReferralRecord>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _copyLink() {
    final summary = _summary;
    if (summary == null || summary.referralCode.isEmpty) return;
    Clipboard.setData(ClipboardData(text: summary.link));
    ShadToaster.of(context).show(
      const ShadToast(title: Text('Referral link copied')),
    );
  }

  /// Same share mechanism as the product share button.
  Future<void> _share() async {
    final summary = _summary;
    if (summary == null || summary.referralCode.isEmpty) return;
    try {
      await ShareHelper.shareText(
        'Join me on Instiy! Sign up with my referral code '
        '${summary.referralCode} and start buying and selling on campus.\n\n'
        'Link: ${summary.link}',
        context: context,
      );
    } catch (_) {
      // System share sheet unavailable/cancelled — nothing to recover.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Refer & Earn'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.cloudOff,
                        size: context.ri(48),
                        color: Colors.grey[300],
                      ),
                      SizedBox(height: context.rh(12)),
                      Text(
                        'Couldn\'t load your referral info',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: context.rsp(15),
                        ),
                      ),
                      SizedBox(height: context.rh(12)),
                      ShadButton.outline(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      context.rw(16),
                      MediaQuery.paddingOf(context).top +
                          kToolbarHeight +
                          context.rh(16),
                      context.rw(16),
                      context.rh(32),
                    ),
                    children: [
                      _buildPointsCard(),
                      SizedBox(height: context.rh(16)),
                      _buildLinkCard(),
                      SizedBox(height: context.rh(16)),
                      if (_config.enabled) ...[
                        _buildHowItWorks(),
                        SizedBox(height: context.rh(16)),
                      ],
                      _buildHistory(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildPointsCard() {
    final summary = _summary!;
    return Container(
      width: double.infinity,
      padding: context.rAll(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accent,
            AppTheme.accent.withValues(alpha: 0.75),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(context.rr(18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.gift,
                size: context.ri(18),
                color: Colors.white.withValues(alpha: 0.9),
              ),
              SizedBox(width: context.rw(8)),
              Text(
                'Your referral points',
                style: TextStyle(
                  fontSize: context.rsp(12),
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
          SizedBox(height: context.rh(8)),
          Text(
            _fmtPoints(summary.points),
            style: TextStyle(
              fontSize: context.rsp(38),
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
            ),
          ),
          SizedBox(height: context.rh(12)),
          Row(
            children: [
              _statChip(
                '${summary.totalReferred}',
                summary.totalReferred == 1 ? 'friend joined' : 'friends joined',
              ),
              SizedBox(width: context.rw(10)),
              _statChip('${summary.qualifiedCount}', 'completed'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String value, String label) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.rw(10),
        vertical: context.rh(5),
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(context.rr(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: context.rsp(13),
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          SizedBox(width: context.rw(4)),
          Text(
            label,
            style: TextStyle(
              fontSize: context.rsp(11),
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkCard() {
    final summary = _summary!;
    final hasCode = summary.referralCode.isNotEmpty;
    return Container(
      padding: context.rAll(16),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(16)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your referral link',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: context.rsp(14),
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(10)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: context.rw(12),
              vertical: context.rh(12),
            ),
            decoration: BoxDecoration(
              color: AppTheme.warmMist,
              borderRadius: BorderRadius.circular(context.rr(10)),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.link,
                  size: context.ri(14),
                  color: AppTheme.mutedSteel,
                ),
                SizedBox(width: context.rw(8)),
                Expanded(
                  child: Text(
                    hasCode ? summary.link : 'Generating your code…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: context.rsp(12),
                      color: hasCode
                          ? AppTheme.charcoalInk
                          : AppTheme.mutedSteel,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: context.rh(12)),
          Row(
            children: [
              Expanded(
                child: ShadButton.outline(
                  onPressed: hasCode ? _copyLink : null,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.copy, size: 15),
                      SizedBox(width: 6),
                      Text('Copy link'),
                    ],
                  ),
                ),
              ),
              SizedBox(width: context.rw(10)),
              Expanded(
                flex: 2,
                child: ShadButton(
                  onPressed: hasCode ? _share : null,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.share2, size: 15),
                      SizedBox(width: 6),
                      Text(
                        'Share with friends',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorks() {
    return Container(
      padding: context.rAll(16),
      decoration: BoxDecoration(
        color: AppTheme.warmMist,
        borderRadius: BorderRadius.circular(context.rr(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: context.rsp(14),
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(10)),
          _step(
            LucideIcons.share2,
            'Share your link',
            'Send your referral link or code to friends and colleagues.',
          ),
          _step(
            LucideIcons.userPlus,
            'They sign up',
            'Your code is filled in automatically when they register '
            'through your link.',
          ),
          _step(
            LucideIcons.packageCheck,
            'You earn ${_fmtPoints(_config.pointsPerReferral)} points',
            'Points land in your account once their first order of '
            '${formatGhs(_config.minPurchaseAmountGhs)} or more is '
            'delivered.',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _step(
    IconData icon,
    String title,
    String subtitle, {
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                padding: context.rAll(7),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: context.ri(14), color: AppTheme.accent),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: AppTheme.whisperBorder,
                    margin: EdgeInsets.symmetric(vertical: context.rh(4)),
                  ),
                ),
            ],
          ),
          SizedBox(width: context.rw(10)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: context.rh(isLast ? 0 : 14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: context.rsp(13),
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  SizedBox(height: context.rh(2)),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: context.rsp(12),
                      color: AppTheme.mutedSteel,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your referrals',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: context.rsp(16),
            color: AppTheme.charcoalInk,
          ),
        ),
        SizedBox(height: context.rh(10)),
        if (_history.isEmpty)
          Container(
            width: double.infinity,
            padding: context.rAll(20),
            decoration: BoxDecoration(
              color: AppTheme.pureSurface,
              borderRadius: BorderRadius.circular(context.rr(14)),
              border: Border.all(color: AppTheme.whisperBorder),
            ),
            child: Column(
              children: [
                Icon(
                  LucideIcons.users,
                  size: context.ri(28),
                  color: AppTheme.mutedSteel,
                ),
                SizedBox(height: context.rh(8)),
                Text(
                  'No referrals yet',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: context.rsp(14),
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(4)),
                Text(
                  'Share your link above to get started.',
                  style: TextStyle(
                    fontSize: context.rsp(12),
                    color: AppTheme.mutedSteel,
                  ),
                ),
              ],
            ),
          )
        else
          for (final record in _history) ...[
            _buildHistoryRow(record),
            SizedBox(height: context.rh(8)),
          ],
      ],
    );
  }

  Widget _buildHistoryRow(ReferralRecord record) {
    final name = record.referredName?.trim().isNotEmpty == true
        ? record.referredName!.trim()
        : 'Instiy user';
    // Show first name only for privacy.
    final firstName = name.split(' ').first;

    return Container(
      padding: context.rAll(12),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(12)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Row(
        children: [
          ShadAvatar(
            record.referredAvatar?.isNotEmpty == true
                ? record.referredAvatar
                : null,
            size: Size(context.ri(34), context.ri(34)),
            backgroundColor: AppTheme.accent,
            placeholder: Text(
              firstName[0].toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: context.rsp(13),
              ),
            ),
          ),
          SizedBox(width: context.rw(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  firstName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: context.rsp(13),
                    color: AppTheme.charcoalInk,
                  ),
                ),
                Text(
                  'Joined ${_fmtDate(record.createdAt)}',
                  style: TextStyle(
                    fontSize: context.rsp(11),
                    color: AppTheme.mutedSteel,
                  ),
                ),
              ],
            ),
          ),
          record.isQualified
              ? Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.rw(10),
                    vertical: context.rh(5),
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.successMoss.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(context.rr(8)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.check,
                        size: context.ri(12),
                        color: AppTheme.successMoss,
                      ),
                      SizedBox(width: context.rw(4)),
                      Text(
                        '+${_fmtPoints(record.pointsAwarded)} pts',
                        style: TextStyle(
                          fontSize: context.rsp(11),
                          fontWeight: FontWeight.w700,
                          color: AppTheme.successMoss,
                        ),
                      ),
                    ],
                  ),
                )
              : Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.rw(10),
                    vertical: context.rh(5),
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warmMist,
                    borderRadius: BorderRadius.circular(context.rr(8)),
                  ),
                  child: Text(
                    'Pending',
                    style: TextStyle(
                      fontSize: context.rsp(11),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.mutedSteel,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  String _fmtPoints(int points) {
    if (points >= 1000000) {
      return '${(points / 1000000).toStringAsFixed(1)}M pts';
    }
    if (points >= 1000) {
      return '${(points / 1000).toStringAsFixed(points % 1000 == 0 ? 0 : 1)}K pts';
    }
    return '$points pts';
  }

  String _fmtDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
