import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../branding.dart';
import 'models.dart';
import 'commerce_store.dart';
import 'admin_page.dart';
import 'store_widgets.dart';
import 'shopping_pages.dart';
import 'customer_profile.dart';

enum StoreSection { home, shop, categories, wishlist, orders, profile }

class Storefront extends StatefulWidget {
  final CommerceStore? store;
  final Future<void> Function(BuildContext) onLogin;
  final StoreSection initialSection;
  final bool showCartOnOpen;
  const Storefront({super.key, this.store, required this.onLogin,
    this.initialSection = StoreSection.home, this.showCartOnOpen = false});
  @override
  State<Storefront> createState() => _StorefrontState();
}

class _StorefrontState extends State<Storefront> {
  late final CommerceStore store;
  StoreSection section = StoreSection.home;
  final searchController = TextEditingController();
  final searchFocusNode = FocusNode();
  final scrollController = ScrollController();
  String category = 'all';
  String sort = 'Featured';
  double priceLimit = 10000;
  int visibleCount = 8;
  bool drawerBusy = false;
  Timer? _ordersRefreshTimer;
  bool _refreshingOrders = false;
  @override
  void initState() {
    super.initState();
    store = widget.store ?? CommerceStore();
    section = widget.initialSection;
    if (!store.catalogReady && !store.loading) store.load();
    if (widget.showCartOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) openCart(); });
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    searchFocusNode.dispose();
    scrollController.dispose();
    _ordersRefreshTimer?.cancel();
    if (widget.store == null) store.dispose();
    super.dispose();
  }

  void navigate(StoreSection target) {
    if (target != StoreSection.orders) _ordersRefreshTimer?.cancel();
    setState(() => section = target);
    if (scrollController.hasClients) scrollController.jumpTo(0);
  }

  Future<void> openOrders() async {
    if (!store.isSignedIn) await widget.onLogin(context);
    if (!store.isSignedIn || !mounted) return;
    navigate(StoreSection.orders);
    await _refreshOrders();
    _ordersRefreshTimer?.cancel();
    _ordersRefreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_refreshOrders(showError: false)),
    );
  }

  Future<void> _refreshOrders({bool showError = true}) async {
    if (!mounted || _refreshingOrders) return;
    _refreshingOrders = true;
    try {
      await store.refreshOrders();
    } catch (error) {
      if (showError) notify('Could not verify payment status: $error');
    } finally {
      _refreshingOrders = false;
    }
  }

  void clearFilters() {
    setState(() {
      searchController.clear();
      category = 'all';
      priceLimit = 10000;
      sort = 'Featured';
      visibleCount = 8;
    });
  }

  void notify(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        duration: const Duration(seconds: 3)));
  }

  Future<void> add(Product p, {int quantity = 1}) async {
    try {
      await store.addToCart(p, quantity: quantity);
      notify('${p.name} added to your bag.');
    } catch (e) {
      notify('$e');
    }
  }

  Future<void> buyNow(Product p, {int quantity = 1}) async {
    try {
      await store.addToCart(p, quantity: quantity);
      if (mounted) await checkout();
    } catch (e) {
      notify('$e');
    }
  }

  Future<void> save(Product p) async {
    if (!store.isSignedIn) {
      await widget.onLogin(context);
      if (!store.isSignedIn) return;
    }
    try {
      await store.toggleWishlist(p);
    } catch (e) {
      notify('$e');
    }
  }

  Future<void> openProduct(Product p) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ProductDetailsPage(
            product: p,
            store: store,
            onAdd: add,
            onBuyNow: buyNow,
            onSave: save,
            onCheckout: checkout,
            onProduct: openProduct)));
  }

  Future<void> checkout() async {
    if (store.cartCount == 0) return;
    if (!store.isSignedIn) {
      await widget.onLogin(context);
      if (!store.isSignedIn || !mounted) return;
    }
    if (mounted) {
      await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => CheckoutPage(store: store)));
    }
  }

  void chooseCategory(String id) {
    setState(() {
      category = id;
      section = StoreSection.shop;
      visibleCount = 8;
    });
    if (scrollController.hasClients) scrollController.jumpTo(0);
  }

  Future<void> privatePage(StoreSection target) async {
    if (target == StoreSection.orders) {
      await openOrders();
      return;
    }
    if (!store.isSignedIn) await widget.onLogin(context);
    if (store.isSignedIn && mounted) {
      if (mounted) navigate(target);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 1000;
        return Scaffold(
            backgroundColor: paper,
            appBar: PreferredSize(
                preferredSize: Size.fromHeight(wide ? 112 : 101),
                child: Column(children: [
                  Container(
                      height: 29,
                      color: cream,
                      alignment: Alignment.center,
                      child: const Text(
                          'YOUR SPACE. YOUR TOOLS. YOUR STORY.   •   FREE SHIPPING OVER ₱1,000',
                          style: TextStyle(fontSize: 8, letterSpacing: 1.4))),
                  Container(
                      height: wide ? 83 : 72,
                      decoration: const BoxDecoration(
                          color: paper,
                          border: Border(bottom: BorderSide(color: border))),
                      padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 16),
                      child: Row(children: [
                        if (!wide)
                          PopupMenuButton<StoreSection>(
                              tooltip: 'Open navigation',
                              icon: const Icon(Icons.menu, size: 21),
                              onSelected: (s) {
                                if (s == StoreSection.orders ||
                                    s == StoreSection.profile ||
                                    s == StoreSection.wishlist) {
                                  privatePage(s);
                                } else {
                                  navigate(s);
                                }
                              },
                              itemBuilder: (_) => [
                                    for (final entry in {
                                      StoreSection.home: 'Home',
                                      StoreSection.shop: 'Shop',
                                      StoreSection.categories: 'Categories',
                                      StoreSection.orders: 'My Orders',
                                      StoreSection.wishlist: 'Wishlist',
                                      StoreSection.profile: 'My Account'
                                    }.entries)
                                      PopupMenuItem(
                                          value: entry.key,
                                          child: Text(entry.value))
                                  ]),
                        InkWell(
                            onTap: () => navigate(StoreSection.home),
                            child: SizedBox(
                                width: wide ? 215 : 162,
                                child: const FittedBox(
                                    alignment: Alignment.centerLeft,
                                    fit: BoxFit.scaleDown,
                                    child: BrandLogo()))),
                        const Spacer(),
                        if (wide) ...[
                          nav('Home', StoreSection.home),
                          nav('Shop', StoreSection.shop),
                          nav('Categories', StoreSection.categories),
                          nav('My Orders', StoreSection.orders, private: true),
                          const SizedBox(width: 22)
                        ],
                        IconButton(
                            tooltip: 'Search products',
                            onPressed: () {
                              navigate(StoreSection.shop);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) searchFocusNode.requestFocus();
                              });
                            },
                            icon: const Icon(Icons.search, size: 21)),
                        if (wide)
                          IconButton(
                              tooltip: 'Wishlist',
                              onPressed: () =>
                                  privatePage(StoreSection.wishlist),
                              icon: Badge(
                                  isLabelVisible: store.wishlist.isNotEmpty,
                                  label: Text('${store.wishlist.length}'),
                                  child: const Icon(Icons.favorite_border,
                                      size: 20))),
                        IconButton(
                            tooltip: 'Shopping cart',
                            onPressed: openCart,
                            icon: Badge(
                                isLabelVisible: store.cartCount > 0,
                                label: Text('${store.cartCount}'),
                                backgroundColor: red,
                                child: const Icon(Icons.shopping_bag_outlined,
                                    size: 21))),
                        if (wide)
                          IconButton(
                              tooltip: 'Your account',
                              onPressed: () =>
                                  privatePage(StoreSection.profile),
                              icon: const Icon(Icons.person_outline, size: 22))
                      ]))
                ])),
            body: SelectionArea(
                child: ListView(controller: scrollController, children: [
              if (store.error != null)
                Container(
                    color: const Color(0xFFF4E8DD),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    child: Row(children: [
                      Expanded(
                          child: Text(
                              store.offline
                                  ? 'You are browsing our saved collection. Connect to the shop server to sync your bag and place an order.'
                                  : store.error!,
                              style:
                                  const TextStyle(fontSize: 11, height: 1.5))),
                      TextButton(
                          onPressed: store.refresh, child: const Text('Retry'))
                    ])),
              Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1240),
                      child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: wide ? 36 : 18, vertical: 30),
                          child: switch (section) {
                            StoreSection.home => home(),
                            StoreSection.shop => shop(),
                            StoreSection.categories => categoriesPage(),
                            StoreSection.wishlist => wishlist(),
                            StoreSection.orders => OrdersSection(
                                store: store,
                                onRefresh: () =>
                                    unawaited(_refreshOrders()),
                                onShop: () => navigate(StoreSection.shop)),
                            StoreSection.profile => profile()
                          }))),
              footer(),
            ])));
      });

  Widget nav(String label, StoreSection target, {bool private = false}) =>
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextButton(
              onPressed: () => private ? privatePage(target) : navigate(target),
              style: TextButton.styleFrom(
                  foregroundColor: section == target ? red : ink),
              child: Text(label, style: const TextStyle(fontSize: 12))));

  Widget grid(List<Product> products) => ProductGrid(
      products: products,
      wishlist: store.wishlist,
      onOpen: openProduct,
      onAdd: add,
      onWishlist: save);

  Widget home() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, c) {
          final compact = c.maxWidth < 920;
          final tablet = c.maxWidth < 1000;
          final copy = Padding(
              padding: EdgeInsets.all(compact
                  ? 26
                  : tablet
                      ? 24
                      : 42),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Eyebrow('The Ibasho Collection'),
                    const SizedBox(height: 22),
                    Text('Little essentials.\nBig ideas.',
                        style: serif.copyWith(
                            fontSize: compact
                                ? 38
                                : tablet
                                    ? 34
                                    : 46,
                            height: 1.15,
                            letterSpacing: -1.5)),
                    const SizedBox(height: 20),
                    const Text(
                        'Discover thoughtfully selected stationery for studying, organizing, and creating.',
                        style:
                            TextStyle(fontSize: 13, color: muted, height: 1.9)),
                    const SizedBox(height: 26),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      StoreButton('SHOP COLLECTION',
                          onPressed: () => navigate(StoreSection.shop),
                          icon: Icons.arrow_forward),
                      StoreButton('EXPLORE CATEGORIES',
                          outline: true,
                          onPressed: () => navigate(StoreSection.categories))
                    ])
                  ]));
          const photo = ProductPhoto(
              'assets/images/products/minimalist-a5-notebook.jpg',
              label: 'Notebook, pencil, and stationery arranged on a desk',
              fit: BoxFit.cover,
              padding: 0);
          return Container(
              decoration: BoxDecoration(
                  color: cream, border: Border.all(color: border)),
              child: compact
                  ? Column(children: [
                      copy,
                      const SizedBox(
                          height: 230, width: double.infinity, child: photo)
                    ])
                  : SizedBox(
                      height: tablet ? 420 : 450,
                      child: Row(children: [
                        Expanded(flex: 11, child: copy),
                        const Expanded(flex: 10, child: photo)
                      ])));
        }),
        const SizedBox(height: 20),
        Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 18,
            runSpacing: 12,
            children: [
              trust(Icons.local_shipping_outlined,
                  'Carefully packed, delivered to you'),
              trust(Icons.edit_outlined, 'Made for everyday inspiration'),
              trust(Icons.payments_outlined, 'Cash on Delivery available')
            ]),
        const SizedBox(height: 48),
        SectionTitle('Find your everyday favorites.',
            subtitle: 'A little order. A little color. A lot of possibility.',
            action: 'All categories',
            onAction: () => navigate(StoreSection.categories)),
        categoryCards(),
        const SizedBox(height: 48),
        SectionTitle('Considered essentials.',
            subtitle: 'Thoughtful tools for whatever comes next.',
            action: 'View all products',
            onAction: () => navigate(StoreSection.shop)),
        if (store.loading && store.products.isEmpty)
          const CatalogSkeleton()
        else
          grid(store.products.where((p) => p.featured).take(4).toList()),
        const SizedBox(height: 48),
        SectionTitle('Fresh on the desk.',
            subtitle: 'Meet the newest additions to your creative routine.',
            action: 'New arrivals', onAction: () {
          setState(() {
            sort = 'Newest';
          });
          navigate(StoreSection.shop);
        }),
        if (store.loading && store.products.isEmpty)
          const CatalogSkeleton()
        else
          grid(store.products.where((p) => p.isNew).take(4).toList()),
        const SizedBox(height: 52),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 45),
            decoration: const BoxDecoration(
                color: cream,
                border: Border(
                    top: BorderSide(color: border),
                    bottom: BorderSide(color: border))),
            child: Column(children: [
              const Eyebrow('Small tools. Meaningful moments.'),
              const SizedBox(height: 18),
              Text('Your space to create.',
                  textAlign: TextAlign.center,
                  style: serif.copyWith(fontSize: 32)),
              const SizedBox(height: 18),
              const Text(
                  'At IBASHO STATIONERY, we believe the smallest tools can inspire the biggest ideas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 13, height: 1.8)),
              const SizedBox(height: 12),
              Text('Your Space. Your Tools. Your Story.',
                  style: hand.copyWith(fontSize: 25))
            ])),
      ]);

  Widget trust(IconData icon, String label) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Row(children: [
          Icon(icon, size: 17, color: muted),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(color: muted, fontSize: 10),
            ),
          )
        ]),
      );
  String categoryPhoto(String id) => 'assets/images/products/${switch (id) {
        'notebooks' => 'minimalist-a5-notebook',
        'writing-essentials' => 'gel-pen-set',
        'art-supplies' => 'pastel-highlighters',
        _ => 'sticky-notes'
      }}.jpg';
  Widget categoryCards() => LayoutBuilder(builder: (context, c) {
        final count = c.maxWidth < 680 ? 2 : 4;
        final gap = c.maxWidth < 680 ? 12.0 : 20.0;
        final width = (c.maxWidth - gap * (count - 1)) / count;
        final entries = store.categories;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final cat in entries)
            SizedBox(
                width: width,
                child: InkWell(
                    onTap: () => chooseCategory(cat.id),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(
                              aspectRatio: 1.65,
                              child: ProductPhoto(categoryPhoto(cat.id),
                                  label: cat.name,
                                  fit: BoxFit.cover,
                                  padding: 0)),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                                child: Text(cat.name,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600))),
                            const Icon(Icons.arrow_forward,
                                size: 15, color: red)
                          ])
                        ])))
        ]);
      });
  Widget categoriesPage() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Eyebrow('A place for everything'),
        const SizedBox(height: 18),
        const SectionTitle('Shop by category.',
            subtitle: 'Find the right tools for your next chapter.'),
        categoryCards(),
        const SizedBox(height: 70)
      ]);

  Widget shop() {
    final maxPrice = store.products
        .fold<double>(300, (v, p) => math.max(v, p.price))
        .ceilToDouble();
    final limit = math.min(priceLimit, maxPrice);
    final list = store.products
        .where((p) =>
            (category == 'all' || p.categoryId == category) &&
            p.name
                .toLowerCase()
                .contains(searchController.text.trim().toLowerCase()) &&
            p.price <= limit)
        .toList();
    switch (sort) {
      case 'Price: low to high':
        list.sort((a, b) => a.price.compareTo(b.price));
      case 'Price: high to low':
        list.sort((a, b) => b.price.compareTo(a.price));
      case 'Name A–Z':
        list.sort((a, b) => a.name.compareTo(b.name));
      case 'Newest':
        list.sort((a, b) {
          final aDate = a.createdAt;
          final bDate = b.createdAt;
          if (aDate != null || bDate != null) {
            return (bDate ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(aDate ?? DateTime.fromMillisecondsSinceEpoch(0));
          }
          return (b.isNew ? 1 : 0).compareTo(a.isNew ? 1 : 0);
        });
      default:
        list.sort((a, b) => (b.featured ? 1 : 0).compareTo(a.featured ? 1 : 0));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Eyebrow('Thoughtfully selected. Ready for you.'),
      const SizedBox(height: 18),
      const SectionTitle('The collection.',
          subtitle:
              'Good things for your desk, your bag, and your next big idea.'),
      LayoutBuilder(
          builder: (context, c) => Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                        width: c.maxWidth < 600 ? c.maxWidth : 350,
                        child: TextField(
                            controller: searchController,
                            focusNode: searchFocusNode,
                            onChanged: (_) => setState(() => visibleCount = 8),
                            decoration: const InputDecoration(
                                hintText: 'Search the collection',
                                prefixIcon: Icon(Icons.search, size: 19),
                                contentPadding: EdgeInsets.all(15)))),
                    SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<String>(
                            initialValue: sort,
                            decoration: const InputDecoration(
                                labelText: 'Sort by',
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12)),
                            isExpanded: true,
                            items: [
                              for (final s in [
                                'Featured',
                                'Newest',
                                'Price: low to high',
                                'Price: high to low',
                                'Name A–Z'
                              ])
                                DropdownMenuItem(
                                    value: s,
                                    child: Text(s,
                                        style: const TextStyle(fontSize: 12)))
                            ],
                            onChanged: (v) => setState(() {
                                  sort = v!;
                                  visibleCount = 8;
                                }))),
                    SizedBox(
                        width: c.maxWidth < 600 ? c.maxWidth : 230,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Maximum price: ${pesos(limit)}',
                                  style: const TextStyle(
                                      fontSize: 11, color: muted)),
                              Slider(
                                  value: limit,
                                  min: 0,
                                  max: maxPrice,
                                  divisions: maxPrice.toInt(),
                                  activeColor: red,
                                  onChanged: (v) => setState(() {
                                        priceLimit = v;
                                        visibleCount = 8;
                                      }))
                            ]))
                  ])),
      const SizedBox(height: 22),
      Wrap(spacing: 8, runSpacing: 8, children: [
        filterChip('All supplies', 'all'),
        for (final cat in store.categories) filterChip(cat.name, cat.id)
      ]),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
            child: Text('${list.length} thoughtful essentials',
                style: const TextStyle(color: muted, fontSize: 11))),
        TextButton(
            onPressed: clearFilters,
            child: const Text('Clear filters',
                style: TextStyle(color: red, fontSize: 11)))
      ]),
      const Divider(color: border),
      const SizedBox(height: 18),
      if (store.loading && store.products.isEmpty)
        const CatalogSkeleton()
      else if (list.isEmpty)
        EmptyState(
            title: 'A fresh search?',
            description: 'Try another name, category, or price range.',
            action: 'CLEAR FILTERS',
            onAction: clearFilters)
      else
        grid(list.take(visibleCount).toList()),
      if (list.length > visibleCount)
        Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Center(
                child: StoreButton('LOAD MORE PRODUCTS',
                    outline: true,
                    onPressed: () => setState(() => visibleCount += 8)))),
      const SizedBox(height: 40)
    ]);
  }

  Widget filterChip(String name, String id) => ChoiceChip(
      label: Text(name,
          style: TextStyle(fontSize: 11, color: category == id ? paper : ink)),
      selected: category == id,
      selectedColor: ink,
      backgroundColor: paper,
      showCheckmark: false,
      shape: const RoundedRectangleBorder(side: BorderSide(color: border)),
      onSelected: (_) => setState(() {
            category = id;
            visibleCount = 8;
          }));

  Widget wishlist() {
    final saved =
        store.products.where((p) => store.wishlist.contains(p.id)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Eyebrow('Keep the things you love close'),
      const SizedBox(height: 18),
      SectionTitle('Your wishlist.',
          subtitle: '${saved.length} little things to come back to.'),
      if (saved.isEmpty)
        EmptyState(
            title: 'Room for your favorites.',
            description: 'Tap a heart on any product to save it here.',
            action: 'EXPLORE THE COLLECTION',
            onAction: () => navigate(StoreSection.shop))
      else
        grid(saved),
      const SizedBox(height: 40)
    ]);
  }

  Widget profile() {
    final user = Supabase.instance.client.auth.currentUser;
    final savedProfile = store.profile;
    final name = savedProfile?.name.trim().isNotEmpty == true
        ? savedProfile!.name
        : user?.userMetadata?['full_name']?.toString()?.trim().isNotEmpty == true
        ? user!.userMetadata!['full_name'].toString()
        : user?.email?.split('@').first ?? 'Creator';
    final saved = store.products
        .where((p) => store.wishlist.contains(p.id))
        .take(4)
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
          color: beige,
          padding: const EdgeInsets.all(30),
          child: LayoutBuilder(
              builder: (context, c) => Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Eyebrow('Chapter 04 • Your Ibasho'),
                          const SizedBox(height: 18),
                          Text('Welcome back,',
                              style: serif.copyWith(
                                  fontSize: c.maxWidth > 700 ? 40 : 28)),
                          Text('$name.',
                              style: hand.copyWith(
                                  fontSize: c.maxWidth > 700 ? 42 : 32)),
                          const SizedBox(height: 12),
                          const Text(
                              'Your quiet corner to create. Pick up where inspiration left off.',
                              style: TextStyle(
                                  fontSize: 12, color: muted, height: 1.7)),
                          const SizedBox(height: 20),
                          StoreButton('CONTINUE SHOPPING',
                              onPressed: () => navigate(StoreSection.shop))
                        ])),
                    if (c.maxWidth > 700)
                      const Speech('A place where\nyour ideas belong.')
                  ]))),
      const SizedBox(height: 20),
      CustomerProfileCard(store: store),
      const SizedBox(height: 38),
      Wrap(spacing: 18, runSpacing: 18, children: [
        accountTile(
            '01  YOUR ORDERS',
            '${store.orders.length} orders',
            'Follow the journey of your essentials.',
            () => unawaited(openOrders())),
        accountTile(
            '02  YOUR WISHLIST',
            '${store.wishlist.length} favorites',
            'The little things you have your eye on.',
            () => navigate(StoreSection.wishlist)),
        accountTile('03  YOUR ACCOUNT',
            savedProfile?.username.isNotEmpty == true
                ? '@${savedProfile!.username}'
                : user?.email ?? 'Your account',
            'Signed in securely with your IBASHO account.', null)
      ]),
      const SizedBox(height: 35),
      if (store.orders.isNotEmpty) ...[
        SectionTitle('Your recent order.',
            action: 'All orders',
            onAction: () => unawaited(openOrders())),
        OrderSummaryCard(order: store.orders.first)
      ],
      const SizedBox(height: 25),
      if (saved.isNotEmpty) ...[
        const SectionTitle('Saved for a little later.'),
        grid(saved),
        const SizedBox(height: 35)
      ],
      const SectionTitle('A little inspiration for you.'),
      grid(store.products.where((p) => p.featured).take(4).toList()),
      const SizedBox(height: 35),
      Wrap(spacing: 15, children: [
        StoreButton('SIGN OUT', outline: true, onPressed: () async {
          await Supabase.instance.client.auth.signOut();
          navigate(StoreSection.home);
        }),
        if (store.isAdmin)
          StoreButton('OPEN ADMIN',
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => AdminPage(store: store))))
      ])
    ]);
  }

  Widget accountTile(
          String title, String value, String detail, VoidCallback? onTap) =>
      SizedBox(
          width: 330,
          child: InkWell(
              onTap: onTap,
              child: Container(
                  height: 155,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                      border: Border.all(color: border), color: paper),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Eyebrow(title),
                        const SizedBox(height: 20),
                        Text(value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        Text(detail,
                            style: const TextStyle(fontSize: 11, color: muted))
                      ]))));

  void openCart() {
    showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Close shopping cart',
        barrierColor: Colors.black38,
        transitionDuration: motion(context),
        transitionBuilder: (_, animation, __, child) => SlideTransition(
            position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child),
        pageBuilder: (dialogContext, _, __) => Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
                width: math.min(MediaQuery.sizeOf(context).width, 460),
                child: Material(
                    color: paper,
                    child: SafeArea(
                        child: AnimatedBuilder(
                            animation: store,
                            builder: (context, _) => Column(children: [
                                  Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          24, 20, 12, 12),
                                      child: Row(children: [
                                        Expanded(
                                            child: Text('Your shopping bag',
                                                style: serif.copyWith(
                                                    fontSize: 24))),
                                        IconButton(
                                            tooltip: 'Close bag',
                                            onPressed: () =>
                                                Navigator.pop(dialogContext),
                                            icon: const Icon(Icons.close))
                                      ])),
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24),
                                      child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                              '${store.cartCount} carefully chosen essentials',
                                              style: const TextStyle(
                                                  color: muted,
                                                  fontSize: 12)))),
                                  const SizedBox(height: 15),
                                  const Divider(color: border),
                                  Expanded(
                                      child: store.cart.isEmpty
                                          ? Padding(
                                              padding: const EdgeInsets.all(24),
                                              child: EmptyState(
                                                  title:
                                                      'A little room for ideas.',
                                                  description:
                                                      'Your shopping bag is waiting for its first essential.',
                                                  action: 'CONTINUE SHOPPING',
                                                  onAction: () {
                                                    Navigator.pop(
                                                        dialogContext);
                                                    navigate(StoreSection.shop);
                                                  }))
                                          : ListView(
                                              padding: const EdgeInsets.all(20),
                                              children: [
                                                  for (final entry
                                                      in store.cart.entries)
                                                    if (store.products.any(
                                                        (p) =>
                                                            p.id == entry.key))
                                                      CartLine(
                                                          product: store
                                                              .products
                                                              .firstWhere((p) =>
                                                                  p.id ==
                                                                  entry.key),
                                                          quantity: entry.value,
                                                          onQuantity:
                                                              (q) async {
                                                            try {
                                                              await store.setQuantity(
                                                                  store.products
                                                                      .firstWhere((p) =>
                                                                          p.id ==
                                                                          entry
                                                                              .key),
                                                                  q);
                                                            } catch (e) {
                                                              notify('$e');
                                                            }
                                                          })
                                                ])),
                                  if (store.cart.isNotEmpty)
                                    Container(
                                        padding: const EdgeInsets.all(24),
                                        decoration: const BoxDecoration(
                                            border: Border(
                                                top:
                                                    BorderSide(color: border))),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              moneyRow(
                                                  'Subtotal', store.subtotal),
                                              const SizedBox(height: 9),
                                              moneyRow('Shipping',
                                                  store.shippingFee),
                                              const Padding(
                                                  padding: EdgeInsets.symmetric(
                                                      vertical: 10),
                                                  child:
                                                      Divider(color: border)),
                                              moneyRow('Total', store.total,
                                                  bold: true),
                                              const SizedBox(height: 18),
                                              StoreButton('PROCEED TO CHECKOUT',
                                                  onPressed: () {
                                                Navigator.pop(dialogContext);
                                                checkout();
                                              }, icon: Icons.arrow_forward),
                                              TextButton(
                                                  onPressed: () {
                                                    Navigator.pop(
                                                        dialogContext);
                                                    navigate(StoreSection.shop);
                                                  },
                                                  child: const Text(
                                                      'Continue shopping',
                                                      style: TextStyle(
                                                          color: muted,
                                                          fontSize: 12)))
                                            ]))
                                ])))))));
  }

  Widget footer() => Container(
      margin: const EdgeInsets.only(top: 35),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 35),
      decoration: const BoxDecoration(
          color: cream, border: Border(top: BorderSide(color: border))),
      child: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1168),
              child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 24,
                  spacing: 32,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const BrandLogo(),
                    const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Your Space. Your Tools. Your Story.',
                              style: TextStyle(fontSize: 12)),
                          SizedBox(height: 9),
                          Text(
                              'Thoughtful stationery for everyday inspiration.',
                              style: TextStyle(color: muted, fontSize: 10))
                        ]),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextButton(
                              onPressed: () => navigate(StoreSection.shop),
                              child: const Text('Shop the collection',
                                  style: TextStyle(fontSize: 11, color: ink))),
                          const Text('© 2026 IBASHO STATIONERY',
                              style: TextStyle(
                                  color: muted, fontSize: 9, letterSpacing: 1))
                        ])
                  ]))));
}
