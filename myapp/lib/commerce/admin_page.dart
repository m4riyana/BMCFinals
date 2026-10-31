import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../branding.dart';
import 'commerce_api.dart';
import 'commerce_store.dart';
import 'models.dart';
import 'store_widgets.dart';

class AdminPage extends StatefulWidget {
  final CommerceStore store;
  const AdminPage({super.key, required this.store});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  bool _loading = true;
  String? _error;
  List<Product> _products = [];
  List<ShopCategory> _categories = [];
  List<ShopOrder> _orders = [];
  int _tab = 0;
  CommerceApi get api => widget.store.api;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.store.isAdmin) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Future.wait([
        api.request('GET', '/api/admin/products'),
        api.request('GET', '/api/admin/categories'),
        api.request('GET', '/api/admin/orders')
      ]);
      if (!mounted) return;
      setState(() {
        _categories = (data[1]['categories'] as List? ?? [])
            .map((e) =>
                ShopCategory.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        final names = {for (final c in _categories) c.id: c.name};
        _products = (data[0]['products'] as List? ?? [])
            .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map),
                categoryName: names[e['categoryId']]))
            .toList();
        _orders = (data[2]['orders'] as List? ?? [])
            .map((e) => ShopOrder.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _editProduct([Product? product]) async {
    if (_categories.isEmpty) {
      _message('Add a category before adding products.');
      return;
    }
    final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ProductEditor(
            api: api, product: product, categories: _categories));
    if (saved == true) {
      await _load();
      await widget.store.refresh();
      _message('Product saved.');
    }
  }

  Future<void> _deactivate(Product product) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Deactivate product?'),
                content: Text(
                    '${product.name} will be hidden from the shop. Existing order records will stay available.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Deactivate'))
                ]));
    if (confirmed != true) return;
    try {
      await api.request(
          'DELETE', '/api/admin/products/${Uri.encodeComponent(product.id)}');
      await _load();
      await widget.store.refresh();
    } catch (e) {
      _message('$e');
    }
  }

  Future<void> _editCategory([ShopCategory? category]) async {
    final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CategoryEditor(api: api, category: category));
    if (saved == true) {
      await _load();
      await widget.store.refresh();
      _message('Category saved.');
    }
  }

  Future<void> _deleteCategory(ShopCategory category) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Delete category?'),
                content: Text(
                    'Delete ${category.name}? Move any products to another category first.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete category'))
                ]));
    if (confirmed != true) return;
    try {
      await api.request('DELETE',
          '/api/admin/categories/${Uri.encodeComponent(category.id)}');
      await _load();
      await widget.store.refresh();
    } catch (e) {
      _message('$e');
    }
  }

  Future<void> _updateOrder(ShopOrder order, String status,
      {String? paymentStatus}) async {
    final label = paymentStatus == 'paid'
        ? 'Confirm that cash was collected for this order?'
        : 'Change ${order.reference} to $status?';
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Update order'),
                content: Text(label),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Confirm'))
                ]));
    if (confirmed != true) return;
    try {
      await api.request(
          'PATCH', '/api/admin/orders/${Uri.encodeComponent(order.id)}', body: {
        'status': status,
        if (paymentStatus != null) 'paymentStatus': paymentStatus
      });
      await _load();
    } catch (e) {
      _message('$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Store management'), actions: [
          IconButton(
              tooltip: 'Refresh management data',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh))
        ]),
        body: !widget.store.isAdmin
            ? const Center(child: Text('Administrator access is required.'))
            : Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1160),
                    child: Column(children: [
                      Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Eyebrow('IBASHO STATIONERY / ADMIN'),
                                const SizedBox(height: 12),
                                Text('A well-kept little shop.',
                                    style: serif.copyWith(fontSize: 30)),
                                const SizedBox(height: 20),
                                Wrap(spacing: 12, children: [
                                  for (final entry in [
                                    (0, 'Products'),
                                    (1, 'Categories'),
                                    (2, 'Orders')
                                  ])
                                    ChoiceChip(
                                        label: Text(entry.$2),
                                        selected: _tab == entry.$1,
                                        onSelected: (_) =>
                                            setState(() => _tab = entry.$1))
                                ])
                              ])),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_error!,
                                style: const TextStyle(color: red))),
                      Expanded(
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : _tab == 0
                                  ? _productList()
                                  : _tab == 1
                                      ? _categoryList()
                                      : _orderList()),
                    ]))),
      );
  Widget _productList() =>
      ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 40), children: [
        Align(
            alignment: Alignment.centerLeft,
            child: StoreButton('ADD PRODUCT',
                onPressed: () => _editProduct(), icon: Icons.add)),
        const SizedBox(height: 20),
        if (_products.isEmpty)
          const Padding(
              padding: EdgeInsets.all(30),
              child: Text('Your catalog is ready for its first product.')),
        for (final product in _products)
          Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: paper, border: Border.all(color: border)),
              child: Row(children: [
                SizedBox(
                    width: 68,
                    height: 68,
                    child: ProductPhoto(product.imagePath,
                        label: product.name, padding: 5)),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(product.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Text('${product.categoryName} · ${pesos(product.price)}',
                          style: const TextStyle(color: muted, fontSize: 12)),
                      const SizedBox(height: 5),
                      Text(
                          '${product.stock} in stock${product.isActive ? '' : ' · Inactive'}',
                          style: TextStyle(
                              color: product.isActive ? muted : red,
                              fontSize: 12))
                    ])),
                IconButton(
                    tooltip: 'Edit ${product.name}',
                    onPressed: () => _editProduct(product),
                    icon: const Icon(Icons.edit_outlined, size: 20)),
                if (product.isActive)
                  IconButton(
                      tooltip: 'Deactivate ${product.name}',
                      onPressed: () => _deactivate(product),
                      icon: const Icon(Icons.visibility_off_outlined, size: 20))
              ])),
      ]);
  Widget _categoryList() =>
      ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 40), children: [
        Align(
            alignment: Alignment.centerLeft,
            child: StoreButton('ADD CATEGORY',
                onPressed: () => _editCategory(), icon: Icons.add)),
        const SizedBox(height: 20),
        for (final category in _categories)
          Card(
              child: ListTile(
                  title: Text(category.name),
                  subtitle: Text(category.description),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        tooltip: 'Edit ${category.name}',
                        onPressed: () => _editCategory(category),
                        icon: const Icon(Icons.edit_outlined)),
                    IconButton(
                        tooltip: 'Delete ${category.name}',
                        onPressed: () => _deleteCategory(category),
                        icon: const Icon(Icons.delete_outline))
                  ])))
      ]);
  Widget _orderList() =>
      ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 40), children: [
        if (_orders.isEmpty)
          const Padding(
              padding: EdgeInsets.all(32),
              child: Text('New customer orders will appear here.')),
        for (final order in _orders)
          Container(
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                  color: paper, border: Border.all(color: border)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                        spacing: 18,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Text(order.reference,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                              '${order.status.toUpperCase()} · ${order.paymentStatus.toUpperCase()}',
                              style: const TextStyle(color: red, fontSize: 11)),
                          Text(pesos(order.total),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold))
                        ]),
                    const SizedBox(height: 14),
                    Text('${order.customerName} · ${order.contactNumber}'),
                    const SizedBox(height: 5),
                    Text(order.address,
                        style: const TextStyle(color: muted, height: 1.5)),
                    const Divider(height: 28),
                    for (final item in order.items)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(children: [
                            SizedBox(
                                width: 42,
                                height: 42,
                                child: ProductPhoto(item.imagePath,
                                    label: item.name, padding: 3)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text('${item.quantity} × ${item.name}',
                                    style: const TextStyle(fontSize: 12))),
                            Text(pesos(item.subtotal),
                                style: const TextStyle(fontSize: 12))
                          ])),
                    Text(
                        'Shipping ${pesos(order.shippingFee)} · ${order.paymentMethod == 'cod' ? 'Cash on Delivery' : order.paymentMethod}',
                        style: const TextStyle(fontSize: 12, color: muted)),
                    const SizedBox(height: 16),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      for (final status in _nextStatuses(order.status))
                        StoreButton(status.toUpperCase(),
                            outline: true,
                            onPressed: () => _updateOrder(order, status)),
                      if (order.status == 'delivered' &&
                          order.paymentMethod == 'cod' &&
                          order.paymentStatus != 'paid')
                        StoreButton('CONFIRM CASH COLLECTED',
                            onPressed: () => _updateOrder(order, order.status,
                                paymentStatus: 'paid'))
                    ]),
                  ])),
      ]);
  List<String> _nextStatuses(String status) => switch (status) {
        'pending' => ['confirmed', 'cancelled'],
        'confirmed' => ['processing', 'cancelled'],
        'processing' => ['shipped', 'cancelled'],
        'shipped' => ['delivered'],
        _ => []
      };
}

