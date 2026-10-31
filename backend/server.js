'use strict';

const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const express = require('express');
const cors = require('cors');
const multer = require('multer');
const sharp = require('sharp');
const {createSupabaseAuth} = require('./lib/supabase_auth');
require('dotenv').config({path: path.join(__dirname, '.env')});

const { CommerceService, HttpError, cleanOrder } = require('./lib/commerce');
const { SupabaseRepository } = require('./lib/supabase_repository');
const { XenditGateway, XenditError } = require('./lib/xendit');
const { ProfileService } = require('./lib/profile');
const seed = require('../catalog/products.json');

const uploadDirectory = path.join(__dirname, 'uploads', 'products');
const profileDirectory = path.join(__dirname, 'uploads', 'profiles');
const imageUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024, files: 1 },
});
const profileImageUpload = multer({
  storage: multer.memoryStorage(),
  limits: {fileSize: 5 * 1024 * 1024, files: 1},
});

async function seedCatalog(repository) {
  for (const category of seed.categories) {
    if (!(await repository.get(`categories/${category.id}`))) {
      await repository.set(`categories/${category.id}`, category);
    }
  }

  for (const product of seed.products) {
    if (!(await repository.get(`products/${product.id}`))) {
      const imagePath = product.imagePath || `assets/images/products/${product.slug}.jpg`;
      await repository.set(`products/${product.id}`, {
        ...product,
        imagePath,
        images: product.images || [imagePath],
        photoNote: product.photoNote || 'Representative generic product photograph; not a branded product.',
      });
    }
  }
}

async function removeProfilePhoto(photoPath, directory) {
  const match = /^\/uploads\/profiles\/([a-f0-9-]{36})\.webp$/.exec(photoPath || '');
  if (match) await fs.rm(path.join(directory, match[1] + '.webp'), {force: true});
}

