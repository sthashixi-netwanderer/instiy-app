import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';

class ShareBottomSheet extends StatelessWidget {
  final String shareText;
  final String? analyticsId;
  final String analyticsType;

  const ShareBottomSheet({
    super.key,
    required this.shareText,
    this.analyticsId,
    this.analyticsType = 'product',
  });

  static void show(
    BuildContext context, {
    required String shareText,
    String? analyticsId,
    String analyticsType = 'product',
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareBottomSheet(
        shareText: shareText,
        analyticsId: analyticsId,
        analyticsType: analyticsType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Share to',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ShareOption(
                    assetPath: 'assets/whatsapp-svgrepo-com.svg',
                    bgColor: const Color(0xFF25D366),
                    label: 'WhatsApp',
                    onTap: () => _shareToSocial(context, 'whatsapp'),
                  ),
                  _ShareOption(
                    assetPath: 'assets/x.png',
                    bgColor: const Color(0xFF000000),
                    label: 'X',
                    onTap: () => _shareToSocial(context, 'twitter'),
                  ),
                  _ShareOption(
                    assetPath: 'assets/facebook-svgrepo-com.svg',
                    bgColor: const Color(0xFF1877F2),
                    label: 'Facebook',
                    onTap: () => _shareToSocial(context, 'facebook'),
                  ),
                  _ShareOption(
                    assetPath: 'assets/instagram-svgrepo-com.svg',
                    bgColor: const Color(0xFFE4405F),
                    label: 'Instagram',
                    onTap: () => _shareToSocial(context, 'instagram'),
                  ),
                  _ShareOption(
                    icon: Icons.copy,
                    bgColor: AppTheme.mutedSteel,
                    label: 'Copy Link',
                    onTap: () => _shareToSocial(context, 'copy_link'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _shareToSocial(BuildContext context, String platform) async {
    final text = Uri.encodeComponent(shareText);
    bool launched = false;

    switch (platform) {
      case 'whatsapp':
        final appUrl = Uri.parse('whatsapp://send?text=$text');
        final webUrl = Uri.parse('https://wa.me/?text=$text');
        if (await canLaunchUrl(appUrl)) {
          launched = await launchUrl(appUrl, mode: LaunchMode.externalApplication);
        } else if (await canLaunchUrl(webUrl)) {
          launched = await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        }

      case 'twitter':
        final appUrl = Uri.parse('twitter://post?message=$text');
        final webUrl = Uri.parse('https://x.com/intent/post?text=$text');
        if (await canLaunchUrl(appUrl)) {
          launched = await launchUrl(appUrl, mode: LaunchMode.externalApplication);
        } else if (await canLaunchUrl(webUrl)) {
          launched = await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        }

      case 'facebook':
        final appUrl = Uri.parse('fb://sharer/sharer.php?quote=$text');
        final webUrl = Uri.parse('https://www.facebook.com/sharer/sharer.php?quote=$text');
        if (await canLaunchUrl(appUrl)) {
          launched = await launchUrl(appUrl, mode: LaunchMode.externalApplication);
        } else if (await canLaunchUrl(webUrl)) {
          launched = await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        }

      case 'instagram':
        await Clipboard.setData(ClipboardData(text: shareText));
        if (context.mounted) {
          ShadToaster.of(context).show(
            const ShadToast(title: Text('Copied! Open Instagram and paste')),
          );
        }
        if (context.mounted) Navigator.of(context).pop();
        return;

      case 'copy_link':
        await Clipboard.setData(ClipboardData(text: shareText));
        if (context.mounted) {
          ShadToaster.of(context).show(
            const ShadToast(title: Text('Link copied to clipboard!')),
          );
        }
        if (context.mounted) Navigator.of(context).pop();
        return;
    }

    if (!launched) {
      await Clipboard.setData(ClipboardData(text: shareText));
      if (context.mounted) {
        ShadToaster.of(context).show(
          const ShadToast(title: Text('Copied to clipboard')),
        );
      }
    }

    if (context.mounted) Navigator.of(context).pop();
  }
}

class _ShareOption extends StatelessWidget {
  final String? assetPath;
  final IconData? icon;
  final Color bgColor;
  final String label;
  final VoidCallback onTap;

  const _ShareOption({
    this.assetPath,
    this.icon,
    required this.bgColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget iconWidget;
    if (assetPath != null) {
      if (assetPath!.endsWith('.svg')) {
        iconWidget = SvgPicture.asset(assetPath!, width: 28, height: 28);
      } else {
        iconWidget = Image.asset(assetPath!, width: 28, height: 28);
      }
    } else {
      iconWidget = Icon(icon, color: bgColor, size: 28);
    }

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bgColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(child: iconWidget),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.charcoalInk),
          ),
        ],
      ),
    );
  }
}