class _ProductEditor extends StatefulWidget {
  final CommerceApi api;
  final Product? product;
  final List<ShopCategory> categories;
  const _ProductEditor(
      {required this.api, required this.product, required this.categories});
  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name,
      _price,
      _stock,
      _description,
      _details;
  late String _categoryId, _imagePath;
  late bool _active, _featured, _new;
  bool _busy = false;
  String? _error, _filename;
  Uint8List? _bytes;
  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name ?? '');
    _price = TextEditingController(text: p?.price.toStringAsFixed(2) ?? '');
    _stock = TextEditingController(text: '${p?.stock ?? 0}');
    _description = TextEditingController(text: p?.description ?? '');
    _details = TextEditingController(text: p?.details.join('\n') ?? '');
    _categoryId = p?.categoryId ?? widget.categories.first.id;
    if (!widget.categories.any((c) => c.id == _categoryId))
      _categoryId = widget.categories.first.id;
    _imagePath = p?.imagePath ?? '';
    _active = p?.isActive ?? true;
    _featured = p?.featured ?? false;
    _new = p?.isNew ?? true;
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _stock, _description, _details]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp']);
      if (file == null) return;
      final length = await file.length();
      if (length != null && length > 5 * 1024 * 1024)
        throw const CommerceException('Choose an image smaller than 5 MB.');
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024)
        throw const CommerceException(
            'Choose a valid image smaller than 5 MB.');
      if (mounted)
        setState(() {
          _bytes = bytes;
          _filename = file.name;
          _error = null;
        });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_imagePath.isEmpty && _bytes == null) {
      setState(() => _error = 'Upload a product photograph.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_bytes != null)
        _imagePath = await widget.api.uploadImage(_bytes!, _filename!);
      final existing = widget.product;
      final body = <String, dynamic>{
        'name': _name.text.trim(),
        'slug': existing?.slug ??
            _name.text
                .trim()
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
                .replaceAll(RegExp(r'^-|-$'), ''),
        'categoryId': _categoryId,
        'price': double.parse(_price.text),
        'stock': int.parse(_stock.text),
        'description': _description.text.trim(),
        'details': _details.text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'imagePath': _imagePath,
        'images': existing?.images ?? [],
        'isActive': _active,
        'featured': _featured,
        'isNew': _new,
        'photoNote': existing?.photoNote ?? ''
      };
      await widget.api.request(
          existing == null ? 'POST' : 'PUT',
          existing == null
              ? '/api/admin/products'
              : '/api/admin/products/${Uri.encodeComponent(existing.id)}',
          body: body);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = '$e';
          _busy = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.product == null ? 'Add product' : 'Edit product'),
          content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                  child: Form(
                      key: _form,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                                height: 165,
                                child: _bytes != null
                                    ? Image.memory(_bytes!,
                                        fit: BoxFit.contain,
                                        errorBuilder: (context, error,
                                                stackTrace) =>
                                            const Center(
                                                child: Text(
                                                    'This file is not a readable image.')))
                                    : _imagePath.isNotEmpty
                                        ? ProductPhoto(_imagePath,
                                            label: 'Current product photograph')
                                        : const ColoredBox(
                                            color: imageGround,
                                            child: Center(
                                                child: Text(
                                                    'Add a real product photograph')))),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                                onPressed: _busy ? null : _pick,
                                icon:
                                    const Icon(Icons.upload_outlined, size: 18),
                                label: const Text('Choose product photograph')),
                            const Text('JPG, PNG, or WebP · up to 5 MB',
                                style: TextStyle(color: muted, fontSize: 11)),
                            const SizedBox(height: 20),
                            TextFormField(
                                controller: _name,
                                maxLength: 120,
                                decoration: const InputDecoration(
                                    labelText: 'Product name'),
                                validator: (v) => (v?.trim().isEmpty ?? true)
                                    ? 'Enter a product name'
                                    : null),
                            const SizedBox(height: 14),
                            DropdownButtonFormField<String>(
                                initialValue: _categoryId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Category'),
                                items: widget.categories
                                    .map((c) => DropdownMenuItem(
                                        value: c.id, child: Text(c.name)))
                                    .toList(),
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(() => _categoryId = v!)),
                            const SizedBox(height: 14),
                            Row(children: [
                              Expanded(
                                  child: TextFormField(
                                      controller: _price,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                          labelText: 'Price (PHP)'),
                                      validator: (v) {
                                        final n = double.tryParse(v ?? '');
                                        return n == null ||
                                                !n.isFinite ||
                                                n <= 0 ||
                                                n > 1000000
                                            ? 'Enter a valid price'
                                            : null;
                                      })),
                              const SizedBox(width: 14),
                              Expanded(
                                  child: TextFormField(
                                      controller: _stock,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                          labelText: 'Stock quantity'),
                                      validator: (v) {
                                        final n = int.tryParse(v ?? '');
                                        return n == null || n < 0 || n > 1000000
                                            ? 'Enter valid stock'
                                            : null;
                                      }))
                            ]),
                            const SizedBox(height: 14),
                            TextFormField(
                                controller: _description,
                                minLines: 3,
                                maxLines: 6,
                                maxLength: 3000,
                                decoration: const InputDecoration(
                                    labelText: 'Description'),
                                validator: (v) => (v?.trim().isEmpty ?? true)
                                    ? 'Enter a description'
                                    : null),
                            const SizedBox(height: 14),
                            TextFormField(
                                controller: _details,
                                minLines: 2,
                                maxLines: 6,
                                decoration: const InputDecoration(
                                    labelText: 'Product details',
                                    helperText: 'One detail per line')),
                            const SizedBox(height: 10),
                            CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Visible in shop'),
                                value: _active,
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(() => _active = v!)),
                            CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Featured product'),
                                value: _featured,
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(() => _featured = v!)),
                            CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('New arrival'),
                                value: _new,
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(() => _new = v!)),
                            if (_error != null)
                              Text(_error!, style: const TextStyle(color: red)),
                          ])))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            StoreButton('SAVE PRODUCT', onPressed: _save, busy: _busy)
          ]);
}

