import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import '../models/category_model.dart';
import '../services/category_image_cache_service.dart';
import 'animated_press.dart';

class CategorySection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? titleIcon;
  final List<Category> categories;
  final ValueChanged<Category> onTap;
  final VoidCallback? onSeeAll;

  const CategorySection({
    super.key,
    required this.title,
    this.subtitle,
    this.titleIcon,
    required this.categories,
    required this.onTap,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (titleIcon != null) ...[
                Icon(titleIcon, size: 18, color: AppTheme.charcoalInk),
                const SizedBox(width: 6),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
                    ),
                ],
              ),
              const Spacer(),
              if (onSeeAll != null)
                GestureDetector(
                  onTap: onSeeAll,
                  child: const Row(
                    children: [
                      Text(
                        'See All',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accent,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(LucideIcons.chevronRight, size: 16, color: AppTheme.accent),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: categories.length,
            itemExtent: 128,
            itemBuilder: (context, index) {
              final category = categories[index];
              return _HorizontalCategoryCard(
                category: category,
                onTap: () => onTap(category),
              );
            },
          ),
        ),
      ],
    );
  }
}

class CategoryGrid extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? titleIcon;
  final List<Category> categories;
  final ValueChanged<Category> onTap;
  final VoidCallback? onSeeAll;
  final int maxItems;

  const CategoryGrid({
    super.key,
    required this.title,
    this.subtitle,
    this.titleIcon,
    required this.categories,
    required this.onTap,
    this.onSeeAll,
    this.maxItems = 6,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();

    final displayCategories = categories.take(maxItems).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (titleIcon != null) ...[
                Icon(titleIcon, size: 18, color: AppTheme.charcoalInk),
                const SizedBox(width: 6),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
                    ),
                ],
              ),
              const Spacer(),
              if (onSeeAll != null)
                GestureDetector(
                  onTap: onSeeAll,
                  child: const Row(
                    children: [
                      Text(
                        'See All',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accent,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(LucideIcons.chevronRight, size: 16, color: AppTheme.accent),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Builder(builder: (context) {
            // ignore: avoid_print
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final box = context.findRenderObject();
              if (box is RenderBox) {
                // ignore: avoid_print
                print('CATGRID_DEBUG gridView=${box.size}');
              }
            });
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.8,
              ),
              itemCount: displayCategories.length,
              itemBuilder: (context, index) {
                final category = displayCategories[index];
                return _GridCategoryCard(
                  category: category,
                  onTap: () => onTap(category),
                );
              },
            );
          }),
        ),
      ],
    );
  }
}

class _HorizontalCategoryCard extends StatelessWidget {
  final Category category;
  final VoidCallback onTap;

  const _HorizontalCategoryCard({
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPress(
      onTap: onTap,
      child: Container(
        width: 120,
        height: 110,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Color(AppTheme.categoryColors[category.colorIndex % AppTheme.categoryColors.length])
              .withValues(alpha: 0.15),
        ),
        clipBehavior: Clip.antiAlias,
        child: category.imageUrl != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: category.imageUrl!,
                    cacheManager: CategoryImageCacheManager(),
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 150),
                    placeholder: (_, _) => _buildIconFallback(),
                    errorWidget: (_, _, _) => _buildIconFallback(),
                  ),
                  // Dark overlay for text readability
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.1),
                          Colors.black.withValues(alpha: 0.6),
                        ],
                        stops: const [0.4, 1.0],
                      ),
                    ),
                  ),
                  // Category name
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 10,
                    child: Text(
                      category.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.2,
                        shadows: [
                          Shadow(blurRadius: 4, color: Colors.black54),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getCategoryIcon(category.icon),
                    size: 28,
                    color: Color(AppTheme.categoryColors[category.colorIndex % AppTheme.categoryColors.length]),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      category.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.charcoalInk,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildIconFallback() {
    final color = Color(AppTheme.categoryColors[category.colorIndex % AppTheme.categoryColors.length]);
    return Container(
      color: color.withValues(alpha: 0.15),
      child: Center(
        child: Icon(
          _getCategoryIcon(category.icon),
          size: 28,
          color: color,
        ),
      ),
    );
  }
}

class _GridCategoryCard extends StatelessWidget {
  final Category category;
  final VoidCallback onTap;

  const _GridCategoryCard({
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPress(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Color(AppTheme.categoryColors[category.colorIndex % AppTheme.categoryColors.length])
              .withValues(alpha: 0.1),
        ),
        clipBehavior: Clip.antiAlias,
        child: category.imageUrl != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: category.imageUrl!,
                    cacheManager: CategoryImageCacheManager(),
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 150),
                    placeholder: (_, _) => _buildIconFallback(context),
                    errorWidget: (_, _, _) => _buildIconFallback(context),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.1),
                          Colors.black.withValues(alpha: 0.6),
                        ],
                        stops: const [0.4, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Text(
                      category.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.2,
                        shadows: [
                          Shadow(blurRadius: 4, color: Colors.black54),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      _getCategoryIcon(category.icon),
                      size: 20,
                      color: Color(AppTheme.categoryColors[category.colorIndex % AppTheme.categoryColors.length]),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        category.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.charcoalInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildIconFallback(BuildContext context) {
    final color = Color(AppTheme.categoryColors[category.colorIndex % AppTheme.categoryColors.length]);
    return Container(
      color: color.withValues(alpha: 0.15),
      child: Center(
        child: Icon(
          _getCategoryIcon(category.icon),
          size: 24,
          color: color,
        ),
      ),
    );
  }
}

IconData _getCategoryIcon(String? icon) {
  switch (icon) {
    case 'book':
      return LucideIcons.bookOpen;
    case 'shirt':
      return LucideIcons.shirt;
    case 'dumbbell':
      return LucideIcons.dumbbell;
    case 'music':
      return LucideIcons.music;
    case 'gamepad':
      return LucideIcons.gamepad2;
    case 'home':
      return LucideIcons.home;
    case 'car':
      return LucideIcons.car;
    case 'coffee':
      return LucideIcons.coffee;
    case 'video':
      return LucideIcons.video;
    case 'code':
      return LucideIcons.code;
    case 'wrench':
      return LucideIcons.wrench;
    case 'armchair':
      return LucideIcons.armchair;
    case 'grid':
    default:
      return LucideIcons.grid3x3;
  }
}