function createApp({ commerce, repository, supabaseAuth, xendit = null, profiles = new ProfileService(repository), adminEmails = [], uploadsPath = uploadDirectory, profileUploadsPath = profileDirectory }) {
  const app = express();
  const allowedAdmins = new Set(adminEmails.map(email => email.trim().toLowerCase()));

  app.use(cors());
  app.use(express.json({ limit: '1mb' }));
  app.use('/uploads/products', express.static(uploadsPath, {
    fallthrough: false,
    immutable: true,
    maxAge: '1y',
  }));
  app.use('/uploads/profiles', express.static(profileUploadsPath, {
    fallthrough: false,
    immutable: true,
    maxAge: '1y',
  }));

  const authenticate = async (req, res, next) => {
    try {
      const authorization = req.get('authorization') || '';
      if (!authorization.startsWith('Bearer ')) {
        throw new HttpError(401, 'Please sign in to continue.');
      }
      req.user = await supabaseAuth.verifyIdToken(authorization.slice(7), true);
      next();
    } catch (error) {
      next(error instanceof HttpError ? error : new HttpError(401, 'Your session is invalid. Please sign in again.'));
    }
  };

  const requireAdmin = (req, res, next) => {
    const email = req.user.email?.toLowerCase();
    if (req.user.admin === true || (req.user.email_verified === true && allowedAdmins.has(email))) {
      next();
      return;
    }
    next(new HttpError(403, 'Administrator access is required.'));
  };

  app.get('/', (req, res) => res.json({ message: 'IBASHO STATIONERY backend is running.' }));
  app.get('/api/catalog', async (req, res) => res.json(await commerce.catalog()));

  app.post('/api/auth/username-login', async (req, res) => {
    const handle = typeof req.body?.username === 'string' ? req.body.username.trim() : '';
    const password = typeof req.body?.password === 'string' ? req.body.password : '';
    
    if (password.length < 1 || password.length > 4096) throw new HttpError(401, 'Incorrect username or password.');
    const uid = await profiles.uidForUsername(handle);
    if (!uid) throw new HttpError(401, 'Incorrect username or password.');

    let account;
    try { account = await supabaseAuth.getUser(uid); }
    catch (_) { throw new HttpError(401, 'Incorrect username or password.'); }
    if (account.disabled || !account.email) throw new HttpError(401, 'Incorrect username or password.');

    try {
      const session = await supabaseAuth.loginWithPassword(account.email,password);
      if(session.uid !== uid) throw new Error('Account mismatch');
      res.json({email:account.email});
    } catch (_) { throw new HttpError(401, 'Incorrect username or password.'); }
  });

  app.get('/api/me', authenticate, (req, res) => {
    const email = req.user.email?.toLowerCase();
    res.json({
      email: req.user.email || '',
      isAdmin: req.user.admin === true || (req.user.email_verified === true && allowedAdmins.has(email)),
    });
  });
  app.get('/api/me/profile', authenticate, async (req, res) => {
    res.json({profile: await profiles.get(req.user.uid, req.user.email || '')});
  });
  app.put('/api/me/profile', authenticate, async (req, res) => {
    res.json({profile: await profiles.save(req.user.uid, req.user.email || '', req.body)});
  });
  app.post('/api/me/profile/photo', authenticate, profileImageUpload.single('image'), async (req, res) => {
    if (!req.file) throw new HttpError(400, 'Choose a profile picture.');
    let metadata;
    try { metadata = await sharp(req.file.buffer).metadata(); }
    catch (_) { throw new HttpError(400, 'Upload a valid JPEG, PNG, or WebP image.'); }
    if (!['jpeg', 'png', 'webp'].includes(metadata.format)) throw new HttpError(400, 'Upload a valid JPEG, PNG, or WebP image.');
    if ((metadata.width || 0) * (metadata.height || 0) > 24000000) throw new HttpError(400, 'Choose an image with a maximum size of 24 megapixels.');
    const fileName = `${crypto.randomUUID()}.webp`;
    const target = path.join(profileUploadsPath, fileName);
    await fs.mkdir(profileUploadsPath, {recursive: true});
    try {
      await sharp(req.file.buffer).rotate().resize(512, 512, {fit: 'cover', withoutEnlargement: true}).webp({quality: 82}).toFile(target);
      const previous = await profiles.get(req.user.uid, req.user.email || '');
      const updated = await profiles.setPhoto(req.user.uid, `/uploads/profiles/${fileName}`);
      await removeProfilePhoto(previous.profilePhotoPath, profileUploadsPath).catch(() => {});
      res.status(201).json({profile: {...updated, email: req.user.email || ''}});
    } catch (error) {
      await fs.rm(target, {force: true}).catch(() => {});
      throw error;
    }
  });
  app.delete('/api/me/profile/photo', authenticate, async (req, res) => {
    const previous = await profiles.get(req.user.uid, req.user.email || '');
    const updated = await profiles.setPhoto(req.user.uid, '');
    await removeProfilePhoto(previous.profilePhotoPath, profileUploadsPath).catch(() => {});
    res.json({profile: {...updated, email: req.user.email || ''}});
  });
  app.get('/api/me/cart', authenticate, async (req, res) => res.json(await commerce.getCart(req.user.uid)));
  app.put('/api/me/cart', authenticate, async (req, res) => res.json(await commerce.saveCart(req.user.uid, req.body)));
  app.get('/api/me/wishlist', authenticate, async (req, res) => res.json(await commerce.getWishlist(req.user.uid)));
  app.put('/api/me/wishlist', authenticate, async (req, res) => res.json(await commerce.saveWishlist(req.user.uid, req.body)));
  app.get('/api/me/orders', authenticate, async (req, res) => {
    const orders = await commerce.orders(req.user.uid);
    let paymentStatusRefreshFailures = 0;
    const refreshedOrders = await Promise.all(orders.map(async order => {
      if (order.paymentMethod !== 'xendit' || !xendit ||
          ['paid', 'cancelled', 'expired'].includes(order.paymentStatus)) return order;
      try {
        return await syncXenditOrder(commerce, xendit, req.user.uid, order.id);
      } catch (error) {
        paymentStatusRefreshFailures++;
        console.error(`Unable to refresh Xendit status for order ${order.id}:`, error);
        return order;
      }
    }));
    res.json({ orders: refreshedOrders, paymentStatusRefreshFailures });
  });
  app.get('/api/me/orders/:id', authenticate, async (req, res) => {
    const order = await commerce.order(req.user.uid, req.params.id);
    res.json({order: order.paymentMethod === 'xendit' && xendit
      ? await syncXenditOrder(commerce, xendit, req.user.uid, order.id)
      : order});
  });
  app.post('/api/me/orders/:id/cancel', authenticate, async (req, res) => {
    if (!xendit) throw new HttpError(503, 'Xendit Test Mode is not configured.');
    const order = await commerce.order(req.user.uid, req.params.id);
    if (order.paymentStatus === 'paid') throw new HttpError(409, 'This order is already paid.');
    if (order.paymentStatus === 'cancelled' || order.paymentStatus === 'expired') return res.json({order});
    if (order.paymentMethod !== 'xendit' || !order.paymentSessionId) throw new HttpError(409, 'This order has no active payment session.');
    let session;
    try { session = await xendit.cancelSession(order.paymentSessionId); }
    catch (error) {
      // If payment completed while cancellation was in progress, verify the
      // provider's final state instead of ever cancelling or refunding it here.
      if (error.status !== 400) throw error;
      const current = await xendit.getSession(order.paymentSessionId);
      if (current.status === 'COMPLETED') {
        const paid = await verifyCompletedSession(xendit, order, current);
        return res.json({order: await commerce.confirmXenditPayment(order.id, paid)});
      }
      if (!['CANCELED', 'EXPIRED'].includes(current.status)) throw error;
      session = current;
    }
    res.json({order: await commerce.finishXenditSession(order.id, {uid: req.user.uid, sessionId: order.paymentSessionId, status: session.status})});
  });
  app.post('/api/orders', authenticate, async (req, res) => {
    const method = req.body.paymentMethod || 'cod';
    if (method === 'cod') return res.status(201).json({ order: await commerce.checkout(req.user, req.body, 'cod') });
    if (method !== 'xendit') throw new HttpError(400, 'Unsupported payment method.');
    if (!xendit) throw new HttpError(503, 'Xendit Test Mode is not configured.');
    const pending = await commerce.checkout(req.user, req.body, 'xendit');
    let order = pending;
    if (!pending.paymentSessionId || !pending.paymentUrl) {
      const claim = await commerce.claimPaymentSession(pending.id, req.user.uid);
      if (!claim.claimed) {
        order = claim.order;
      } else {
        try {
          const session = await xendit.createSession(claim.order);
          order = await commerce.attachPaymentSession(pending.id, session, req.user.uid);
        } catch (error) {
          await commerce.releasePaymentSessionClaim(pending.id, req.user.uid);
          throw error;
        }
      }
    }
    res.status(201).json({order, paymentUrl: order.paymentUrl});
  });

  app.post('/api/xendit/webhook', async (req, res) => {
    if (!xendit || !xendit.verifyCallbackToken(req.get('x-callback-token'))) {
      throw new HttpError(401, 'Invalid payment callback.');
    }
    const event = req.body?.event;
    const data = req.body?.data;
    if (!data || typeof data !== 'object') throw new HttpError(400, 'Invalid payment callback.');
    if (!['payment_session.completed', 'payment_session.expired', 'payment.capture', 'payment.succeeded', 'payment.failure'].includes(event)) {
      return res.status(200).json({received: true});
    }

    const orderId = paymentEventOrderId(data);
    let order = null;
    if (orderId) {
      try { order = await commerce.order('', orderId, true); }
      catch (error) {
        if (!(error instanceof HttpError) || error.status !== 404) throw error;
      }
    }
    if (!order || order.paymentMethod !== 'xendit' || !order.paymentSessionId) {
      // Unknown or stale notifications are safely acknowledged; they cannot
      // change any customer's order.
      return res.status(200).json({received: true});
    }

    if (event === 'payment_session.expired') {
      const session = await xendit.getSession(order.paymentSessionId);
      if (session.payment_session_id === order.paymentSessionId && session.reference_id === order.reference && session.status === 'EXPIRED') {
        await commerce.finishXenditSession(order.id, {sessionId: order.paymentSessionId, status: session.status});
      }
    } else if (event === 'payment.failure') {
      const paymentId = data.payment_id;
      if (typeof paymentId === 'string') {
        const session = await xendit.getSession(order.paymentSessionId);
        const payment = await xendit.getPayment(paymentId);
        const paymentRequestId = session.latest_payment_request_id || session.payment_request_id;
        if (session.payment_session_id === order.paymentSessionId &&
            session.reference_id === order.reference &&
            payment.payment_id === paymentId && payment.status === 'FAILED' &&
            payment.metadata?.order_id === order.id &&
            (payment.reference_id === order.reference || payment.reference_id?.startsWith(`${order.reference}_`)) &&
            paymentRequestId && payment.payment_request_id === paymentRequestId &&
            payment.currency === 'PHP' && Math.round(Number(payment.request_amount) * 100) === Math.round(order.total * 100)) {
          await commerce.markPaymentFailure(order.id, paymentId);
        }
      }
    } else {
      const session = await xendit.getSession(order.paymentSessionId);
      if (session.payment_session_id !== order.paymentSessionId || session.reference_id !== order.reference) {
        return res.status(200).json({received: true});
      }
      if (session.status === 'COMPLETED') {
        const verified = await verifyCompletedSession(xendit, order, session, data.payment_id);
        await commerce.confirmXenditPayment(order.id, verified);
      }
    }
    res.status(200).json({received: true});
  });

  app.get('/api/admin/products', authenticate, requireAdmin, async (req, res) => {
    const result = await commerce.catalog(true);
    res.json({ products: result.products });
  });
  app.post('/api/admin/products', authenticate, requireAdmin, async (req, res) => {
    res.status(201).json({ product: await commerce.saveProduct(null, req.body, true) });
  });
  app.put('/api/admin/products/:id', authenticate, requireAdmin, async (req, res) => {
    res.json({ product: await commerce.saveProduct(req.params.id, req.body) });
  });
  app.delete('/api/admin/products/:id', authenticate, requireAdmin, async (req, res) => {
    res.json({ product: await commerce.deactivateProduct(req.params.id) });
  });

  app.get('/api/admin/categories', authenticate, requireAdmin, async (req, res) => {
    const result = await commerce.catalog(true);
    res.json({ categories: result.categories });
  });
  app.post('/api/admin/categories', authenticate, requireAdmin, async (req, res) => {
    res.status(201).json({ category: await commerce.saveCategory(null, req.body, true) });
  });
  app.put('/api/admin/categories/:id', authenticate, requireAdmin, async (req, res) => {
    res.json({ category: await commerce.saveCategory(req.params.id, req.body) });
  });
  app.delete('/api/admin/categories/:id', authenticate, requireAdmin, async (req, res) => {
    await commerce.deleteCategory(req.params.id);
    res.json({ deleted: true });
  });

  app.get('/api/admin/orders', authenticate, requireAdmin, async (req, res) => {
    const orders = await repository.list('orders', { limit: 100 });
    res.json({ orders: orders.map(cleanOrder) });
  });
  app.patch('/api/admin/orders/:id', authenticate, requireAdmin, async (req, res) => {
    res.json({ order: await commerce.updateOrder(req.params.id, req.body, req.user) });
  });

  app.post(
    '/api/admin/images',
    authenticate,
    requireAdmin,
    imageUpload.single('image'),
    async (req, res) => {
      if (!req.file) throw new HttpError(400, 'Choose an image to upload.');

      let metadata;
      try {
        metadata = await sharp(req.file.buffer, { failOn: 'error' }).metadata();
      } catch {
        throw new HttpError(400, 'Choose a valid JPG, PNG, or WebP image.');
      }
      if (!['jpeg', 'png', 'webp'].includes(metadata.format)) {
        throw new HttpError(400, 'Choose a JPG, PNG, or WebP image.');
      }

      await fs.mkdir(uploadsPath, { recursive: true });
      const filename = `${crypto.randomUUID()}.webp`;
      await sharp(req.file.buffer)
        .rotate()
        .resize(1600, 1600, { fit: 'inside', withoutEnlargement: true })
        .webp({ quality: 82 })
        .toFile(path.join(uploadsPath, filename));
      res.status(201).json({ imagePath: `/uploads/products/${filename}` });
    },
  );

  app.use((error, req, res, next) => {
    if (res.headersSent) {
      next(error);
      return;
    }
    if (error instanceof multer.MulterError) {
      const status = error.code === 'LIMIT_FILE_SIZE' ? 413 : 400;
      res.status(status).json({ error: status === 413 ? 'Choose an image smaller than 5 MB.' : 'Invalid image upload.' });
      return;
    }
    const status = error instanceof HttpError || error instanceof XenditError ? error.status : error.statusCode || 500;
    if (error instanceof XenditError) {
      console.error('Xendit API request failed:', JSON.stringify(error.diagnostics));
    } else if (status >= 500) console.error('Commerce request failed:', error);
    res.status(status).json({
      error: error instanceof HttpError || error instanceof XenditError
        ? error.message
        : status >= 500 ? 'The store could not complete this request.' : error.message,
      ...(error.code ? { code: error.code } : {}),
    });
  });

  return app;
}