class _CategoryEditor extends StatefulWidget {
  final CommerceApi api;
  final ShopCategory? category;
  const _CategoryEditor({required this.api, this.category});
  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _description, _image;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.category?.name ?? '');
    _description =
        TextEditingController(text: widget.category?.description ?? '');
    _image = TextEditingController(text: widget.category?.imagePath ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _image.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = widget.category;
      final id = c?.id ??
          _name.text
              .toLowerCase()
              .trim()
              .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
              .replaceAll(RegExp(r'^-|-$'), '');
      await widget.api.request(
          c == null ? 'POST' : 'PUT',
          c == null
              ? '/api/admin/categories'
              : '/api/admin/categories/${Uri.encodeComponent(c.id)}',
          body: {
            'id': id,
            'name': _name.text.trim(),
            'description': _description.text.trim(),
            'imagePath': _image.text.trim()
          });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = '$e';
          _busy = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title:
              Text(widget.category == null ? 'Add category' : 'Edit category'),
          content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                  child: Form(
                      key: _form,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        TextFormField(
                            controller: _name,
                            decoration: const InputDecoration(
                                labelText: 'Category name'),
                            maxLength: 80,
                            validator: (v) => (v?.trim().isEmpty ?? true)
                                ? 'Enter a category name'
                                : null),
                        const SizedBox(height: 16),
                        TextFormField(
                            controller: _description,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                                labelText: 'Description')),
                        const SizedBox(height: 16),
                        TextFormField(
                            controller: _image,
                            decoration: const InputDecoration(
                                labelText: 'Local photograph path',
                                hintText:
                                    'assets/images/products/example.jpg')),
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(_error!,
                                  style: const TextStyle(color: red)))
                      ])))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            StoreButton('SAVE CATEGORY', onPressed: _save, busy: _busy)
          ]);
}
