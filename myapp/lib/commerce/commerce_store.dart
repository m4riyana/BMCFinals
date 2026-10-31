import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'commerce_api.dart';
import 'models.dart';

class CommerceStore extends ChangeNotifier {
  final CommerceApi api;
  final Future<Map<String, dynamic>> Function() _fallbackLoader;
  final bool _preview;
  StreamSubscription<String?>? _authSubscription;
  bool _disposed = false;
  bool _started = false;
  bool _cartDirty = false;
  String? _uid;
  int _session = 0, _cartVersion = 0, _wishlistVersion = 0;
  Future<void> _writes = Future<void>.value();
  String? _checkoutKey, _checkoutFingerprint;
  Map<String, int>? _pendingXenditCart;
  List<Product> products = [];
  List<ShopCategory> categories = [];
  Map<String, int> cart = {};
  Set<String> wishlist = {};
  List<ShopOrder> orders = [];
  CustomerProfile? profile;
  bool isAdmin = false, loading = false, offline = false, catalogReady = false;
  String? error;
  double standardShippingFee = 60, freeShippingThreshold = 1000;

  CommerceStore(
      {CommerceApi? api,
      Future<Map<String, dynamic>> Function()? fallbackLoader})
      : api = api ?? CommerceApi(),
        _fallbackLoader = fallbackLoader ?? _bundledCatalog,
        _preview = false;

