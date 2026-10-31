'use strict';

const crypto = require('node:crypto');

class XenditError extends Error {
  constructor(message, status = 502, diagnostics = {}) {
    super(message);
    this.status = status;
    this.diagnostics = diagnostics;
  }
}

function safeProviderMessage(message, body, secretKey) {
  if (typeof message !== 'string') return 'Xendit returned an error.';
  const values = [];
  if (secretKey) values.push(secretKey);
  const collect = value => {
    if (typeof value === 'string' && value.length >= 3) values.push(value);
    else if (Array.isArray(value)) value.forEach(collect);
    else if (value && typeof value === 'object') Object.values(value).forEach(collect);
  };
  collect(body);
  let safe = message;
  for (const value of [...new Set(values)].sort((a, b) => b.length - a.length)) {
    safe = safe.split(value).join('[redacted]');
  }
  return safe
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[redacted email]')
    .replace(/\+?\d[\d\s().-]{7,}\d/g, '[redacted number]')
    .slice(0, 500);
}

class XenditGateway {
  constructor({secretKey, callbackToken, returnUrl, fetchImpl = fetch}) {
    // Test Mode is enforced server-side so a misconfigured live key cannot
    // accidentally create a real charge during this integration.
    if (typeof secretKey !== 'string' || !secretKey.startsWith('xnd_development_')) {
      throw new XenditError('Set XENDIT_SECRET_KEY to a Xendit Test Mode development key.', 503);
    }
    this.secretKey = secretKey;
    this.callbackToken = callbackToken || '';
    // Payment Sessions require HTTPS return URLs. Local Flutter HTTP URLs
    // are not reachable from Xendit; omit them during local Test Mode.
    this.returnUrl = returnUrl && /^https:\/\//i.test(returnUrl) ? returnUrl : '';
    this.fetch = fetchImpl;
    this.baseUrl = 'https://api.xendit.co';
    this.auth = `Basic ${Buffer.from(`${secretKey}:`).toString('base64')}`;
  }

  async _request(path, {method = 'GET', body, apiVersion} = {}) {
    const endpoint = path
      .replace(/\/sessions\/[^/]+/g, '/sessions/:id')
      .replace(/\/v3\/payments\/[^/]+/g, '/v3/payments/:id');
    let response;
    try {
      response = await this.fetch(`${this.baseUrl}${path}`, {
        method,
        headers: {
          authorization: this.auth,
          ...(body ? {'content-type': 'application/json'} : {}),
          ...(apiVersion ? {'api-version': apiVersion} : {}),
        },
        ...(body ? {body: JSON.stringify(body)} : {}),
        signal: AbortSignal.timeout(15000),
      });
    } catch (error) {
      throw new XenditError(
        'Xendit is temporarily unavailable. Your pending order is safe; try again.',
        502,
        {endpoint, httpStatus: null, errorCode: null, safeMessage: 'Xendit request could not reach the provider.'},
      );
    }
    let data;
    try { data = await response.json(); }
    catch (_) {
      throw new XenditError('Xendit returned an unreadable response.', 502, {
        endpoint,
        httpStatus: response.status,
        errorCode: null,
        safeMessage: 'Xendit returned an unreadable response.',
      });
    }
    if (!response.ok) {
      const providerError = data && typeof data === 'object' ? data : {};
      const validationPaths = Array.isArray(providerError.errors)
        ? providerError.errors
          .map(error => typeof error?.path === 'string' ? error.path : null)
          .filter(Boolean)
          .slice(0, 10)
        : [];
      throw new XenditError(response.status === 401 || response.status === 403
        ? 'Xendit checkout is unavailable because the store payment key is invalid or lacks permission. Please contact the store.'
        : response.status >= 500
        ? 'Xendit is temporarily unavailable. Your pending order is safe; try again.'
        : 'Xendit could not accept the checkout details. Your order is saved as pending; please retry or contact support.',
      response.status >= 500 ? 502 : 400, {
        endpoint,
        httpStatus: response.status,
        errorCode: typeof providerError.error_code === 'string' ? providerError.error_code.slice(0, 100) : null,
        safeMessage: safeProviderMessage(providerError.message, body, this.secretKey),
        validationPaths,
      });
    }
    return data;
  }

  async createSession(order) {
    const contact = order.contactNumber.startsWith('+63')
      ? order.contactNumber
      : `+63${order.contactNumber.slice(1)}`;
    const items = order.items.map(item => ({
      reference_id: item.productId,
      name: item.name,
      description: `IBASHO STATIONERY order ${order.reference}`,
      type: 'PHYSICAL_PRODUCT',
      category: item.categoryId || 'Stationery',
      net_unit_amount: Number(item.price.toFixed(2)),
      quantity: item.quantity,
      currency: 'PHP',
    }));
    if (order.shippingFee > 0) {
      items.push({reference_id: `${order.id}-shipping`, name: 'Shipping', type: 'FEE', category: 'Shipping', net_unit_amount: Number(order.shippingFee.toFixed(2)), quantity: 1, currency: 'PHP'});
    }
    const body = {
      reference_id: order.reference,
      session_type: 'PAY',
      mode: 'PAYMENT_LINK',
      amount: Number(order.total.toFixed(2)),
      currency: 'PHP',
      country: 'PH',
      locale: 'en',
      description: `IBASHO STATIONERY order ${order.reference}`,
      customer: {
        // Xendit requires a new customer.reference_id for EVERY new session,
        // including retries of the SAME pending order after a failed attempt.
        // Keep order.reference unchanged for order/payment reconciliation.
        reference_id: `cust-${crypto.randomUUID()}`,
        type: 'INDIVIDUAL',
        individual_detail: {given_names: order.customerName},
        ...(order.email ? {email: order.email} : {}),
        mobile_number: contact,
      },
      items,
      metadata: {order_id: order.id},
      ...(this.returnUrl ? {
        success_return_url: `${this.returnUrl}?order=${encodeURIComponent(order.id)}&payment=success`,
        cancel_return_url: `${this.returnUrl}?order=${encodeURIComponent(order.id)}&payment=cancelled`,
      } : {}),
    };
    const session = await this._request('/sessions', {method: 'POST', body});
    let link;
    try { link = new URL(session.payment_link_url); }
    catch (_) { throw new XenditError('Xendit did not return a valid checkout link.'); }
    if (link.protocol !== 'https:' || !['checkout-staging.xendit.co', 'dev.xen.to', 'xen.to'].includes(link.hostname)) {
      throw new XenditError('Xendit did not return a Test Mode checkout link.');
    }
    if (session.reference_id !== order.reference || Number(session.amount) !== Number(order.total.toFixed(2)) || session.currency !== 'PHP') {
      throw new XenditError('Xendit returned a checkout session that did not match this order.');
    }
    return {id: session.payment_session_id, url: session.payment_link_url, status: session.status, expiresAt: session.expires_at || null};
  }

  getSession(id) { return this._request(`/sessions/${encodeURIComponent(id)}`); }

  getPayment(id) { return this._request(`/v3/payments/${encodeURIComponent(id)}`, {apiVersion: '2024-11-11'}); }

  async cancelSession(id) {
    return this._request(`/sessions/${encodeURIComponent(id)}/cancel`, {method: 'POST'});
  }

  verifyCallbackToken(value) {
    if (!this.callbackToken || typeof value !== 'string') return false;
    const expected = Buffer.from(this.callbackToken);
    const provided = Buffer.from(value);
    return expected.length === provided.length && crypto.timingSafeEqual(expected, provided);
  }
}

module.exports = {XenditGateway, XenditError};
