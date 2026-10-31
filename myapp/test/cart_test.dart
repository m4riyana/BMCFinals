import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho_stationery/commerce/commerce_api.dart';
import 'package:ibasho_stationery/commerce/commerce_store.dart';
import 'package:ibasho_stationery/commerce/models.dart';

const notebook = Product(
  id: 'ibasho-001', slug: 'minimalist-a5-notebook', name: 'Minimalist A5 Notebook',
  categoryId: 'notebooks', categoryName: 'Notebooks', price: 89, stock: 8,
  description: 'An everyday notebook.', imagePath: 'assets/images/products/minimalist-a5-notebook.jpg',
);

class CartApi extends CommerceApi {
  bool unavailable = false;
  CommerceException? saveError;
  List<Map<String, dynamic>> saved = [];
  Completer<Map<String, dynamic>>? delayedCart;
  @override
  String? get currentUid => 'customer';
  @override
  String? get currentEmail => 'creator@example.com';
  @override
  Stream<String?> get authChanges => const Stream.empty();
  @override
  Future<Map<String, dynamic>> catalog() async {
    if (unavailable) throw const CommerceException('Unable to reach the store.');
    return {'products': [notebook.toJson()], 'categories': []};
  }
  @override
  Future<Map<String, dynamic>> me() async => {'isAdmin': false};
  @override
  Future<Map<String, dynamic>> wishlist() async => {'productIds': []};
  @override
  Future<Map<String, dynamic>> orders() async => {'orders': []};
  @override
  Future<Map<String, dynamic>> cart() async => delayedCart == null ? {'items': saved} : await delayedCart!.future;
  @override
  Future<Map<String, dynamic>> saveCart(List<Map<String, dynamic>> items) async {
    if (unavailable) throw const CommerceException('Unable to reach the store.');
    if (saveError != null) throw saveError!;
    saved = items.map((item) => Map<String, dynamic>.from(item)).toList();
    return {'items': saved};
  }
}

void main() {
  late CartApi api;
  late CommerceStore store;
  setUp(() {
    api = CartApi();
    store = CommerceStore(api: api, fallbackLoader: () async => {'products': [notebook.toJson()], 'categories': []});
  });
  tearDown(() => store.dispose());

  test('signed-in cart keeps offline additions and syncs on retry', () async {
    api.unavailable = true;
    await store.load();
    await store.addToCart(notebook, quantity: 2);
    expect(store.cart, {notebook.id: 2});
    expect(store.cartCount, 2);
    expect(store.subtotal, 178);
    api.unavailable = false;
    await store.refresh();
    expect(store.cart, {notebook.id: 2});
    expect(api.saved, [{'productId': notebook.id, 'quantity': 2}]);
  });

  test('an old cart response cannot erase a newer Add to Cart', () async {
    await store.load();
    api.delayedCart = Completer<Map<String, dynamic>>();
    final refresh = store.refresh();
    await Future<void>.delayed(Duration.zero);
    await store.addToCart(notebook);
    api.delayedCart!.complete({'items': []});
    await refresh;
    expect(store.cart, {notebook.id: 1});
  });

  test('server stock rejection still rolls back and reports failure', () async {
    await store.load();
    api.saveError = const CommerceException('Not enough stock.', 409);
    await expectLater(store.addToCart(notebook), throwsA(isA<CommerceException>()));
    expect(store.cart, isEmpty);
  });

  test('network loss during save keeps the item for a later retry', () async {
    await store.load();
    api.saveError = const CommerceException('Unable to reach the store.');
    await store.addToCart(notebook);
    expect(store.cart, {notebook.id: 1});
    api.saveError = null;
    await store.refresh();
    expect(api.saved, [{'productId': notebook.id, 'quantity': 1}]);
  });
}
