
import test from 'node:test';
import assert from 'node:assert/strict';
import seed from '../seed.json' with {type:'json'};
import {CommerceService} from '../lib/commerce.js';
import {MemoryRepository} from '../lib/repository.js';
import {createApp} from '../app.js';
import {XenditGateway} from '../lib/xendit.js';

function setup() {
  const initial = {};
  for (const category of seed.categories) initial[`categories/${category.id}`] = category;
  for (const product of seed.products) {
    const imagePath = `assets/images/products/${product.slug}.jpg`;
    initial[`products/${product.id}`] = {...product, imagePath, images: [imagePath]};
  }
  const repository = new MemoryRepository(initial);
  const commerce = new CommerceService(repository, {shipping: seed.shipping, now: () => '2026-10-26T00:00:00.000Z'});
  let providerSessionStatus = 'ACTIVE';
  let providerPaymentStatus = 'SUCCEEDED';
  let providerSessionAmountOffset = 0;
  let lastSessionRequest;
  let sessionCreateCount = 0;
  let sessionDelayMs = 0;
  let sessionFetchFailure = false;
  const sessionId = 'ps-661f87c614802d6c402cd82d';
  const paymentId = 'py-661f87c614802d6c402cd82d';
  const paymentRequestId = 'pr-661f87c614802d6c402cd82d';
  const gateway = new XenditGateway({
    secretKey: 'xnd_development_checkout-test-key',
    callbackToken: 'local-test-callback-token',
    fetchImpl: async (url, options = {}) => {
      if (url.endsWith('/sessions') && options.method === 'POST') {
        sessionCreateCount++;
        if (sessionDelayMs) await new Promise(resolve => setTimeout(resolve, sessionDelayMs));
        lastSessionRequest = JSON.parse(options.body);
        return reply(201, {payment_session_id: sessionId, reference_id: lastSessionRequest.reference_id, amount: lastSessionRequest.amount, currency: 'PHP', session_type: 'PAY', status: 'ACTIVE', payment_request_id: paymentRequestId, payment_link_url: `https://checkout-staging.xendit.co/sessions/${sessionId}`, expires_at: '2026-10-26T01:00:00.000Z'});
      }
      if (url.endsWith(`/sessions/${sessionId}`)) {
        if (sessionFetchFailure) return reply(503, {message: 'Provider unavailable.'});
        return reply(200, {payment_session_id: sessionId, reference_id: lastSessionRequest.reference_id, session_type: 'PAY', amount: lastSessionRequest.amount + providerSessionAmountOffset, currency: 'PHP', status: providerSessionStatus, payment_id: providerSessionStatus === 'COMPLETED' ? paymentId : null, payment_request_id: paymentRequestId, latest_payment_request_id: paymentRequestId});
      }
      if (url.endsWith(`/v3/payments/${paymentId}`)) {
        return reply(200, {payment_id: paymentId, reference_id: `${lastSessionRequest.reference_id}_attempt`, request_amount: lastSessionRequest.amount, currency: 'PHP', status: providerPaymentStatus, payment_request_id: paymentRequestId, metadata: lastSessionRequest.metadata});
      }
      if (url.endsWith(`/sessions/${sessionId}/cancel`)) {
        providerSessionStatus = 'CANCELED';
        return reply(200, {payment_session_id: sessionId, reference_id: lastSessionRequest.reference_id, status: providerSessionStatus});
      }
      throw new Error(`Unexpected Xendit request: ${url}`);
    },
  });
  const app = createApp({
    commerce,
    repository,
    xendit: gateway,
    supabaseAuth: {verifyIdToken: async token => token === 'test-customer' ? {uid: 'customer-test', email: 'customer@example.com'} : (() => {throw new Error('invalid token');})()},
  });
  return {
    app, repository, gateway, get lastSessionRequest() { return lastSessionRequest; },
    get sessionCreateCount() { return sessionCreateCount; },
    set sessionDelay(value) { sessionDelayMs = value; },
    set sessionFetchFailure(value) { sessionFetchFailure = value; },
    set sessionStatus(value) { providerSessionStatus = value; },
    set paymentStatus(value) { providerPaymentStatus = value; },
    set sessionAmountOffset(value) { providerSessionAmountOffset = value; },
  };
}

function reply(status, data) {
  return {ok: status >= 200 && status < 300, status, json: async () => data};
}

async function listening(t, app) {
  const server = app.listen(0);
  t.after(() => new Promise(resolve => server.close(resolve)));
  await new Promise(resolve => server.once('listening', resolve));
  return `http://127.0.0.1:${server.address().port}`;
}

async function post(url, route, body, headers = {}) {
  return fetch(`${url}${route}`, {
    method: 'POST',
    headers: {'content-type': 'application/json', authorization: 'Bearer test-customer', ...headers},
    body: JSON.stringify(body),
  });
}

