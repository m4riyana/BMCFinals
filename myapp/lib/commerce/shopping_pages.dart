import 'dart:async';
import 'package:flutter/material.dart';

import '../branding.dart';
import 'commerce_store.dart';
import 'models.dart';
import '../services/payment_service.dart';
import 'store_widgets.dart';

class ProductDetailsPage extends StatefulWidget {
  final Product product;
  final CommerceStore store;
  final Future<void> Function(Product, {int quantity}) onAdd;
  final Future<void> Function(Product, {int quantity}) onBuyNow;
  final Future<void> Function(Product) onSave;
  final Future<void> Function() onCheckout;
  final Future<void> Function(Product) onProduct;

  const ProductDetailsPage({
    super.key,
    required this.product,
    required this.store,
    required this.onAdd,
    required this.onBuyNow,
    required this.onSave,
    required this.onCheckout,
    required this.onProduct,
  });

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage> {
  late String _selectedImage;
  int _quantity = 1;

  List<String> get _images =>
      {widget.product.imagePath, ...widget.product.images}.toList();

  @override
  void initState() {
    super.initState();
    _selectedImage = widget.product.imagePath;
  }

  @override
  void didUpdateWidget(covariant ProductDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id) {
      _selectedImage = widget.product.imagePath;
      _quantity = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final related = widget.store.products
        .where((item) =>
            item.id != product.id && item.categoryId == product.categoryId)
        .take(4)
        .toList();
    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(
        title: Text(product.name),
        actions: [
          AnimatedBuilder(
            animation: widget.store,
            builder: (context, _) {
              final saved = widget.store.wishlist.contains(product.id);
              return IconButton(
                tooltip: saved ? 'Remove from wishlist' : 'Save to wishlist',
                onPressed: () => widget.onSave(product),
                icon: Icon(
                  saved ? Icons.favorite : Icons.favorite_border,
                  color: saved ? red : ink,
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: widget.store,
            builder: (context, _) => IconButton(
              tooltip: 'Shopping cart',
              onPressed: widget.onCheckout,
              icon: Badge(
                isLabelVisible: widget.store.cartCount > 0,
                label: Text('${widget.store.cartCount}'),
                child: const Icon(Icons.shopping_bag_outlined),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 680;
                      final gallery = Column(
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: ProductPhoto(
                              _selectedImage,
                              label: product.name,
                              padding: 0,
                            ),
                          ),
                          if (_images.length > 1) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (final image in _images)
                                  InkWell(
                                    onTap: () =>
                                        setState(() => _selectedImage = image),
                                    child: Container(
                                      width: 66,
                                      height: 66,
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: image == _selectedImage
                                              ? red
                                              : border,
                                        ),
                                      ),
                                      child: ProductPhoto(
                                        image,
                                        label: '${product.name} view',
                                        padding: 4,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      );
                      final details = Padding(
                        padding: EdgeInsets.all(compact ? 8 : 36),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Eyebrow(product.categoryName),
                            const SizedBox(height: 18),
                            Text(
                              product.name,
                              style:
                                  serif.copyWith(fontSize: compact ? 28 : 36),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              pesos(product.price),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              product.description,
                              style: const TextStyle(
                                color: muted,
                                height: 1.8,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              product.inStock
                                  ? '${product.stock} in stock'
                                  : 'Currently out of stock',
                              style: TextStyle(
                                color: product.inStock ? muted : red,
                                fontSize: 12,
                              ),
                            ),
                            if (product.photoNote.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                product.photoNote,
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 10,
                                  height: 1.5,
                                ),
                              ),
                            ],
                            if (product.inStock) ...[
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  const Text(
                                    'Quantity',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(width: 14),
                                  IconButton(
                                    tooltip: 'Decrease quantity',
                                    onPressed: _quantity > 1
                                        ? () => setState(() => _quantity--)
                                        : null,
                                    icon: const Icon(Icons.remove),
                                  ),
                                  Text('$_quantity'),
                                  IconButton(
                                    tooltip: 'Increase quantity',
                                    onPressed: _quantity < product.stock
                                        ? () => setState(() => _quantity++)
                                        : null,
                                    icon: const Icon(Icons.add),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 22),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                StoreButton(
                                  'ADD TO BAG',
                                  onPressed: product.inStock
                                      ? () => widget.onAdd(
                                            product,
                                            quantity: _quantity,
                                          )
                                      : null,
                                  icon: Icons.shopping_bag_outlined,
                                ),
                                if (product.inStock)
                                  StoreButton(
                                    'BUY NOW',
                                    outline: true,
                                    onPressed: () => widget.onBuyNow(
                                      product,
                                      quantity: _quantity,
                                    ),
                                    icon: Icons.arrow_forward,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            gallery,
                            const SizedBox(height: 24),
                            details
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: gallery),
                          Expanded(child: details),
                        ],
                      );
                    },
                  ),
                  if (product.details.isNotEmpty) ...[
                    const SizedBox(height: 36),
                    const SectionTitle('The little details.'),
                    ...product.details.map(
                      (detail) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check, color: red, size: 18),
                            const SizedBox(width: 10),
                            Expanded(child: Text(detail)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (related.isNotEmpty) ...[
                    const SizedBox(height: 48),
                    const SectionTitle('You may also like.'),
                    ProductGrid(
                      products: related,
                      wishlist: widget.store.wishlist,
                      onOpen: widget.onProduct,
                      onAdd: (item) => widget.onAdd(item),
                      onWishlist: widget.onSave,
                    ),
                  ],
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CheckoutPage extends StatefulWidget {
  final CommerceStore store;

  const CheckoutPage({super.key, required this.store});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  bool _saveDetails = true;
  bool _busy = false;
  bool _checkingStatus = false;
  Timer? _paymentStatusTimer;
  String? _error;
  ShopOrder? _order;

  @override
  void initState() {
    super.initState();
    final profile = widget.store.profile;
    _nameController.text = profile?.name ?? '';
    _emailController.text = profile?.contactEmail.isNotEmpty == true
        ? profile!.contactEmail
        : widget.store.userEmail ?? '';
    _phoneController.text = profile?.phoneNumber ?? '';
    _addressController.text = profile?.address ?? '';
    if (profile == null && widget.store.isSignedIn) {
      unawaited(_loadSavedProfile());
    }
  }

  Future<void> _loadSavedProfile() async {
    try {
      final profile = await widget.store.refreshProfile();
      if (!mounted) return;
      setState(() {
        if (_nameController.text.isEmpty) _nameController.text = profile.name;
        if (_emailController.text.isEmpty) {
          _emailController.text = profile.contactEmail.isNotEmpty
              ? profile.contactEmail
              : profile.email;
        }
        if (_phoneController.text.isEmpty) {
          _phoneController.text = profile.phoneNumber;
        }
        if (_addressController.text.isEmpty) {
          _addressController.text = profile.address;
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _paymentStatusTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_saveDetails) {
        await widget.store.saveProfile(
          name: _nameController.text.trim(),
          contactEmail: _emailController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          address: _addressController.text.trim(),
        );
      }
      final order = await widget.store.placeOrder(
        customerName: _nameController.text,
        email: _emailController.text,
        contactNumber: _phoneController.text,
        address: _addressController.text,
      );
      if (mounted) {
        setState(() => _order = order);
        _startPaymentStatusSync();
      }
      await _openPayment(order);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPayment(ShopOrder order) async {
    if (order.paymentUrl.isEmpty) {
      if (mounted)
        setState(() => _error =
            'The secure payment link is unavailable. Your order is still unpaid; return to checkout and try again.');
      return;
    }
    try {
      await PaymentService().openPayment(order.paymentUrl);
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Could not open the Xendit checkout tab. Return to checkout to try again; this order remains unpaid.');
    }
  }

  // Poll the server rather than assuming a payment is complete when the
  // external Xendit tab opens or closes. The backend verifies the payment.
  void _startPaymentStatusSync() {
    _paymentStatusTimer?.cancel();
    if (_order?.paymentStatus == 'paid' ||
        _order?.paymentStatus == 'cancelled' ||
        _order?.paymentStatus == 'expired') return;
    _paymentStatusTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_checkPayment()),
    );
    unawaited(_checkPayment());
  }

  Future<void> _checkPayment() async {
    final order = _order;
    if (!mounted || order == null || _checkingStatus) return;
    if (order.paymentStatus == 'paid' ||
        order.paymentStatus == 'cancelled' ||
        order.paymentStatus == 'expired') {
      _paymentStatusTimer?.cancel();
      return;
    }
    _checkingStatus = true;
    try {
      final updated = await widget.store.refreshOrder(order.id);
      if (!mounted || _order?.id != order.id) return;
      setState(() {
        _order = updated;
        _error = null;
      });
      if (updated.paymentStatus == 'paid' ||
          updated.paymentStatus == 'cancelled' ||
          updated.paymentStatus == 'expired') {
        _paymentStatusTimer?.cancel();
      }
    } catch (_) {
      // A temporary network outage must not fabricate a paid result.
      // Keep checking while the payment remains pending.
    } finally {
      _checkingStatus = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      backgroundColor: paper,
      appBar:
          AppBar(title: Text(order == null ? 'Checkout' : 'Payment status')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (order != null) ...[
                Panel(
                  color: beige,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow(order.paymentStatus == 'paid'
                          ? 'Payment confirmed'
                          : order.paymentStatus == 'cancelled' ||
                                  order.paymentStatus == 'expired'
                              ? 'Payment not completed'
                              : 'Order saved · awaiting Xendit'),
                      const SizedBox(height: 16),
                      Text(
                          order.paymentStatus == 'paid'
                              ? 'Thank you for your payment.'
                              : order.paymentStatus == 'cancelled' ||
                                      order.paymentStatus == 'expired'
                                  ? 'This payment session has ended.'
                                  : 'Your order is pending payment.',
                          style: serif.copyWith(fontSize: 27)),
                      const SizedBox(height: 12),
                      Text('Order ${order.reference}'),
                      const SizedBox(height: 8),
                      Text(
                        'Total ${pesos(order.total)} · ${order.paymentStatus.toUpperCase()}',
                        style: const TextStyle(color: muted),
                      ),
                      const SizedBox(height: 16),
                      if (order.paymentStatus != 'paid' &&
                          order.paymentStatus != 'cancelled' &&
                          order.paymentStatus != 'expired') ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Waiting for Xendit payment confirmation. This page updates automatically once payment is verified.',
                          style: TextStyle(color: muted, fontSize: 12, height: 1.6),
                        ),
                      ],
                      if (order.paymentStatus == 'failed') ...[
                        const SizedBox(height: 12),
                        const Text(
                            'The last attempt did not complete. You can retry the secure payment link.',
                            style: TextStyle(
                                color: muted, fontSize: 12, height: 1.6)),
                      ],
                      if (order.paymentStatus == 'paid') ...[
                        const SizedBox(height: 12),
                        const Text(
                            'Xendit verified your payment. Your order is confirmed.',
                            style: TextStyle(
                                color: muted, fontSize: 12, height: 1.6)),
                      ],
                      if (order.paymentStatus == 'cancelled' ||
                          order.paymentStatus == 'expired') ...[
                        const SizedBox(height: 12),
                        const Text(
                            'The order was cancelled and its stock returned to the shop.',
                            style: TextStyle(
                                color: muted, fontSize: 12, height: 1.6)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                OrderSummaryCard(order: order),
              ] else ...[
                const Eyebrow('Almost yours'),
                const SizedBox(height: 12),
                Text('Delivery details.', style: serif.copyWith(fontSize: 30)),
                const SizedBox(height: 24),
                ...widget.store.cart.entries.map((entry) {
                  final product = widget.store.productById(entry.key);
                  if (product == null) return const SizedBox.shrink();
                  return CartLine(
                    product: product,
                    quantity: entry.value,
                    onQuantity: (quantity) =>
                        widget.store.setQuantity(product, quantity),
                    editable: false,
                  );
                }),
                const SizedBox(height: 16),
                moneyRow('Subtotal', widget.store.subtotal),
                const SizedBox(height: 8),
                moneyRow('Shipping', widget.store.shippingFee),
                const Divider(height: 28),
                moneyRow('Total', widget.store.total, bold: true),
                const SizedBox(height: 24),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 2
                            ? 'Enter your full name'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'Email address'),
                        validator: (value) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch(value?.trim() ?? '')
                            ? null
                            : 'Enter a valid email address',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Philippine mobile number',
                          hintText: '09XXXXXXXXX',
                        ),
                        validator: (value) =>
                            RegExp(r'^09\d{9}$').hasMatch(value?.trim() ?? '')
                                ? null
                                : 'Enter a valid 11-digit mobile number',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _addressController,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Delivery address',
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 10
                            ? 'Enter a complete delivery address'
                            : null,
                      ),
                    ],
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _saveDetails,
                  onChanged: (value) => setState(() => _saveDetails = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Save these details for next time',
                      style: TextStyle(fontSize: 12)),
                ),
                const Text(
                  'A changed checkout email is saved as your contact email. Your sign-in email changes only after verification in your profile.',
                  style: TextStyle(color: muted, fontSize: 11, height: 1.5),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Payment method: Xendit secure hosted checkout · Test Mode',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: red)),
                ],
                const SizedBox(height: 24),
                StoreButton(
                  'CONTINUE TO XENDIT',
                  onPressed: _busy ? null : _placeOrder,
                  busy: _busy,
                  icon: Icons.arrow_forward,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class OrdersSection extends StatelessWidget {
  final CommerceStore store;
  final VoidCallback onShop;
  final VoidCallback onRefresh;

  const OrdersSection(
      {super.key,
      required this.store,
      required this.onShop,
      required this.onRefresh});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Eyebrow('Your little milestones'),
          const SizedBox(height: 14),
          SectionTitle(
            'Your orders.',
            subtitle: '${store.orders.length} orders in your story so far.',
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 17),
              label: const Text('Refresh payment status'),
            ),
          ),
          if (store.orders.isEmpty)
            EmptyState(
              title: 'Your next chapter starts here.',
              description: 'Orders you place will be saved here.',
              action: 'EXPLORE THE COLLECTION',
              onAction: onShop,
            )
          else
            ...store.orders.map(
              (order) => Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: OrderSummaryCard(order: order),
              ),
            ),
          const SizedBox(height: 40),
        ],
      );
}

class OrderSummaryCard extends StatelessWidget {
  final ShopOrder order;

  const OrderSummaryCard({super.key, required this.order});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: paper,
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(
                  order.reference,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${order.status.toUpperCase()} · ${order.paymentStatus.toUpperCase()}',
                  style: const TextStyle(color: red, fontSize: 11),
                ),
              ],
            ),
            const Divider(height: 28),
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: ProductPhoto(
                        item.imagePath,
                        label: item.name,
                        padding: 4,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${item.quantity} × ${item.name}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(pesos(item.subtotal)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '${order.customerName} · ${order.contactNumber}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              order.address,
              style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
            ),
            const Divider(height: 28),
            moneyRow('Subtotal', order.subtotal),
            const SizedBox(height: 8),
            moneyRow('Shipping', order.shippingFee),
            const SizedBox(height: 8),
            moneyRow('Total', order.total, bold: true),
            const SizedBox(height: 10),
            Text(
              'Payment: ${order.paymentMethod == 'cod' ? 'Cash on Delivery' : order.paymentMethod}',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
      );
}

class CartLine extends StatelessWidget {
  final Product product;
  final int quantity;
  final Future<void> Function(int quantity) onQuantity;
  final bool editable;

  const CartLine({
    super.key,
    required this.product,
    required this.quantity,
    required this.onQuantity,
    this.editable = true,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: border)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: ProductPhoto(
                product.imagePath,
                label: product.name,
                padding: 4,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${pesos(product.price)} · ${pesos(product.price * quantity)}',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  if (editable)
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Decrease quantity',
                          visualDensity: VisualDensity.compact,
                          onPressed: quantity > 0
                              ? () => onQuantity(quantity - 1)
                              : null,
                          icon: const Icon(Icons.remove, size: 16),
                        ),
                        Text('$quantity'),
                        IconButton(
                          tooltip: 'Increase quantity',
                          visualDensity: VisualDensity.compact,
                          onPressed: quantity < product.stock
                              ? () => onQuantity(quantity + 1)
                              : null,
                          icon: const Icon(Icons.add, size: 16),
                        ),
                        TextButton(
                          onPressed: () => onQuantity(0),
                          child: const Text(
                            'Remove',
                            style: TextStyle(color: red, fontSize: 11),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Quantity: $quantity',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

Widget moneyRow(String label, num amount, {bool bold = false}) => Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: bold ? ink : muted,
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ),
        Text(
          pesos(amount),
          style: TextStyle(
            color: bold ? ink : muted,
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ],
    );
