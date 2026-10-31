'use strict';
const crypto = require('node:crypto');

class HttpError extends Error {
  constructor(status, message, code = 'request_failed') { super(message); this.status = status; this.code = code; }
}
const fail = (status, message, code) => { throw new HttpError(status, message, code); };
const idPattern = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$/;
function id(value) { if (typeof value !== 'string' || !idPattern.test(value)) fail(400, 'Invalid identifier.'); return value; }
function text(value, label, min = 1, max = 500) {
  if (typeof value !== 'string' || value.trim().length < min || value.trim().length > max || /[\u0000-\u0008\u000B\u000C\u000E-\u001F]/.test(value)) fail(400, `Enter a valid ${label}.`);
  return value.trim();
}
function imagePath(value) {
  if (typeof value !== 'string' || !/^(assets\/images\/products\/[a-zA-Z0-9_-]+\.(?:jpg|jpeg|png|webp)|\/uploads\/products\/[a-f0-9-]+\.webp)$/.test(value)) fail(400, 'Use an uploaded product image.');
  return value;
}
function items(value, allowEmpty = false) {
  if (!Array.isArray(value) || value.length > 100 || (!allowEmpty && value.length === 0)) fail(400, 'Your cart must contain valid products.');
  const seen = new Set();
  return value.map(item => {
    if (!item || typeof item !== 'object') fail(400, 'Invalid cart item.');
    const productId = id(item.productId);
    if (seen.has(productId) || !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 99) fail(400, 'Choose a quantity between 1 and 99 for each product.');
    seen.add(productId);
    return {productId, quantity: item.quantity};
  }).sort((a,b) => a.productId.localeCompare(b.productId));
}
function customer(body, fallbackEmail = '') {
  const customerName = text(body.customerName, 'customer name', 2, 100);
  const contactNumber = text(body.contactNumber, 'contact number', 11, 13);
  if (!/^(09\d{9}|\+639\d{9})$/.test(contactNumber)) fail(400, 'Use a valid Philippine mobile number.');
  const email = text(body.email || fallbackEmail, 'email address', 5, 254);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) fail(400, 'Enter a valid email address.');
  return {customerName, email, contactNumber, address: text(body.address, 'shipping address', 10, 600)};
}
function productInput(body, productId) {
  const price = Number(body.price);
  if (!Number.isFinite(price) || price <= 0 || price > 1000000 || Math.abs(price * 100 - Math.round(price * 100)) > .00001) fail(400, 'Price must be a positive amount with at most two decimals.');
  if (!Number.isInteger(body.stock) || body.stock < 0 || body.stock > 1000000) fail(400, 'Stock must be a nonnegative whole number.');
  const details = body.details ?? [];
  if (!Array.isArray(details) || details.length > 20) fail(400, 'Use up to 20 product details.');
  const primary = imagePath(body.imagePath);
  const images = body.images ?? [primary];
  if (!Array.isArray(images) || images.length > 8) fail(400, 'Use up to eight product photographs.');
  return {id: productId, slug: id(body.slug || productId), name: text(body.name, 'product name', 2, 150), categoryId: id(body.categoryId), price, stock: body.stock,
    description: text(body.description, 'description', 10, 4000), details: details.map(x => text(x, 'product detail', 1, 300)),
    imagePath: primary, images: [...new Set([primary, ...images.map(imagePath)])], featured: body.featured === true, isNew: body.isNew === true, isActive: body.isActive !== false,
    photoNote: typeof body.photoNote === 'string' ? text(body.photoNote, 'photo note', 0, 500) : ''};
}
const cleanOrder = order => { const {checkoutFingerprint, paymentCreating, paymentCreatingAt, ...safe} = order; return safe; };

