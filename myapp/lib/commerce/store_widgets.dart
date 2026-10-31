import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../branding.dart';
import '../services/payment_service.dart';
import 'models.dart';

const muted = Color(0xFF77736A);
const border = Color(0xFFDED9CD);
const imageGround = Color(0xFFF0EDE5);
String pesos(num amount) => '₱${amount.toStringAsFixed(2)}';
Duration motion(BuildContext context) => MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180);

class ProductPhoto extends StatelessWidget {
  final String path;
  final String label;
  final BoxFit fit;
  final double padding;
  const ProductPhoto(this.path, {super.key, required this.label, this.fit = BoxFit.contain, this.padding = 14});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final logicalWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : 400.0;
      final cacheWidth = math.min(
        1600,
        math.max(
          64,
          (logicalWidth * MediaQuery.devicePixelRatioOf(context)).round(),
        ),
      );
      final image = path.startsWith('assets/')
          ? Image.asset(path, fit: fit, semanticLabel: label, cacheWidth: cacheWidth, errorBuilder: _error)
          : Image.network(path.startsWith('http') ? path : '${PaymentService.backendUrl}$path', fit: fit, semanticLabel: label, cacheWidth: cacheWidth, errorBuilder: _error, loadingBuilder: (_, child, progress) => progress == null ? child : const ColoredBox(color: imageGround, child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.5)))));
      return ClipRect(child: ColoredBox(color: imageGround, child: Padding(padding: EdgeInsets.all(padding), child: SizedBox.expand(child: image))));
    });
  }
  Widget _error(BuildContext context, Object error, StackTrace? stack) => const ColoredBox(color: imageGround, child: Center(child: Text('Photo unavailable', style: TextStyle(color: muted, fontSize: 11))));
}

class Eyebrow extends StatelessWidget {
  final String text;
  const Eyebrow(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: const TextStyle(color: red, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w700));
}

class StoreButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool outline;
  final IconData? icon;
  final bool busy;
  const StoreButton(this.text, {super.key, required this.onPressed, this.outline = false, this.icon, this.busy = false});
  @override
  Widget build(BuildContext context) {
    final child = Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [if (busy) ...[const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5)), const SizedBox(width: 10)], Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)), if (icon != null) ...[const SizedBox(width: 12), Icon(icon, size: 16)]]);
    final style = ButtonStyle(minimumSize: const WidgetStatePropertyAll(Size(0, 44)), padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 19, vertical: 14)), shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.zero)), animationDuration: motion(context));
    return outline ? OutlinedButton(onPressed: busy ? null : onPressed, style: style.copyWith(foregroundColor: const WidgetStatePropertyAll(ink), side: const WidgetStatePropertyAll(BorderSide(color: border))), child: child) : FilledButton(onPressed: busy ? null : onPressed, style: style.copyWith(backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? border : states.contains(WidgetState.hovered) ? red : ink)), child: child);
  }
}