async function verifyCompletedSession(xendit, order, session, callbackPaymentId) {
  const amountMatches = Math.round(Number(session.amount) * 100) === Math.round(order.total * 100);
  if (session.status !== 'COMPLETED' || session.session_type !== 'PAY' || session.currency !== 'PHP' || !amountMatches ||
      session.payment_session_id !== order.paymentSessionId || session.reference_id !== order.reference) {
    throw new HttpError(400, 'Payment confirmation does not match the pending order.');
  }
  const paymentId = session.payment_id || session.latest_payment_id;
  if (!paymentId || (callbackPaymentId && callbackPaymentId !== paymentId)) {
    throw new HttpError(400, 'Xendit has not confirmed the payment for this order.');
  }
  const payment = await xendit.getPayment(paymentId);
  const paymentRequestId = session.latest_payment_request_id || session.payment_request_id;
  const paymentBelongsToOrder = payment.metadata?.order_id === order.id &&
    typeof payment.reference_id === 'string' &&
    (payment.reference_id === order.reference || payment.reference_id.startsWith(`${order.reference}_`));
  if (payment.payment_id !== paymentId || payment.status !== 'SUCCEEDED' || !paymentBelongsToOrder ||
      !paymentRequestId || payment.payment_request_id !== paymentRequestId ||
      payment.currency !== 'PHP' || Math.round(Number(payment.request_amount) * 100) !== Math.round(order.total * 100)) {
    throw new HttpError(400, 'Xendit payment verification did not match the pending order.');
  }
  return {sessionId: session.payment_session_id, paymentId, reference: order.reference};
}

