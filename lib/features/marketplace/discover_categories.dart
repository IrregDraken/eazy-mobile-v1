import 'package:flutter/material.dart';

class DiscoverParentCategory {
  const DiscoverParentCategory({
    required this.slug,
    required this.name,
    required this.icon,
    required this.assetPath,
    required this.childCategorySlugs,
  });

  final String slug;
  final String name;
  final IconData icon;
  final String assetPath;
  final List<String> childCategorySlugs;
}

/// UI-level parent categories. Backend categories remain unchanged and are
/// resolved by slug to their current database IDs when a parent is selected.
const discoverParentCategories = <DiscoverParentCategory>[
  DiscoverParentCategory(
    slug: 'electronics-tech',
    name: 'Electronics & Tech',
    icon: Icons.devices_rounded,
    assetPath: 'assets/images/discover/categories/electronics_tech.webp',
    childCategorySlugs: ['electronics'],
  ),
  DiscoverParentCategory(
    slug: 'gaming',
    name: 'Gaming',
    icon: Icons.sports_esports_rounded,
    assetPath: 'assets/images/discover/categories/gaming.webp',
    childCategorySlugs: ['gaming'],
  ),
  DiscoverParentCategory(
    slug: 'fashion-lifestyle',
    name: 'Fashion & Lifestyle',
    icon: Icons.checkroom_rounded,
    assetPath: 'assets/images/discover/categories/fashion_lifestyle.webp',
    childCategorySlugs: [
      'baby-kids',
      'beauty',
      'fashion',
      'food-groceries',
      'home-living',
      'pets',
      'sports-outdoors',
    ],
  ),
  DiscoverParentCategory(
    slug: 'vehicles-automotive',
    name: 'Vehicles & Automotive',
    icon: Icons.directions_car_rounded,
    assetPath: 'assets/images/discover/categories/vehicles_automotive.webp',
    childCategorySlugs: ['vehicles'],
  ),
  DiscoverParentCategory(
    slug: 'services',
    name: 'Services',
    icon: Icons.handyman_rounded,
    assetPath: 'assets/images/discover/categories/services.webp',
    childCategorySlugs: ['books-learning', 'health', 'tools-hardware'],
  ),
];

List<String> resolveBackendCategoryIdsForParent(
  DiscoverParentCategory parent,
  Iterable<Map<String, dynamic>> backendCategories,
) {
  final childSlugs = parent.childCategorySlugs.toSet();
  return backendCategories
      .where((category) => childSlugs.contains(category['slug']?.toString()))
      .map((category) => category['id']?.toString())
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();
}
