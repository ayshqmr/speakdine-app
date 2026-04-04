/// Stored on each menu document as [dishCategory] (Firestore).
abstract final class MenuDishCategory {
  static const appetizer = 'appetizer';
  static const main = 'main';
  static const dessert = 'dessert';
  static const drink = 'drink';

  static const List<String> idsInMenuOrder = [
    appetizer,
    main,
    dessert,
    drink,
  ];

  static const Map<String, String> labels = {
    appetizer: 'Appetizer',
    main: 'Main',
    dessert: 'Dessert',
    drink: 'Drink',
  };

  /// Plural headings shown above each group of dishes (customer + merchant menu).
  static const Map<String, String> sectionHeadings = {
    appetizer: 'Appetizers',
    main: 'Main courses',
    dessert: 'Desserts',
    drink: 'Drinks',
  };

  static String normalizeId(Object? raw) {
    final s = raw?.toString().trim().toLowerCase() ?? '';
    if (idsInMenuOrder.contains(s)) return s;
    return main;
  }

  static String labelFor(Object? raw) =>
      labels[normalizeId(raw)] ?? labels[main]!;

  static String sectionHeadingFor(Object? raw) =>
      sectionHeadings[normalizeId(raw)] ?? sectionHeadings[main]!;
}