function paymentEventOrderId(data) {
  const metadataOrderId = typeof data.metadata?.order_id === 'string' ? data.metadata.order_id : '';
  const reference = typeof data.reference_id === 'string' ? data.reference_id : '';
  const referenceOrderId = /^IB-[a-f0-9-]{36}$/.test(reference)
    ? reference
    : /^(IB-[a-f0-9-]{36})_[A-Za-z0-9]+$/.exec(reference)?.[1] || '';
  if (metadataOrderId && referenceOrderId && metadataOrderId !== referenceOrderId) return '';
  return metadataOrderId || referenceOrderId;
}

async function syncXenditOrder(commerce, xendit, uid, orderId) {
  const order = await commerce.order(uid, orderId);
  if (order.paymentMethod !== 'xendit' || !order.paymentSessionId ||
      ['paid', 'cancelled', 'expired'].includes(order.paymentStatus)) return order;
  const session = await xendit.getSession(order.paymentSessionId);
  if (session.payment_session_id !== order.paymentSessionId || session.reference_id !== order.reference) {
    throw new HttpError(409, 'Xendit payment session does not match this order.');
  }
  if (session.status === 'COMPLETED') {
    return commerce.confirmXenditPayment(order.id, await verifyCompletedSession(xendit, order, session));
  }
  if (session.status === 'EXPIRED' || session.status === 'CANCELED') {
    return commerce.finishXenditSession(order.id, {uid, sessionId: session.payment_session_id, status: session.status});
  }
  return order;
}

