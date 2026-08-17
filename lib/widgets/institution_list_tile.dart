import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'dart:math' as math;
import '../models/institution_model.dart';
import '../config/app_theme.dart';

class InstitutionListTile extends StatelessWidget {
  final Institution institution;
  final bool isSelected;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool dense;

  const InstitutionListTile({
    super.key,
    required this.institution,
    required this.isSelected,
    this.onTap,
    this.trailing,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final inst = institution;
    final tileHeight = dense ? 64.0 : 72.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: isSelected
            ? BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: SizedBox(
          height: tileHeight,
          child: Row(
            children: [
              _buildLeading(inst),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextContent(inst),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeading(Institution inst) {
    if (inst.logoUrl != null && inst.logoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CachedNetworkImage(
          imageUrl: inst.logoUrl!,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          memCacheWidth: 36,
          placeholder: (_, _) => Container(
            width: 36,
            height: 36,
            color: AppTheme.warmMist,
          ),
          errorWidget: (_, _, _) => Container(
            width: 36,
            height: 36,
            color: AppTheme.warmMist,
            child: const Icon(LucideIcons.graduationCap, size: 20),
          ),
        ),
      );
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Center(
        child: Text(
          inst.code.substring(0, math.min(3, inst.code.length)),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildTextContent(Institution inst) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          inst.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppTheme.accent : const Color(0xFF1E293B),
            height: 1.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          inst.location != null ? '${inst.code} \u2022 ${inst.location}' : inst.code,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.mutedSteel,
          ),
        ),
      ],
    );
  }
}

class InstitutionListTileCheckbox extends StatelessWidget {
  final Institution institution;
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  const InstitutionListTileCheckbox({
    super.key,
    required this.institution,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InstitutionListTile(
      institution: institution,
      isSelected: isSelected,
      onTap: () => onChanged(!isSelected),
      trailing: Checkbox(
        value: isSelected,
        onChanged: onChanged,
        activeColor: AppTheme.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}

class InstitutionListTileRadio extends StatelessWidget {
  final Institution institution;
  final bool isSelected;
  final VoidCallback? onTap;

  const InstitutionListTileRadio({
    super.key,
    required this.institution,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InstitutionListTile(
      institution: institution,
      isSelected: isSelected,
      onTap: onTap,
      trailing: Icon(
        LucideIcons.check,
        color: isSelected ? AppTheme.accent : Colors.transparent,
        size: 20,
      ),
    );
  }
}
