/// Shared, defensive data models for the catalog and saved order snapshots.
library;

num _number(Object? value, [num fallback = 0]) =>
    value is num ? value : num.tryParse('$value') ?? fallback;
List<String> _strings(Object? value) =>
    value is List ? value.map((e) => '$e').toList() : const [];
DateTime? _date(Object? value) {
  if (value is String) return DateTime.tryParse(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  if (value is Map && value['_seconds'] is num)
    return DateTime.fromMillisecondsSinceEpoch(
        (value['_seconds'] as num).toInt() * 1000);
  return null;
}

class Product {
  final String id, slug, name, categoryId, categoryName, description, imagePath;
  final double price;
  final int stock;
  final List<String> details, images;
  final bool isNew, featured, isActive;
  final DateTime? createdAt;
  final String photoNote;
  const Product(
      {required this.id,
      required this.slug,
      required this.name,
      required this.categoryId,
      required this.categoryName,
      required this.price,
      required this.stock,
      required this.description,
      required this.imagePath,
      this.details = const [],
      this.images = const [],
      this.isNew = false,
      this.featured = false,
      this.isActive = true,
      this.createdAt,
      this.photoNote = ''});
  factory Product.fromJson(Map<String, dynamic> json, {String? categoryName}) =>
      Product(
        id: '${json['id'] ?? ''}',
        slug: '${json['slug'] ?? json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        categoryId: '${json['categoryId'] ?? ''}',
        categoryName:
            categoryName ?? '${json['categoryName'] ?? json['category'] ?? ''}',
        price: _number(json['price']).toDouble(),
        stock: _number(json['stock']).toInt(),
        description: '${json['description'] ?? ''}',
        imagePath:
            '${json['imagePath'] ?? 'assets/images/products/${json['slug']}.jpg'}',
        details: _strings(json['details']),
        images: _strings(json['images']),
        isNew: json['isNew'] == true,
        featured: json['featured'] == true,
        isActive: json['isActive'] != false,
        createdAt: _date(json['createdAt']),
        photoNote: '${json['photoNote'] ?? ''}',
      );
  bool get inStock => isActive && stock > 0;
  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': slug,
        'name': name,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'price': price,
        'stock': stock,
        'description': description,
        'imagePath': imagePath,
        'images': images,
        'details': details,
        'isNew': isNew,
        'featured': featured,
        'isActive': isActive,
        'photoNote': photoNote
      };
}

class ShopCategory {
  final String id, name, description, imagePath;
  const ShopCategory(
      {required this.id,
      required this.name,
      this.description = '',
      this.imagePath = ''});
  factory ShopCategory.fromJson(Map<String, dynamic> json) => ShopCategory(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      imagePath: '${json['imagePath'] ?? ''}');
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'imagePath': imagePath
      };
}

class CartItem {
  final String productId;
  final int quantity;
  const CartItem({required this.productId, required this.quantity});
  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
      productId: '${json['productId'] ?? ''}',
      quantity: _number(json['quantity']).toInt());
  Map<String, dynamic> toJson() =>
      {'productId': productId, 'quantity': quantity};
}

class CustomerProfile {
  final String username, name, email, contactEmail, phoneNumber, address, profilePhotoPath;
  const CustomerProfile({
    this.username = '',
    this.name = '',
    this.email = '',
    this.contactEmail = '',
    this.phoneNumber = '',
    this.address = '',
    this.profilePhotoPath = '',
  });
  factory CustomerProfile.fromJson(Map<String, dynamic> json) => CustomerProfile(
        username: '${json['username'] ?? ''}',
        name: '${json['name'] ?? ''}',
        email: '${json['email'] ?? ''}',
        contactEmail: '${json['contactEmail'] ?? json['email'] ?? ''}',
        phoneNumber: '${json['phoneNumber'] ?? ''}',
        address: '${json['address'] ?? ''}',
        profilePhotoPath: '${json['profilePhotoPath'] ?? ''}',
      );
  Map<String, dynamic> toJson() => {
        'username': username,
        'name': name,
        'email': email,
        'contactEmail': contactEmail,
        'phoneNumber': phoneNumber,
        'address': address,
        'profilePhotoPath': profilePhotoPath,
      };
}

class OrderItem {
  final String productId, name, imagePath;
  final double price, subtotal;
  final int quantity;
  const OrderItem(
      {required this.productId,
      required this.name,
      required this.imagePath,
      required this.price,
      required this.quantity,
      required this.subtotal});
  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
      productId: '${json['productId'] ?? ''}',
      name: '${json['name'] ?? ''}',
      imagePath: '${json['imagePath'] ?? ''}',
      price: _number(json['price']).toDouble(),
      quantity: _number(json['quantity']).toInt(),
      subtotal: _number(json['subtotal'],
              _number(json['price']) * _number(json['quantity']))
          .toDouble());
}

class ShopOrder {
  final String id,
      reference,
      status,
      paymentStatus,
      paymentMethod,
      customerName,
      contactNumber,
      address;
  final String paymentUrl, paymentSessionId;
  final List<OrderItem> items;
  final double subtotal, shippingFee, total;
  final DateTime? createdAt;
  const ShopOrder(
      {required this.id,
      required this.reference,
      required this.status,
      required this.paymentStatus,
      required this.paymentMethod,
      required this.customerName,
      required this.contactNumber,
      required this.address,
      required this.items,
      required this.subtotal,
      required this.shippingFee,
      required this.total,
      this.paymentUrl = '',
      this.paymentSessionId = '',
      this.createdAt});
  factory ShopOrder.fromJson(Map<String, dynamic> json) => ShopOrder(
      id: '${json['id'] ?? ''}',
      reference:
          '${json['reference'] ?? json['referenceId'] ?? json['id'] ?? ''}',
      status: '${json['status'] ?? 'pending'}',
      paymentStatus: '${json['paymentStatus'] ?? 'unpaid'}',
      paymentMethod: '${json['paymentMethod'] ?? 'cod'}',
      customerName: '${json['customerName'] ?? ''}',
      contactNumber: '${json['contactNumber'] ?? ''}',
      address: '${json['address'] ?? ''}',
      items: (json['items'] as List? ?? [])
          .map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      subtotal: _number(json['subtotal']).toDouble(),
      shippingFee: _number(json['shippingFee']).toDouble(),
      total: _number(json['total'], _number(json['amount'])).toDouble(),
      paymentUrl: '${json['paymentUrl'] ?? ''}',
      paymentSessionId: '${json['paymentSessionId'] ?? ''}',
      createdAt: _date(json['createdAt']));
}