async function start() {
  for(const key of ['SUPABASE_URL','SUPABASE_ANON_KEY','SUPABASE_SERVICE_ROLE_KEY','SUPABASE_DB_URL']) {
    if(!process.env[key]) throw new Error(`Missing ${key} in backend/.env`);
  }
  const repository = new SupabaseRepository(process.env.SUPABASE_DB_URL);
  const supabaseAuth = createSupabaseAuth(process.env.SUPABASE_URL,process.env.SUPABASE_ANON_KEY,process.env.SUPABASE_SERVICE_ROLE_KEY);
  await seedCatalog(repository);
  const commerce = new CommerceService(repository, {
    shipping: seed.shipping,
  });
  const secretKey = process.env.XENDIT_SECRET_KEY || '';
  const xendit = secretKey
    ? new XenditGateway({
        secretKey,
        callbackToken: process.env.XENDIT_CALLBACK_TOKEN,
        returnUrl: process.env.XENDIT_RETURN_URL,
      })
    : null;
  const app = createApp({
    commerce,
    repository,
    supabaseAuth: supabaseAuth,
    xendit,
    adminEmails: (process.env.ADMIN_EMAILS || '').split(',').filter(Boolean),
  });
  const port = Number(process.env.PORT || 3000);
  app.listen(port, () => console.log(`IBASHO STATIONERY backend running on http://localhost:${port}`));
}

if (require.main === module) {
  start().catch(error => {
    console.error('Unable to start the commerce backend:', error);
    process.exitCode = 1;
  });
}

module.exports = { createApp, seedCatalog, verifyCompletedSession, syncXenditOrder, paymentEventOrderId };
