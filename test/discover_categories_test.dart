import 'package:flutter_test/flutter_test.dart';
import 'package:eazy_mobile_v1/features/marketplace/discover_categories.dart';

void main() {
  test('Discover exposes exactly the five requested parent categories', () {
    expect(
      discoverParentCategories.map((category) => category.name).toList(),
      equals([
        'Electronics & Tech',
        'Gaming',
        'Fashion & Lifestyle',
        'Vehicles & Automotive',
        'Services',
      ]),
    );
  });

  test('every existing backend category is mapped exactly once', () {
    const backendSeedSlugs = <String>{
      'baby-kids',
      'beauty',
      'books-learning',
      'electronics',
      'fashion',
      'food-groceries',
      'gaming',
      'health',
      'home-living',
      'pets',
      'sports-outdoors',
      'tools-hardware',
      'vehicles',
    };
    final mappedSlugs =
        discoverParentCategories
            .expand((category) => category.childCategorySlugs)
            .toList();

    expect(mappedSlugs.length, backendSeedSlugs.length);
    expect(mappedSlugs.toSet(), equals(backendSeedSlugs));
  });

  test('parent filter resolves every mapped backend category ID', () {
    final parent = discoverParentCategories.firstWhere(
      (category) => category.slug == 'fashion-lifestyle',
    );
    final categories = <Map<String, dynamic>>[
      for (var index = 0; index < parent.childCategorySlugs.length; index++)
        {'id': 'backend-id-$index', 'slug': parent.childCategorySlugs[index]},
      {'id': 'unmapped-id', 'slug': 'not-in-a-parent'},
    ];

    expect(
      resolveBackendCategoryIdsForParent(parent, categories),
      equals([
        for (var index = 0; index < parent.childCategorySlugs.length; index++)
          'backend-id-$index',
      ]),
    );
  });
}
