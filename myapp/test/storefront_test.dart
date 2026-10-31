import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho_stationery/commerce/commerce_store.dart';
import 'package:ibasho_stationery/commerce/models.dart';
import 'package:ibasho_stationery/commerce/shopping_pages.dart';
import 'package:ibasho_stationery/commerce/storefront.dart';
import 'package:ibasho_stationery/main.dart' show DashboardPage, ibashoTheme;

List<Product> _products() => List.generate(
      10,
      (index) {
        final slug = switch (index) {
          0 => 'minimalist-a5-notebook',
          1 => 'gel-pen-set',
          2 => 'pastel-highlighters',
          3 => 'mechanical-pencil',
          4 => 'sticky-notes',
          5 => 'washi-tape',
          6 => 'canvas-pencil-case',
          7 => 'grid-writing-pad',
          8 => 'pastel-erasers',
          _ => 'desk-organizer',
        };
        return Product(
          id: 'product-$index',
          slug: slug,
          name: 'Stationery item $index',
          categoryId: 'notebooks',
          categoryName: 'Notebooks',
          price: 50 + index.toDouble(),
          stock: 10,
          description: 'A useful stationery item for everyday ideas.',
          imagePath: 'assets/images/products/$slug.jpg',
          featured: true,
          isNew: index.isOdd,
        );
      },
    );

Future<void> _pumpStorefront(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final store = CommerceStore.preview(
    products: _products(),
    signedIn: true,
  );
  addTearDown(store.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Storefront(store: store, onLogin: (_) async {}),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dashboard and shop share the bag across navigation', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = CommerceStore.preview(products: _products(), signedIn: true);
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(theme: ibashoTheme(), home: DashboardPage(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('01    THE STATIONERY COLLECTION'), findsOneWidget);
    expect(find.text('02    YOUR ESSENTIALS'), findsOneWidget);
    expect(find.text('03    YOUR PROFILE'), findsOneWidget);

    await tester.tap(find.text('EXPLORE SUPPLIES →'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ADD TO CART').first);
    await tester.tap(find.text('ADD TO CART').first);
    await tester.pumpAndSettle();
    expect(store.cart, {'product-0': 1});
    expect(find.text('Stationery item 0 added to your bag.'), findsOneWidget);
    final shopBadge = tester.widget<Badge>(find.descendant(of: find.byTooltip('Shopping cart'), matching: find.byType(Badge)));
    expect((shopBadge.label as Text).data, '1');

    Navigator.of(tester.element(find.byType(Storefront))).pop();
    await tester.pumpAndSettle();
    final dashboardBadge = tester.widget<Badge>(find.descendant(of: find.byTooltip('Shopping cart'), matching: find.byType(Badge)));
    expect((dashboardBadge.label as Text).data, '1');
    await tester.tap(find.byTooltip('Shopping cart'));
    await tester.pumpAndSettle();
    expect(find.text('Your shopping bag'), findsOneWidget);
    final line = tester.widget<CartLine>(find.byType(CartLine));
    expect(line.product.id, 'product-0');
    expect(line.quantity, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard keeps its three panels on mobile', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = CommerceStore.preview(products: _products(), signedIn: true);
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(theme: ibashoTheme(), home: DashboardPage(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('02    YOUR ESSENTIALS'), findsOneWidget);
    expect(find.text('My orders'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product details cart badge updates immediately after adding', (tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final product = _products().first;
    final store = CommerceStore.preview(products: [product], signedIn: true);
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(theme: ibashoTheme(), home: ProductDetailsPage(
      product: product, store: store,
      onAdd: (p, {quantity = 1}) => store.addToCart(p, quantity: quantity),
      onBuyNow: (p, {quantity = 1}) async {}, onSave: (_) async {},
      onCheckout: () async {}, onProduct: (_) async {},
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ADD TO BAG'));
    await tester.pumpAndSettle();
    final badge = tester.widget<Badge>(find.descendant(of: find.byTooltip('Shopping cart'), matching: find.byType(Badge)));
    expect(badge.isLabelVisible, isTrue);
    expect((badge.label as Text).data, '2');
    expect(store.cart, {product.id: 2});
  });

  test('bundled catalog and all product images are available locally',
      () async {
    final catalog = jsonDecode(
      await rootBundle.loadString('assets/catalog.json'),
    ) as Map<String, dynamic>;
    final products = catalog['products'] as List<dynamic>;

    expect(products, hasLength(10));
    for (final product in products) {
      final slug = (product as Map<String, dynamic>)['slug'] as String;
      await rootBundle.load('assets/images/products/$slug.jpg');
    }
  });

  testWidgets('product cards use four columns on wide desktop', (tester) async {
    await _pumpStorefront(tester, const Size(1440, 1000));

    final grid = tester.widget<GridView>(find.byType(GridView).first);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 4);
    expect(find.text('Little essentials.\nBig ideas.'), findsOneWidget);
  });

  testWidgets('product cards use three columns on medium desktop',
      (tester) async {
    await _pumpStorefront(tester, const Size(900, 1000));

    final grid = tester.widget<GridView>(find.byType(GridView).first);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
  });

  testWidgets('product cards use two columns on mobile', (tester) async {
    await _pumpStorefront(tester, const Size(390, 844));

    final grid = tester.widget<GridView>(find.byType(GridView).first);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
  });

  testWidgets('product details quantity is passed to Buy Now', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final product = _products().first;
    final store = CommerceStore.preview(
      products: [product],
      signedIn: true,
    );
    addTearDown(store.dispose);
    var purchasedQuantity = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ProductDetailsPage(
          product: product,
          store: store,
          onAdd: (product, {quantity = 1}) async {},
          onBuyNow: (product, {quantity = 1}) async {
            purchasedQuantity = quantity;
          },
          onSave: (product) async {},
          onCheckout: () async {},
          onProduct: (product) async {},
        ),
      ),
    );

    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BUY NOW'));
    await tester.pumpAndSettle();

    expect(purchasedQuantity, 2);
  });
}
