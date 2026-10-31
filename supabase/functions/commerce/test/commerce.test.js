
import test from 'node:test';
import assert from 'node:assert/strict';
import seed from '../seed.json' with {type:'json'};
import { CommerceService } from '../lib/commerce.js';
import { MemoryRepository } from '../lib/repository.js';
import { createApp, seedCatalog } from '../app.js';

function createCommerce() {
  const data = {};
  for (const category of seed.categories) {
    data[`categories/${category.id}`] = category;
  }
  for (const product of seed.products) {
    const imagePath = `assets/images/products/${product.slug}.jpg`;
    data[`products/${product.id}`] = {
      ...product,
      imagePath,
      images: [imagePath],
    };
  }
  const repository = new MemoryRepository(data);
  return {
    repository,
    service: new CommerceService(repository, {
      shipping: seed.shipping,
      now: () => '2026-10-26T00:00:00.000Z',
    }),
  };
}

test('checkout uses catalog prices, reserves stock, and is idempotent', async () => {
  const { repository, service } = createCommerce();
  const user = { uid: 'customer-1', email: 'customer@example.com' };
  const request = {
    customerName: 'A Customer',
    contactNumber: '09123456789',
    address: '12 Stationery Street, Manila',
    items: [{ productId: 'ibasho-001', quantity: 2 }],
    idempotencyKey: 'checkout-request-unique-001',
  };

  const first = await service.checkout(user, request);
  const retry = await service.checkout(user, request);

  assert.equal(first.id, retry.id);
  assert.equal(first.items[0].price, 89);
  assert.equal(first.subtotal, 178);
  assert.equal(first.shippingFee, 60);
  assert.equal(first.paymentStatus, 'unpaid');
  assert.equal((await repository.get('products/ibasho-001')).stock, 38);
  assert.deepEqual((await service.getCart(user.uid)).items, []);
});

test('checkout rejects invalid contact details without changing stock', async () => {
  const { repository, service } = createCommerce();

  await assert.rejects(
    service.checkout(
      { uid: 'customer-2' },
      {
        customerName: 'A Customer',
        contactNumber: '123',
        address: '12 Stationery Street, Manila',
        items: [{ productId: 'ibasho-001', quantity: 1 }],
        idempotencyKey: 'checkout-request-unique-002',
      },
    ),
    /contact number/,
  );
  assert.equal((await repository.get('products/ibasho-001')).stock, 40);
});

test('cancelling an unpaid cash order restores inventory once', async () => {
  const { repository, service } = createCommerce();
  const user = { uid: 'customer-3', email: 'customer@example.com' };
  const order = await service.checkout(user, {
    customerName: 'A Customer',
    contactNumber: '09123456789',
    address: '12 Stationery Street, Manila',
    items: [{ productId: 'ibasho-002', quantity: 3 }],
    idempotencyKey: 'checkout-request-unique-003',
  });

  await service.updateOrder(order.id, { status: 'cancelled' }, user);
  await service.updateOrder(order.id, { status: 'cancelled' }, user);

  assert.equal((await repository.get('products/ibasho-002')).stock, 35);
  assert.equal((await repository.get(`orders/${order.id}`)).stockRestored, true);
});

test('commerce API protects account and admin routes with Supabase bearer auth', async t => {
  const { repository, service } = createCommerce();
  const app = createApp({
    commerce: service,
    repository,
    supabaseAuth: {
      verifyIdToken: async token => {
        if (token === 'invalid') throw new Error('Invalid token');
        return {
          uid: 'api-user',
          email: token === 'admin' ? 'admin@example.com' : 'customer@example.com',
          email_verified: true,
          admin: token === 'admin',
        };
      },
    },
    adminEmails: ['admin@example.com'],
  });
  const server = app.listen(0);
  t.after(() => new Promise(resolve => server.close(resolve)));
  await new Promise(resolve => server.once('listening', resolve));
  const address = server.address();
  const baseUrl = `http://127.0.0.1:${address.port}`;

  const publicCatalog = await fetch(`${baseUrl}/api/catalog`);
  assert.equal(publicCatalog.status, 200);
  assert.equal((await publicCatalog.json()).products.length, 10);

  const unauthenticatedCart = await fetch(`${baseUrl}/api/me/cart`);
  assert.equal(unauthenticatedCart.status, 401);

  const forbidden = await fetch(`${baseUrl}/api/admin/products`, {
    headers: { authorization: 'Bearer customer' },
  });
  assert.equal(forbidden.status, 403);

  const adminProducts = await fetch(`${baseUrl}/api/admin/products`, {
    headers: { authorization: 'Bearer admin' },
  });
  assert.equal(adminProducts.status, 200);
  assert.equal((await adminProducts.json()).products.length, 10);
});

test('catalog seeding preserves existing inventory and creates new product records', async () => {
  const repository = new MemoryRepository({
    'products/ibasho-001': {
      ...seed.products[0],
      imagePath: 'assets/images/products/custom-notebook.jpg',
      stock: 7,
    },
  });

  await seedCatalog(repository);

  const existing = await repository.get('products/ibasho-001');
  const seeded = await repository.get('products/ibasho-010');
  assert.equal(existing.stock, 7);
  assert.equal(existing.imagePath, 'assets/images/products/custom-notebook.jpg');
  assert.equal(seeded.imagePath, 'assets/images/products/desk-organizer.jpg');
  assert.match(seeded.photoNote, /Representative generic/);
  assert.equal((await repository.list('products')).length, 10);
});