const checkoutBody = suffix => ({
  customerName: 'Stationery Customer',
  contactNumber: '09123456789',
  address: '12 Stationery Street, Manila',
  items: [{productId: 'ibasho-001', quantity: 1}],
  paymentMethod: 'xendit',
  idempotencyKey: `xendit-checkout-test-${suffix}-unique`,
  // These are intentionally untrusted and must have no effect on the amount.
  amount: 0.01,
  price: 0.01,
});

async function beginCheckout(t, state, suffix = 'one') {
  const url = await listening(t, state.app);
  const response = await post(url, '/api/orders', checkoutBody(suffix));
  assert.equal(response.status, 201);
  const result = await response.json();
  return {url, order: result.order, paymentUrl: result.paymentUrl};
}

test('Xendit checkout creates a pending order and redirects with server-calculated PHP total', async t => {
  const state = setup();
  const {order, paymentUrl} = await beginCheckout(t, state);
  assert.equal(order.status, 'pending_payment');
  assert.equal(order.paymentStatus, 'unpaid');
  assert.equal(order.paymentMethod, 'xendit');
  assert.equal(order.total, 149);
  assert.equal(state.lastSessionRequest.amount, 149);
  assert.equal(state.lastSessionRequest.currency, 'PHP');
  assert.equal(state.lastSessionRequest.reference_id, order.reference);
  assert.equal(state.lastSessionRequest.customer.individual_detail.given_names, 'Stationery Customer');
  assert.equal(order.paymentUrl, paymentUrl);
  assert.match(paymentUrl, /^https:\/\/checkout-staging\.xendit\.co\//);
  assert.equal((await state.repository.get('products/ibasho-001')).stock, 39);
});

test('concurrent retries create only one Xendit session and reserve stock once', async t => {
  const state = setup();
  state.sessionDelay = 25;
  const url = await listening(t, state.app);
  const body = checkoutBody('concurrent');
  const responses = await Promise.all([
    post(url, '/api/orders', body),
    post(url, '/api/orders', body),
  ]);
  assert.equal(state.sessionCreateCount, 1);
  assert.deepEqual(responses.map(response => response.status).sort(), [201, 409]);
  assert.equal((await state.repository.get('products/ibasho-001')).stock, 39);
  const order = (await state.repository.list('orders'))[0];
  assert.equal(order.paymentStatus, 'unpaid');
  assert.ok(order.paymentSessionId);
});

test('Xendit diagnostics retain safe provider details without customer values', async () => {
  const gateway = new XenditGateway({
    secretKey: 'xnd_development_checkout-test-key',
    fetchImpl: async () => reply(400, {
      error_code: 'API_VALIDATION_ERROR',
      message: 'Rejected user@example.com at +639123456789',
      errors: [{path: '/body/customer/individual_detail'}],
    }),
  });
  await assert.rejects(
    gateway._request('/sessions', {
      method: 'POST',
      body: {customer: {email: 'user@example.com', mobile_number: '+639123456789'}},
    }),
    error => {
      assert.equal(error.diagnostics.httpStatus, 400);
      assert.equal(error.diagnostics.errorCode, 'API_VALIDATION_ERROR');
      assert.equal(error.diagnostics.endpoint, '/sessions');
      assert.deepEqual(error.diagnostics.validationPaths, ['/body/customer/individual_detail']);
      assert.doesNotMatch(error.diagnostics.safeMessage, /user@example\.com|\+639123456789/);
      return true;
    },
  );
});

test('retrying checkout returns the same pending payment session without reserving stock twice', async t => {
  const state = setup();
  const url = await listening(t, state.app);
  const body = checkoutBody('idempotent');
  const firstResponse = await post(url, '/api/orders', body);
  const first = await firstResponse.json();
  const secondResponse = await post(url, '/api/orders', body);
  const second = await secondResponse.json();

  assert.equal(firstResponse.status, 201);
  assert.equal(secondResponse.status, 201);
  assert.equal(second.order.id, first.order.id);
  assert.equal(second.paymentUrl, first.paymentUrl);
  assert.equal((await state.repository.get('products/ibasho-001')).stock, 39);
});

test('checking payment status verifies a completed Xendit session with the provider', async t => {
  const state = setup();
  const {url, order} = await beginCheckout(t, state, 'status-check');
  state.sessionStatus = 'COMPLETED';
  const response = await fetch(`${url}/api/me/orders/${encodeURIComponent(order.id)}`, {
    headers: {authorization: 'Bearer test-customer'},
  });
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.order.status, 'confirmed');
  assert.equal(result.order.paymentStatus, 'paid');
  assert.equal(result.order.xenditPaymentId, 'py-661f87c614802d6c402cd82d');
});