  /// Isolated UI-test fixture; never used as a checkout or persistence fallback.
  CommerceStore.preview(
      {required this.products,
      this.categories = const [],
      Map<String, int>? cart,
      Set<String>? wishlist,
      bool signedIn = false,
      this.orders = const [],
      this.isAdmin = false})
      : api = CommerceApi(),
        _fallbackLoader = _bundledCatalog,
        _preview = true,
        _uid = signedIn ? 'preview-user' : null {
    this.cart = cart ?? {};
    this.wishlist = wishlist ?? {};
    catalogReady = true;
  }
  static Future<Map<String, dynamic>> _bundledCatalog() async =>
      Map<String, dynamic>.from(
          jsonDecode(await rootBundle.loadString('assets/catalog.json'))
              as Map);
  bool get isSignedIn => _uid != null;
  String? get userEmail => _preview
      ? (_uid == null ? null : 'creator@example.com')
      : api.currentEmail;
  int get cartCount => cart.values.fold(0, (sum, qty) => sum + qty);
  double get subtotal =>
      products.fold(0, (sum, p) => sum + p.price * (cart[p.id] ?? 0));
  double get shippingFee => cart.isEmpty || subtotal >= freeShippingThreshold
      ? 0
      : standardShippingFee;
  double get total => subtotal + shippingFee;
  List<Product> get wishlistProducts =>
      products.where((p) => wishlist.contains(p.id)).toList();
  Product? productById(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void clearError() {
    error = null;
    _emit();
  }

  void _readCatalog(Map<String, dynamic> json) {
    categories = (json['categories'] as List? ?? [])
        .map((e) => ShopCategory.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final names = {for (final c in categories) c.id: c.name};
    products = (json['products'] as List? ?? [])
        .map((e) {
          final p = Map<String, dynamic>.from(e as Map);
          return Product.fromJson(p, categoryName: names[p['categoryId']]);
        })
        .where((p) => p.isActive)
        .toList();
    final shipping = json['shipping'];
    if (shipping is Map) {
      standardShippingFee = (shipping['standardFee'] as num? ?? 60).toDouble();
      freeShippingThreshold =
          (shipping['freeShippingThreshold'] as num? ?? 1000).toDouble();
    }
    catalogReady = true;
  }

  Future<void> load() async {
    if (_preview) return;
    if (!_started) {
      _started = true;
      _uid = api.currentUid;
      _authSubscription = api.authChanges.listen((uid) {
        if (uid == _uid) return;
        final guestCart =
            _uid == null ? Map<String, int>.from(cart) : <String, int>{};
        final guestWishlist =
            _uid == null ? Set<String>.from(wishlist) : <String>{};
        _uid = uid;
        _session++;
        cart = {};
        wishlist = {};
        orders = [];
        profile = null;
        isAdmin = false;
        _cartDirty = false;
        _checkoutKey = null;
        _checkoutFingerprint = null;
        _pendingXenditCart = null;
        _emit();
        if (uid != null)
          unawaited(
              _loadUser(guestCart: guestCart, guestWishlist: guestWishlist));
      });
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (_preview) return;
    loading = true;
    error = null;
    _emit();
    try {
      _readCatalog(await api.catalog());
      offline = false;
    } catch (_) {
      offline = true;
      error =
          'Showing the saved collection. Live stock and checkout are temporarily unavailable.';
      if (!catalogReady) {
        try {
          _readCatalog(await _fallbackLoader());
        } catch (_) {
          error = 'The collection could not be loaded. Please try again.';
        }
      }
    }
    if (isSignedIn && !offline) await _loadUser();
    loading = false;
    _emit();
  }

  Future<void> _loadUser(
      {Map<String, int> guestCart = const {},
      Set<String> guestWishlist = const {}}) async {
    final session = _session;
    final cartVersion = _cartVersion;
    if (!isSignedIn) return;
    try {
      final result = await Future.wait(
          [api.me(), api.cart(), api.wishlist(), api.orders()]);
      if (session != _session || _disposed) return;
      isAdmin = result[0]['isAdmin'] == true;
      // A slow read must not replace additions made while it was in flight,
      // or the local bag waiting to sync after a connection failure.
      if (!_cartDirty && cartVersion == _cartVersion) {
        cart = {
          for (final raw in result[1]['items'] as List? ?? [])
            '${raw['productId']}': (raw['quantity'] as num).toInt()
        };
      }
      wishlist =
          (result[2]['productIds'] as List? ?? []).map((e) => '$e').toSet();
      orders = (result[3]['orders'] as List? ?? [])
          .map((e) => ShopOrder.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      try {
        final profileResult = await api.profile();
        if (session != _session || _disposed) return;
        profile = CustomerProfile.fromJson(
            Map<String, dynamic>.from(profileResult['profile'] as Map));
      } catch (_) {
        // Account profile support may be temporarily unavailable. Keep the
        // existing cart, wishlist, and order experience usable in the meantime.
      }
      final loadedProfile = profile;
      if (loadedProfile != null &&
          loadedProfile.username.isEmpty &&
          api.currentUid == _uid) {
        final email = api.currentEmail ?? '';
        final suffix = (api.currentUid ?? 'customer')
            .replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
        final fallbackName = email.contains('@') ? email.split('@').first : '';
        try {
          final saved = await api.saveProfile(
            username:
                'creator-${suffix.length > 8 ? suffix.substring(suffix.length - 8) : suffix}',
            name: fallbackName,
            contactEmail: email,
            phoneNumber: loadedProfile.phoneNumber,
            address: loadedProfile.address,
          );
          profile = CustomerProfile.fromJson(
              Map<String, dynamic>.from(saved['profile'] as Map));
        } catch (_) {
          // Keep the signed-in storefront usable; profile edits can be retried.
        }
        if (session != _session || _disposed) return;
      }
      if (guestCart.isNotEmpty) {
        for (final entry in guestCart.entries) {
          final p = productById(entry.key);
          if (p != null && p.inStock)
            cart[entry.key] =
                min(p.stock, (cart[entry.key] ?? 0) + entry.value);
        }
        _cartVersion++;
        _cartDirty = true;
      }
      if (_cartDirty) await _syncCart(session);
      if (guestWishlist.isNotEmpty) {
        wishlist.addAll(guestWishlist);
        await api.saveWishlist(wishlist.toList());
      }
    } catch (e) {
      if (session == _session) error = '$e';
    }
    if (session == _session) _emit();
  }

  List<Map<String, dynamic>> _cartPayload() => cart.entries
      .map((e) => {'productId': e.key, 'quantity': e.value})
      .toList();
  Future<void> _enqueue(Future<void> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.catchError((Object _) {});
    return result;
  }

  Future<void> _syncCart(int session) => _enqueue(() async {
        if (session != _session || _disposed || !_cartDirty) return;
        final version = _cartVersion;
        await api.saveCart(_cartPayload());
        if (session == _session && version == _cartVersion) _cartDirty = false;
      });
  Future<void> addToCart(Product product, {int quantity = 1}) =>
      setQuantity(product, (cart[product.id] ?? 0) + quantity);
  Future<void> removeFromCart(Product product) => setQuantity(product, 0);
  Future<void> setQuantity(Product product, int quantity) async {
    if (quantity < 0) return;
    if (quantity > product.stock || (quantity > 0 && !product.isActive))
      throw CommerceException(
          'Only ${product.stock} available for ${product.name}.');
    final previous = Map<String, int>.from(cart);
    final wasDirty = _cartDirty;
    final version = ++_cartVersion, session = _session;
    cart = Map<String, int>.from(cart);
    if (quantity == 0) {
      cart.remove(product.id);
    } else {
      cart[product.id] = quantity;
    }
    _cartDirty = true;
    final payload = _cartPayload();
    if (!offline) error = null;
    _emit();
    if (!isSignedIn || _preview) return;
    if (offline) return;
    try {
      await _enqueue(() async {
        if (session != _session || _disposed || offline) return;
        await api.saveCart(payload);
        if (session == _session && version == _cartVersion) _cartDirty = false;
      });
    } catch (e) {
      if (session == _session) {
        if (e is CommerceException &&
            (e.statusCode == null || e.statusCode! >= 500)) {
          // Keep shopping during a temporary outage; checkout still requires
          // the live server to validate prices and stock.
          offline = true;
          error =
              'Your bag is kept for this visit. Reconnect to sync it before checkout.';
          _emit();
          return;
        }
        if (version == _cartVersion) {
          cart = previous;
          _cartDirty = wasDirty;
        }
        error = '$e';
        _emit();
      }
      rethrow;
    }
  }

  Future<void> toggleWishlist(Product product) async {
    final previous = Set<String>.from(wishlist);
    final version = ++_wishlistVersion, session = _session;
    wishlist = Set<String>.from(wishlist);
    if (!wishlist.add(product.id)) wishlist.remove(product.id);
    final payload = wishlist.toList();
    error = null;
    _emit();
    if (!isSignedIn || _preview) return;
    try {
      await _enqueue(() async {
        if (session != _session) return;
        await api.saveWishlist(payload);
      });
    } catch (e) {
      if (session == _session) {
        if (version == _wishlistVersion) wishlist = previous;
        error = '$e';
        _emit();
      }
      rethrow;
    }
  }

  Future<CustomerProfile> refreshProfile() async {
    if (_preview) return profile ?? const CustomerProfile();
    final response = await api.profile();
    profile = CustomerProfile.fromJson(
        Map<String, dynamic>.from(response['profile'] as Map));
    _emit();
    return profile!;
  }

  Future<CustomerProfile> saveProfile({
    String? username,
    String? name,
    String? contactEmail,
    String? phoneNumber,
    String? address,
  }) async {
    if (_preview)
      throw const CommerceException(
          'Profile editing is unavailable in preview mode.');
    final current = profile ?? await refreshProfile();
    final response = await api.saveProfile(
      username: username ?? current.username,
      name: name ?? current.name,
      contactEmail: contactEmail ?? current.contactEmail,
      phoneNumber: phoneNumber ?? current.phoneNumber,
      address: address ?? current.address,
    );
    profile = CustomerProfile.fromJson(
        Map<String, dynamic>.from(response['profile'] as Map));
    _emit();
    return profile!;
  }

  Future<CustomerProfile> uploadProfilePhoto(
      Uint8List bytes, String filename) async {
    final response = await api.uploadProfilePhoto(bytes, filename);
    profile = CustomerProfile.fromJson(
        Map<String, dynamic>.from(response['profile'] as Map));
    _emit();
    return profile!;
  }

  Future<CustomerProfile> removeProfilePhoto() async {
    final response = await api.deleteProfilePhoto();
    profile = CustomerProfile.fromJson(
        Map<String, dynamic>.from(response['profile'] as Map));
    _emit();
    return profile!;
  }

  Future<ShopOrder> placeOrder(
      {required String customerName,
      required String email,
      required String contactNumber,
      required String address}) async {
    if (!isSignedIn)
      throw const CommerceException(
          'Please sign in before placing your order.');
    if (_preview)
      throw const CommerceException(
          'Checkout is unavailable in preview mode.');
    // Catalog may have been cached before the backend was started. Recheck
    // the live API on checkout instead of permanently blocking this session.
    if (offline) {
      try {
        final liveCatalog = await api.catalog();
        if (_disposed) {
          throw const CommerceException('The store is no longer available.');
        }
        _readCatalog(liveCatalog);
        offline = false;
        error = null;
        _emit();
      } on CommerceException catch (e) {
        error = 'Live checkout is unavailable: $e';
        _emit();
        throw CommerceException(error!);
      } catch (_) {
        error = 'Unable to reconnect to the live store. Check that the backend is running, then try again.';
        _emit();
        throw CommerceException(error!);
      }
    }
    if (cart.isEmpty)
      throw const CommerceException('Add something to your cart first.');
    if (customerName.trim().isEmpty ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim()) ||
        address.trim().isEmpty ||
        !RegExp(r'^09\d{9}$').hasMatch(contactNumber.trim()))
      throw const CommerceException(
          'Please complete your name, address, and valid Philippine mobile number.');
    final session = _session;
    await _writes;
    if (session != _session)
      throw const CommerceException('Your sign-in changed. Please try again.');
    final submittedCart = _cartPayload();
    final body = <String, dynamic>{
      'customerName': customerName.trim(),
      'email': email.trim(),
      'contactNumber': contactNumber.trim(),
      'address': address.trim(),
      'items': submittedCart,
      'paymentMethod': 'xendit'
    };
    final fingerprint = jsonEncode(body);
    if (_checkoutFingerprint != fingerprint || _checkoutKey == null) {
      _checkoutFingerprint = fingerprint;
      final random = Random.secure();
      _checkoutKey =
          'checkout-${DateTime.now().microsecondsSinceEpoch}-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    }
    body['idempotencyKey'] = _checkoutKey;
    try {
      final response = await api.createOrder(body);
      final orderJson = Map<String, dynamic>.from(response['order'] as Map);
      if (response['paymentUrl'] is String)
        orderJson['paymentUrl'] = response['paymentUrl'];
      final order = ShopOrder.fromJson(orderJson);
      if (order.paymentMethod != 'xendit' ||
          order.paymentStatus == 'paid' ||
          order.paymentUrl.isEmpty ||
          !order.paymentUrl.startsWith('https://checkout-staging.xendit.co/') &&
              !order.paymentUrl.startsWith('https://dev.xen.to/') &&
              !order.paymentUrl.startsWith('https://xen.to/')) {
        throw const CommerceException(
            'Xendit did not return a valid Test Mode checkout link. Your bag is still here.');
      }
      if (session != _session)
        throw const CommerceException(
            'Order saved. Sign in to the original account to see its confirmation.');
      orders = [order, ...orders.where((o) => o.id != order.id)];
      _pendingXenditCart ??= Map<String, int>.from(cart);
      cart = {};
      _cartDirty = false;
      _checkoutKey = null;
      _checkoutFingerprint = null;
      _emit();
      unawaited(_refreshCatalogAfterOrder());
      return order;
    } catch (e) {
      if (session == _session) {
        error = '$e';
        _emit();
      }
      rethrow;
    }
  }

  Future<ShopOrder> refreshOrder(String orderId) async {
    if (_preview)
      throw const CommerceException(
          'Payment status checks are unavailable in preview mode.');
    final response = await api.order(orderId);
    final order =
        ShopOrder.fromJson(Map<String, dynamic>.from(response['order'] as Map));
    orders = [
      for (final saved in orders)
        if (saved.id != order.id) saved,
      order
    ];
    if ((order.paymentStatus == 'cancelled' ||
            order.paymentStatus == 'expired') &&
        _pendingXenditCart != null) {
      cart = Map<String, int>.from(_pendingXenditCart!);
      _pendingXenditCart = null;
      _cartDirty = false;
      _checkoutKey = null;
      _checkoutFingerprint = null;
    }
    error = null;
    _emit();
    return order;
  }

  Future<void> refreshOrders() async {
    if (_preview)
      throw const CommerceException(
          'Order status checks are unavailable in preview mode.');
    if (!isSignedIn) return;
    final session = _session;
    final response = await api.orders();
    if (session != _session || _disposed) return;
    orders = (response['orders'] as List? ?? [])
        .map((e) => ShopOrder.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    _emit();
    if ((response['paymentStatusRefreshFailures'] as num? ?? 0) > 0) {
      throw const CommerceException(
          'Some Xendit payments could not be verified right now. Tap Refresh to try again.');
    }
  }

  Future<ShopOrder> cancelOrder(ShopOrder order) async {
    if (_preview)
      throw const CommerceException(
          'Order cancellations are unavailable in preview mode.');
    final response = await api.cancelOrder(order.id);
    final updated =
        ShopOrder.fromJson(Map<String, dynamic>.from(response['order'] as Map));
    orders = [
      for (final saved in orders)
        if (saved.id != updated.id) saved,
      updated
    ];
    if (updated.paymentStatus == 'cancelled' && _pendingXenditCart != null) {
      cart = Map<String, int>.from(_pendingXenditCart!);
      _pendingXenditCart = null;
      _cartDirty = false;
      _checkoutKey = null;
      _checkoutFingerprint = null;
    }
    _emit();
    return updated;
  }

  Future<void> _refreshCatalogAfterOrder() async {
    try {
      _readCatalog(await api.catalog());
      _emit();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _authSubscription?.cancel();
    api.dispose();
    super.dispose();
  }
}
