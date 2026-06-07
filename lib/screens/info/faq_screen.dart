import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const _faqs = [
    {
      'q': 'How do I create an account?',
      'a': 'Download the app and sign up with your student email address. You will receive a verification link to activate your account.',
    },
    {
      'q': 'Is it free to list items?',
      'a': 'Yes! Listing items on Instiy is completely free. You only pay a small fee when you make a sale.',
    },
    {
      'q': 'How do I pay for items?',
      'a': 'You can pay using your Instiy wallet or via Paystack with card or mobile money. Sellers receive payments directly to their wallet.',
    },
    {
      'q': 'How does delivery work?',
      'a': 'You can arrange pickup with the seller or opt for delivery if the seller offers it. Delivery fees are calculated at checkout.',
    },
    {
      'q': 'What if I have a problem with an order?',
      'a': 'Contact the seller through our chat system first. If the issue persists, you can report it and our team will help resolve it.',
    },
    {
      'q': 'How do I withdraw my earnings?',
      'a': 'Go to your wallet and request a withdrawal. You can receive funds via mobile money or bank transfer.',
    },
    {
      'q': 'Is my information secure?',
      'a': 'Yes, we use industry-standard encryption and security practices. Your data is never shared without your consent.',
    },
    {
      'q': 'Which institutions are supported?',
      'a': 'We support all major Ghanaian universities and tertiary institutions. Check the registration page for the full list.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('FAQ')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _faqs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final faq = _faqs[index];
          return _FaqTile(question: faq['q']!, answer: faq['a']!);
        },
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    color: AppTheme.mutedSteel,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                widget.answer,
                style: const TextStyle(
                  color: AppTheme.mutedSteel,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