class CommerceService {
  constructor(repository, {shipping = {standardFee: 60, freeShippingThreshold: 1000}, now = () => new Date().toISOString()} = {}) { this.repo = repository; this.shipping = shipping; this.now = now; }
  async catalog(includeInactive = false) {
    const [products, categories] = await Promise.all([this.repo.list('products', {active: !includeInactive}), this.repo.list('categories')]);
    const names = new Map(categories.map(c => [c.id, c.name]));
    return {products: products.map(p => ({...p, categoryName: names.get(p.categoryId) || p.categoryId})), categories, shipping: this.shipping};
  }
  async getCart(uid) { return await this.repo.get(`carts/${uid}`) || {items: []}; }
  async saveCart(uid, body) {
    const list = items(body.items, true);
    return this.repo.transaction(async tx => {
      const products = await Promise.all(list.map(item => tx.get(`products/${item.productId}`)));
      list.forEach((item,i) => { if (!products[i]?.isActive || products[i].stock < item.quantity) fail(409, `${products[i]?.name || 'A product'} is unavailable in that quantity.`, 'insufficient_stock'); });
      const cart = {items: list, updatedAt: this.now()}; tx.set(`carts/${uid}`, cart); return cart;
    });
  }
  async getWishlist(uid) { return await this.repo.get(`wishlists/${uid}`) || {productIds: []}; }
  async saveWishlist(uid, body) {
    if (!Array.isArray(body.productIds) || body.productIds.length > 200) fail(400, 'Save up to 200 wishlist products.');
    const productIds = [...new Set(body.productIds.map(id))];
    const products = await Promise.all(productIds.map(productId => this.repo.get(`products/${productId}`)));
    if (products.some(p => !p)) fail(400, 'One of the selected products no longer exists.');
    const result = {productIds, updatedAt: this.now()}; await this.repo.set(`wishlists/${uid}`, result); return result;
  }
  async orders(uid) { return (await this.repo.list('orders', {uid, limit: 100})).map(cleanOrder); }
  async order(uid, orderId, isAdmin = false) {
    const order = await this.repo.get(`orders/${id(orderId)}`);
    if (!order || (!isAdmin && order.uid !== uid)) fail(404, 'Order not found.');
    return cleanOrder(order);
  }
  async checkout(user, body, paymentMethod = 'cod') {
    const contact = customer(body, user.email || ''); const cart = items(body.items);
    if (!['cod', 'xendit'].includes(paymentMethod)) fail(400, 'Unsupported payment method.');
    const key = text(body.idempotencyKey, 'checkout reference', 16, 120);
    const checkoutFingerprint = crypto.createHash('sha256').update(JSON.stringify({contact, cart, paymentMethod})).digest('hex');
    const keyId = crypto.createHash('sha256').update(`${user.uid}:${key}`).digest('hex');
    const orderId = `IB-${crypto.randomUUID()}`;
    return this.repo.transaction(async tx => {
      const previous = await tx.get(`checkoutKeys/${keyId}`);
      if (previous) {
        if (previous.fingerprint !== checkoutFingerprint) fail(409, 'This checkout reference has already been used.');
        return cleanOrder(await tx.get(`orders/${previous.orderId}`));
      }
      const products = await Promise.all(cart.map(item => tx.get(`products/${item.productId}`)));
      let subtotalCents = 0;
      const checkedItems = cart.map((item,i) => {
        const p = products[i];
        if (!p?.isActive || p.stock < item.quantity) fail(409, `${p?.name || 'A product'} is unavailable in that quantity.`, 'insufficient_stock');
        if (!Number.isFinite(p.price) || p.price <= 0 || !Number.isInteger(p.stock)) fail(409, 'A product requires a catalog update.');
        const amount = Math.round(p.price * 100) * item.quantity; subtotalCents += amount;
        return {productId: item.productId, name: p.name, price: p.price, quantity: item.quantity, subtotal: amount / 100, imagePath: p.imagePath, categoryId: p.categoryId};
      });
      const subtotal = subtotalCents / 100;
      const shippingFee = subtotal >= this.shipping.freeShippingThreshold ? 0 : this.shipping.standardFee;
      const createdAt = this.now();
      const order = {id: orderId, reference: orderId, uid: user.uid, ...contact, items: checkedItems, subtotal, shippingFee,
        total: (subtotalCents + Math.round(shippingFee * 100)) / 100, currency: 'PHP', paymentMethod, paymentStatus: 'unpaid',
        status: paymentMethod === 'cod' ? 'pending' : 'pending_payment', stockRestored: false, createdAt, updatedAt: createdAt, checkoutFingerprint,
        history: [{status: paymentMethod === 'cod' ? 'pending' : 'pending_payment', at: createdAt}]};
      cart.forEach((item,i) => tx.set(`products/${item.productId}`, {...products[i], stock: products[i].stock - item.quantity, updatedAt: createdAt}));
      tx.set(`orders/${orderId}`, order); tx.set(`checkoutKeys/${keyId}`, {orderId, fingerprint: checkoutFingerprint, uid: user.uid, createdAt});
      if (paymentMethod === 'cod') tx.set(`carts/${user.uid}`, {items: [], updatedAt: createdAt});
      return cleanOrder(order);
    });
  }
  async attachPaymentSession(orderId, session, uid) {
    return this.repo.transaction(async tx => {
      const order = await tx.get(`orders/${id(orderId)}`);
      if (!order || order.uid !== uid) fail(404, 'Order not found.');
      if (order.paymentMethod !== 'xendit' || order.status !== 'pending_payment' || order.paymentStatus !== 'unpaid') fail(409, 'This order is no longer awaiting payment.');
      if (order.paymentSessionId) {
        if (order.paymentSessionId !== session.id) fail(409, 'A payment session already exists for this order.');
        return cleanOrder(order);
      }
      const now = this.now();
      const updated = {...order, paymentSessionId: session.id, paymentUrl: session.url, paymentSessionExpiresAt: session.expiresAt || null, updatedAt: now,
        paymentCreating: false, paymentCreatingAt: null,
        history: [...order.history, {status: order.status, paymentStatus: order.paymentStatus, event: 'payment_session_created', at: now}]};
      tx.set(`orders/${order.id}`, updated);
      tx.set(`carts/${uid}`, {items: [], updatedAt: now});
      return cleanOrder(updated);
    });
  }
  async claimPaymentSession(orderId, uid) {
    return this.repo.transaction(async tx => {
      const order = await tx.get(`orders/${id(orderId)}`);
      if (!order || order.uid !== uid) fail(404, 'Order not found.');
      if (order.paymentMethod !== 'xendit' || order.status !== 'pending_payment' || order.paymentStatus !== 'unpaid') {
        fail(409, 'This order is no longer awaiting payment.');
      }
      if (order.paymentSessionId && order.paymentUrl) {
        return {order: cleanOrder(order), claimed: false};
      }
      if (order.paymentCreating && Date.now() - (order.paymentCreatingAt || 0) < 60000) {
        fail(409, 'Your secure payment link is being prepared. Please wait a moment and try again.');
      }
      tx.set(`orders/${order.id}`, {...order, paymentCreating: true, paymentCreatingAt: Date.now()});
      return {order: cleanOrder(order), claimed: true};
    });
  }
  async releasePaymentSessionClaim(orderId, uid) {
    return this.repo.transaction(async tx => {
      const order = await tx.get(`orders/${id(orderId)}`);
      if (order?.uid === uid && !order.paymentSessionId && order.paymentCreating) {
        tx.set(`orders/${order.id}`, {...order, paymentCreating: false, paymentCreatingAt: null});
      }
    });
  }
  async markPaymentFailure(orderId, paymentId) {
    return this.repo.transaction(async tx => {
      const order = await tx.get(`orders/${id(orderId)}`);
      if (!order || order.paymentMethod !== 'xendit') fail(404, 'Order not found.');
      if (order.paymentStatus === 'paid') return cleanOrder(order);
      const now = this.now();
      const updated = {...order, paymentStatus: 'failed', xenditPaymentId: paymentId || order.xenditPaymentId || null, updatedAt: now,
        history: [...order.history, {status: order.status, paymentStatus: 'failed', at: now}]};
      tx.set(`orders/${order.id}`, updated);
      return cleanOrder(updated);
    });
  }
  async confirmXenditPayment(orderId, verified) {
    return this.repo.transaction(async tx => {
      const order = await tx.get(`orders/${id(orderId)}`);
      if (!order || order.paymentMethod !== 'xendit') fail(404, 'Order not found.');
      if (order.paymentSessionId !== verified.sessionId || order.reference !== verified.reference ||
          order.paymentSessionStatus && order.paymentSessionStatus !== 'COMPLETED' ||
          order.paymentStatus === 'paid') return cleanOrder(order);
      const now = this.now();
      const updated = {...order, status: 'confirmed', paymentStatus: 'paid', xenditPaymentId: verified.paymentId,
        paymentSessionStatus: 'COMPLETED', updatedAt: now,
        history: [...order.history, {status: 'confirmed', paymentStatus: 'paid', at: now}]};
      tx.set(`orders/${order.id}`, updated);
      return cleanOrder(updated);
    });
  }
  async finishXenditSession(orderId, {uid, sessionId, status}) {
    return this.repo.transaction(async tx => {
      const order = await tx.get(`orders/${id(orderId)}`);
      if (!order || (uid && order.uid !== uid) || order.paymentMethod !== 'xendit') fail(404, 'Order not found.');
      if (order.paymentSessionId !== sessionId) fail(409, 'Payment session does not match this order.');
      if (order.paymentStatus === 'paid') return cleanOrder(order);
      if (!['EXPIRED', 'CANCELED'].includes(status)) fail(409, 'This payment session is still active.');
      if (order.stockRestored) return cleanOrder(order);
      const products = await Promise.all(order.items.map(item => tx.get(`products/${item.productId}`)));
      const savedCart = await tx.get(`carts/${order.uid}`);
      const now = this.now();
      order.items.forEach((item, index) => { if (products[index]) tx.set(`products/${item.productId}`, {...products[index], stock: products[index].stock + item.quantity, updatedAt: now}); });
      const paymentStatus = status === 'EXPIRED' ? 'expired' : 'cancelled';
      const restoredCart = new Map((savedCart?.items || []).map(item => [item.productId, item.quantity]));
      order.items.forEach(item => restoredCart.set(item.productId, Math.min(
        (products.find(product => product?.id === item.productId)?.stock || 0) + item.quantity,
        (restoredCart.get(item.productId) || 0) + item.quantity,
      )));
      const updated = {...order, status: 'cancelled', paymentStatus, paymentSessionStatus: status, stockRestored: true, updatedAt: now,
        history: [...order.history, {status: 'cancelled', paymentStatus, at: now}]};
      tx.set(`orders/${order.id}`, updated);
      tx.set(`carts/${order.uid}`, {items: [...restoredCart].map(([productId, quantity]) => ({productId, quantity})), updatedAt: now});
      return cleanOrder(updated);
    });
  }
  async updateOrder(orderId, body, actor) {
    id(orderId); const next = body.status;
    const transitions = {pending: ['confirmed','cancelled'], confirmed: ['processing','cancelled'], processing: ['shipped','cancelled'], shipped: ['delivered'], delivered: [], cancelled: [], pending_payment: ['cancelled']};
    return this.repo.transaction(async tx => {
      const order = await tx.get(`orders/${orderId}`);
      if (!order) fail(404, 'Order not found.');
      if (!Object.hasOwn(transitions, next)) fail(400, 'Invalid order status.');
      if (order.status !== next && !transitions[order.status]?.includes(next)) fail(409, 'This order status transition is not allowed.');
      if (next === 'cancelled' && order.paymentStatus === 'paid') fail(409, 'Paid orders require a verified refund before cancellation.');
      if (next === 'cancelled' && order.paymentMethod === 'xendit' && !['expired','failed'].includes(order.paymentStatus)) fail(409, 'Verify that the online payment session has expired before cancelling.');
      if (body.paymentStatus !== undefined && body.paymentStatus !== order.paymentStatus && !(body.paymentStatus === 'paid' && order.paymentMethod === 'cod' && next === 'delivered')) fail(400, 'Confirm COD collection only when the order is delivered. Online payments are verified automatically.');
      const restock = next === 'cancelled' && !order.stockRestored;
      const products = restock ? await Promise.all(order.items.map(item => tx.get(`products/${item.productId}`))) : [];
      const now = this.now();
      if (restock) order.items.forEach((item,i) => { if (products[i]) tx.set(`products/${item.productId}`, {...products[i], stock: products[i].stock + item.quantity, updatedAt: now}); });
      const updated = {...order, status: next, paymentStatus: body.paymentStatus || order.paymentStatus, stockRestored: order.stockRestored || restock, updatedAt: now,
        history: [...order.history, {status: next, paymentStatus: body.paymentStatus || order.paymentStatus, at: now, by: actor.uid}]};
      tx.set(`orders/${orderId}`, updated); return cleanOrder(updated);
    });
  }
  async saveProduct(productId, body, create = false) {
    productId = productId ? id(productId) : `product-${crypto.randomUUID()}`;
    const input = productInput(body, productId);
    return this.repo.transaction(async tx => {
      const [previous, category] = await Promise.all([tx.get(`products/${productId}`), tx.get(`categories/${input.categoryId}`)]);
      if (!category) fail(400, 'Select an existing category.');
      if (!create && !previous) fail(404, 'Product not found.');
      if (create && previous) fail(409, 'This product already exists.');
      const product = {...input, createdAt: previous?.createdAt || this.now(), updatedAt: this.now()}; tx.set(`products/${productId}`, product); return product;
    });
  }
  async deactivateProduct(productId) {
    return this.repo.transaction(async tx => { const p = await tx.get(`products/${id(productId)}`); if (!p) fail(404, 'Product not found.'); const product = {...p, isActive: false, updatedAt: this.now()}; tx.set(`products/${productId}`, product); return product; });
  }
  async saveCategory(categoryId, body, create = false) {
    categoryId = id(categoryId || body.id || `category-${crypto.randomUUID()}`);
    const category = {id: categoryId, name: text(body.name,'category name',2,80), description: text(body.description || '', 'category description', 0, 500), imagePath: body.imagePath ? imagePath(body.imagePath) : ''};
    return this.repo.transaction(async tx => { const old = await tx.get(`categories/${categoryId}`); if (create && old) fail(409,'This category already exists.'); if (!create && !old) fail(404,'Category not found.'); const next = {...category,createdAt:old?.createdAt || this.now(),updatedAt:this.now()};tx.set(`categories/${categoryId}`,next);return next; });
  }
  async deleteCategory(categoryId) {
    id(categoryId);
    return this.repo.transaction(async tx => {
      const [category, used] = await Promise.all([tx.get(`categories/${categoryId}`), tx.query('products', {categoryId, limit:1})]);
      if (!category) fail(404,'Category not found.'); if (used.length) fail(409,'Move all products to another category before deleting this category.'); tx.delete(`categories/${categoryId}`);
    });
  }
}
module.exports = {CommerceService, HttpError, fail, id, imagePath, productInput, cleanOrder};
