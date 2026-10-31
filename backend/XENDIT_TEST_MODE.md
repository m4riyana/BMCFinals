# Xendit Test Mode checkout

The checkout page posts the product IDs, quantities, customer details, and a single-use retry key to the authenticated backend. The server snapshots catalog prices, calculates Philippine peso shipping and totals, records the pending order, then creates an Xendit Test Mode Payment Session. The Xendit secret stays on the server. A payment callback does not make an order paid by itself: the server fetches the session and Payment from Xendit and checks the order reference, session ID, PHP currency, and exact amount before recording success.

## Server setup

1. Copy `.env.example` to `.env`. Keep the development API key only in this server file and use the Xendit **Test Mode** secret.
2. Set `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, and `SUPABASE_DB_URL`, then run `../supabase/schema.sql` in the Supabase SQL Editor.
3. Start the existing API with `npm start` from `backend/`.
4. In the Xendit Test Mode dashboard, set the Payment Session status webhook to `https://<public-backend-host>/api/xendit/webhook`; copy the matching callback verification token into `XENDIT_CALLBACK_TOKEN` and restart the backend. Do not point this to a private localhost address.
5. Optionally set `XENDIT_RETURN_URL` in `backend/.env` to the deployed HTTPS storefront URL, not the backend or Supabase project URL. Pointing it at the API displays the backend health JSON after payment. The deployment script forwards this optional value. When no storefront return URL is available, leave it unset; customers can return to the app and check payment status, which the backend verifies directly with Xendit.

Checkout continues to use a server-side Xendit status check, so a missing or delayed callback cannot turn a pending order into a paid order. Failed payment attempts remain pending and can be retried using the active hosted session. Customers can cancel an active session; expired or canceled sessions restore the reserved stock and the cart. Duplicate callbacks and checkout retries are safe.

## Test

Run `npm test` from `backend/`. The Xendit tests mock both the provider API and Supabase identity: they cover a Test Mode session and redirect, server-calculated total, valid and forged or mismatched confirmation, failed payment, cancellation, expiration, and stock restoration. They do not make a live payment or require production credentials.
