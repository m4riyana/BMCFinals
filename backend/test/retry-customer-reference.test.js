'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { XenditGateway } = require('../lib/xendit');

test('Xendit retries same pending order use distinct customer reference IDs', async () => {
  const payloads = [];
  const gateway = new XenditGateway({
    secretKey: 'xnd_development_fake_test_key',
    fetchImpl: async (_url, options) => {
      const b = JSON.parse(options.body);
      payloads.push(b);
      return {ok:true,status:201,json:async()=>({
        payment_session_id: `ps-${payloads.length}`, reference_id:b.reference_id,
        amount:b.amount,currency:b.currency,status:'ACTIVE',
        payment_link_url:`https://checkout-staging.xendit.co/session/test-${payloads.length}`,
      })};
    },
  });
  const order = {
    id: 'order-existing',reference:'IB-order-existing',
    contactNumber:'09123456789',customerName:'Test Customer',email:'test@example.com',
    total:125,shippingFee:60,items:[{productId:'p1',name:'Pencil',price:65,quantity:1,categoryId:'pens'}],
  };
  await gateway.createSession(order);
  await gateway.createSession(order);
  assert.equal(payloads.length,2);
  assert.notEqual(payloads[0].customer.reference_id,payloads[1].customer.reference_id);
  assert.equal(payloads[0].reference_id,order.reference);
  assert.equal(payloads[1].reference_id,order.reference);
});