test('order history verifies completed Xendit payments when the callback was missed', async t => {
  const state = setup();
  const {url, order} = await beginCheckout(t, state, 'history-status-check');
  state.sessionStatus = 'COMPLETED';
  const response = await fetch(`${url}/api/me/orders`, {
    headers: {authorization: 'Bearer test-customer'},
  });
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.orders.length, 1);
  assert.equal(result.orders[0].id, order.id);
  assert.equal(result.orders[0].status, 'confirmed');
  assert.equal(result.orders[0].paymentStatus, 'paid');
});

test('order history reports when Xendit status could not be verified', async t => {
  const state = setup();
  const {url, order} = await beginCheckout(t, state, 'history-status-failure');
  state.sessionFetchFailure = true;
  const response = await fetch(`${url}/api/me/orders`, {
    headers: {authorization: 'Bearer test-customer'},
  });
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.paymentStatusRefreshFailures, 1);
  assert.equal(result.orders[0].id, order.id);
  assert.equal(result.orders[0].paymentStatus, 'unpaid');
});

test('a callback alone cannot mark an order paid; the session and Payment API must both verify', async t => {
  const state = setup();
  const {url, order} = await beginCheckout(t, state, 'verified');
  const forged = await post(url, '/api/xendit/webhook', {event: 'payment_session.completed', data: {reference_id: order.reference, payment_session_id: 'ps-forged', payment_id: 'py-forged'}}, {'x-callback-token': 'local-test-callback-token'});
  assert.equal(forged.status, 200);
  let stored = await state.repository.get(`orders/${order.id}`);
  assert.equal(stored.paymentStatus, 'unpaid');

  state.sessionStatus = 'COMPLETED';
  const paid = await post(url, '/api/xendit/webhook', {event: 'payment_session.completed', data: {reference_id: order.reference, payment_session_id: 'ps-661f87c614802d6c402cd82d', payment_id: 'py-661f87c614802d6c402cd82d'}}, {'x-callback-token': 'local-test-callback-token'});
  assert.equal(paid.status, 200);
  stored = await state.repository.get(`orders/${order.id}`);
  assert.equal(stored.status, 'confirmed');
  assert.equal(stored.paymentStatus, 'paid');
});

test('payment webhook with Xendit attempt suffix confirms the matching order', async t => {
  const state = setup();
  const {url, order} = await beginCheckout(t, state, 'payment-event-suffix');
  state.sessionStatus = 'COMPLETED';
  const response = await post(url, '/api/xendit/webhook', {
    event: 'payment.succeeded',
    data: {
      reference_id: `${order.reference}_C0qit8u7qN`,
      payment_id: 'py-661f87c614802d6c402cd82d',
      metadata: {order_id: order.id},
    },
  }, {'x-callback-token': 'local-test-callback-token'});
  assert.equal(response.status, 200);
  const stored = await state.repository.get(`orders/${order.id}`);
  assert.equal(stored.status, 'confirmed');
  assert.equal(stored.paymentStatus, 'paid');
});

test('payment is not verified when its payment request does not match the session', async t => {
  const state = setup();
  const {url, order} = await beginCheckout(t, state, 'mismatched-payment-request');
  state.sessionStatus = 'COMPLETED';
  const originalFetch = state.gateway.fetch;
  state.gateway.fetch = async (requestUrl, options) => {
    const response = await originalFetch(requestUrl, options);
    if (requestUrl.endsWith('/v3/payments/py-661f87c614802d6c402cd82d')) {
      const body = await response.json();
      return reply(200, {...body, payment_request_id: 'pr-unrelated'});
    }
    return response;
  };
  const response = await fetch(`${url}/api/me/orders/${encodeURIComponent(order.id)}`, {
    headers: {authorization: 'Bearer test-customer'},
  });
  assert.equal(response.status, 400);
  assert.equal((await state.repository.get(`orders/${order.id}`)).paymentStatus, 'unpaid');
});

test('failed payment remains unpaid and an invalid callback token is rejected', async t => {
  const state = setup();
  const {url, order} = await beginCheckout(t, state, 'failed');
  const invalidToken = await post(url, '/api/xendit/webhook', {event: 'payment_session.completed', data: {reference_id: order.reference}}, {'x-callback-token': 'wrong-token'});
  assert.equal(invalidToken.status, 401);

  state.paymentStatus = 'FAILED';
  const failure = await post(url, '/api/xendit/webhook', {event: 'payment.failure', data: {reference_id: order.reference, payment_id: 'py-661f87c614802d6c402cd82d'}}, {'x-callback-token': 'local-test-callback-token'});
  assert.equal(failure.status, 200);
  const stored = await state.repository.get(`orders/${order.id}`);
  assert.equal(stored.paymentStatus, 'failed');
  assert.equal(stored.status, 'pending_payment');
});