class ProductCard extends StatefulWidget {
  final Product product;
  final bool saved;
  final VoidCallback onOpen;
  final VoidCallback onWishlist;
  final VoidCallback onAdd;
  const ProductCard({super.key, required this.product, required this.saved, required this.onOpen, required this.onWishlist, required this.onAdd});
  @override
  State<ProductCard> createState() => _ProductCardState();
}
class _ProductCardState extends State<ProductCard> {
  bool hovering = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return MouseRegion(onEnter: (_) => setState(() => hovering = true), onExit: (_) => setState(() => hovering = false), child: AnimatedContainer(duration: motion(context), decoration: BoxDecoration(color: paper, border: Border.all(color: hovering ? const Color(0xFFB7AA96) : border), boxShadow: hovering ? [const BoxShadow(color: Color(0x12000000), offset: Offset(3, 4))] : []), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AspectRatio(aspectRatio: 1, child: Stack(fit: StackFit.expand, children: [InkWell(onTap: widget.onOpen, child: ProductPhoto(p.imagePath, label: p.name)), if (p.isNew) const Positioned(top: 12, left: 12, child: DecoratedBox(decoration: BoxDecoration(color: paper), child: Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5), child: Text('NEW', style: TextStyle(color: red, fontSize: 9, letterSpacing: 1))))), Positioned(top: 5, right: 5, child: IconButton(tooltip: widget.saved ? 'Remove ${p.name} from wishlist' : 'Save ${p.name}', onPressed: widget.onWishlist, style: IconButton.styleFrom(backgroundColor: paper.withValues(alpha: .92), minimumSize: const Size(36, 36)), icon: Icon(widget.saved ? Icons.favorite : Icons.favorite_border, color: widget.saved ? red : ink, size: 18)))])),
      Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(p.categoryName.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 8, letterSpacing: 1.1)), const SizedBox(height: 4), InkWell(onTap: widget.onOpen, child: SizedBox(height: 36, child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.35, fontWeight: FontWeight.w600)))), const SizedBox(height: 4), Row(children: [Expanded(child: Text(pesos(p.price), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))), Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: p.stock > 0 ? const Color(0xFF708369) : red)), const SizedBox(width: 4), Text(p.stock > 0 ? 'In stock' : 'Sold out', style: const TextStyle(fontSize: 9, color: muted))]), const Spacer(), SizedBox(height: 34, child: OutlinedButton(onPressed: p.inStock ? widget.onAdd : null, style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 5), foregroundColor: ink, side: const BorderSide(color: border), shape: const RoundedRectangleBorder()), child: Text(p.inStock ? 'ADD TO CART' : 'OUT OF STOCK', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .8))))]))),
    ])));
  }
}

class ProductGrid extends StatelessWidget {
  final List<Product> products;
  final Set<String> wishlist;
  final void Function(Product) onOpen, onAdd, onWishlist;
  const ProductGrid({super.key, required this.products, required this.wishlist, required this.onOpen, required this.onAdd, required this.onWishlist});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
    final columns = c.maxWidth >= 1040 ? 4 : c.maxWidth >= 740 ? 3 : c.maxWidth >= 310 ? 2 : 1;
    final gap = c.maxWidth < 600 ? 12.0 : 22.0;
    final width = (c.maxWidth - gap * (columns - 1)) / columns;
    return GridView.builder(key: const ValueKey('product-grid'), shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: products.length, gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, crossAxisSpacing: gap, mainAxisSpacing: gap, mainAxisExtent: width + 158), itemBuilder: (_, index) { final p = products[index]; return ProductCard(product: p, saved: wishlist.contains(p.id), onOpen: () => onOpen(p), onAdd: () => onAdd(p), onWishlist: () => onWishlist(p)); });
  });
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle, action;
  final VoidCallback? onAction;
  const SectionTitle(this.title, {super.key, this.subtitle, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 24), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: serif.copyWith(fontSize: MediaQuery.sizeOf(context).width < 600 ? 24 : 30, height: 1.25)), if (subtitle != null) ...[const SizedBox(height: 8), Text(subtitle!, style: const TextStyle(color: muted, fontSize: 12, height: 1.6))]])), if (action != null) TextButton(onPressed: onAction, child: Text('$action →', style: const TextStyle(color: red, fontSize: 11)))]));
}

class EmptyState extends StatelessWidget {
  final String title, description, action;
  final VoidCallback onAction;
  const EmptyState({super.key, required this.title, required this.description, required this.action, required this.onAction});
  @override
  Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 65), decoration: BoxDecoration(border: Border.all(color: border), color: paper), child: Column(children: [Text(title, textAlign: TextAlign.center, style: serif.copyWith(fontSize: 26)), const SizedBox(height: 12), Text(description, textAlign: TextAlign.center, style: const TextStyle(color: muted, height: 1.7)), const SizedBox(height: 24), StoreButton(action, onPressed: onAction)]));
}

class CatalogSkeleton extends StatelessWidget {
  const CatalogSkeleton({super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) => Wrap(spacing: 20, runSpacing: 20, children: List.generate(c.maxWidth > 700 ? 4 : 2, (_) => SizedBox(width: (c.maxWidth - (c.maxWidth > 700 ? 60 : 20)) / (c.maxWidth > 700 ? 4 : 2), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const AspectRatio(aspectRatio: 1, child: ColoredBox(color: imageGround)), const SizedBox(height: 15), Container(height: 12, width: 110, color: imageGround), const SizedBox(height: 10), Container(height: 12, width: 70, color: imageGround)])))));
}