test('a completed session with a mismatched amount stays unpaid', async t => {
  const state = setup();
  const {url, order} = await beginCheckout(t, state, 'wrong-amount');
  state.sessionStatus = 'COMPLETED';
  state.sessionAmountOffset = 1;
  const response = await post(url, '/api/xendit/webhook', {event: 'payment_session.completed', data: {reference_id: order.reference, payment_session_id: 'ps-661f87c614802d6c402cd82d', payment_id: 'py-661f87c614802d6c402cd82d'}}, {'x-callback-token': 'local-test-callback-token'});
  assert.equal(response.status, 400);
  assert.equal((await state.repository.get(`orders/${order.id}`)).paymentStatus, 'unpaid');
});

test('session expiry cancels the pending order and releases stock once', async t => {
  const state = setup();
  const {url, order} = await beginCheckout(t, state, 'expired');
  state.sessionStatus = 'EXPIRED';
  const body = {event: 'payment_session.expired', data: {reference_id: order.reference, payment_session_id: 'ps-661f87c614802d6c402cd82d'}};
  const first = await post(url, '/api/xendit/webhook', body, {'x-callback-token': 'local-test-callback-token'});
  const second = await post(url, '/api/xendit/webhook', body, {'x-callback-token': 'local-test-callback-token'});
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  const stored = await state.repository.get(`orders/${order.id}`);
  assert.equal(stored.paymentStatus, 'expired');
  assert.equal(stored.stockRestored, true);
  assert.equal((await state.repository.get('products/ibasho-001')).stock, 40);
});

test('customer cancellation closes the Xendit session, restores stock and saves the cart once', async t => {
  const state = setup();
  const {url, order} = await beginCheckout(t, state, 'cancel');
  const response = await post(url, `/api/me/orders/${order.id}/cancel`, {});
  assert.equal(response.status, 200);
  const cancelled = (await response.json()).order;
  assert.equal(cancelled.status, 'cancelled');
  assert.equal(cancelled.paymentStatus, 'cancelled');
  assert.equal((await state.repository.get('products/ibasho-001')).stock, 40);
  assert.deepEqual((await state.repository.get('carts/customer-test')).items, [{productId: 'ibasho-001', quantity: 1}]);
  const retry = await post(url, `/api/me/orders/${order.id}/cancel`, {});
  assert.equal(retry.status, 200);
  assert.equal((await state.repository.get('products/ibasho-001')).stock, 40);
});


test('Local HTTP return URLs are omitted for Xendit Payment Sessions', async () => {
  const gateway = new XenditGateway({
    secretKey: 'xnd_development_checkout-test-key',
    returnUrl: 'http://localhost:50371',
    fetchImpl: async (url, options) => {
      const body = JSON.parse(options.body);
      assert.equal(body.success_return_url, undefined);
      assert.equal(body.cancel_return_url, undefined);
      return reply(201, {
        payment_session_id: 'ps-661f87c614802d6c402cd82d',
        payment_link_url: 'https://xen.to/TESTCHECKOUT',
        reference_id: body.reference_id, amount: body.amount, currency: 'PHP',
        status: 'ACTIVE',
      });
    },
  });
  const session = await gateway.createSession({
    id: 'order-test', reference: 'ref-test', uid: 'test-user',
    customerName: 'Sample Customer', email: 'user@example.com',
    contactNumber: '09123456789', shippingFee: 60, total: 189,
    items: [{productId: 'test-product', name: 'Pencil', categoryId: 'Stationery', price: 129, quantity: 1}],
  });
  assert.equal(session.url, 'https://xen.to/TESTCHECKOUT');
});


test('each order gets a unique Xendit customer reference even for the same user', async () => {
  const references = [];
  const gateway = new XenditGateway({
    secretKey: 'xnd_development_checkout-test-key',
    fetchImpl: async (url, options) => {
      const body = JSON.parse(options.body);
      references.push(body.customer.reference_id);
      return reply(201, {
        payment_session_id: `ps-${references.length}`,
        payment_link_url: `https://checkout-staging.xendit.co/sessions/${references.length}`,
        reference_id: body.reference_id, amount: body.amount, currency: 'PHP', status: 'ACTIVE',
      });
    },
  });
  const sample = {reference: 'ref-sample', uid: 'same-user', customerName: 'Sample',
    email: 'sample@example.com', contactNumber: '09123456789', shippingFee: 0, total: 65,
    items: [{productId: 'pen', name: 'Pen', categoryId: 'Stationery', price: 65, quantity: 1}]};
  await gateway.createSession({...sample, id: 'order-1', reference: 'ref-1'});
  await gateway.createSession({...sample, id: 'order-2', reference: 'ref-2'});
  assert.equal(references.length, 2);
  assert.notEqual(references[0], references[1]);
});
