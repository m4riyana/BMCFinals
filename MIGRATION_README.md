# IBASHO STATIONERY — Supabase + Xendit migration

## What changed
- Existing Flutter IBASHO UI preserved; Firebase SDK imports replaced with Supabase Auth.
- Separate Dart files: `config/supabase_config.dart`, `services/auth_service.dart`, `services/customer_service.dart`, `services/product_service.dart`, `services/orders_service.dart`, `services/payment_service.dart`.
- Existing Node/Express checkout and Xendit gateway retained.
- Backend data operations now use PostgreSQL `ibasho_documents` through `pg` with transaction/advisory locking.
- Supabase Auth access tokens are verified server-side using Supabase Admin client.
- No credentials are included. No Firebase user data has been migrated.

## Setup
1. Use the BMCFINALS Supabase project at `https://yvzulpfohcxkfkbfwvmk.supabase.co` (already configured as the Flutter default and in `backend/.env.example`), and enable Email auth. Decide whether email confirmation is required. For immediate sign-up testing, turn off confirmation in a TEST project or confirm email before login.
2. In Supabase SQL Editor run `supabase/schema.sql`.
3. Copy `backend/.env.example` to `backend/.env`; fill in new Supabase URL, publishable/anon key, service role key, DB connection URL, and Xendit **TEST** credentials. Never expose backend keys in Flutter or Git. DB URL may require pooler address depending on network/IPv4 support.
4. In `backend`: run `npm install` then `npm start`.
5. In `myapp`: run `flutter pub get`, then `flutter run -d chrome --dart-define=SUPABASE_URL=https://... --dart-define=SUPABASE_ANON_KEY=... --dart-define=BACKEND_URL=http://localhost:3000`.
6. For Android, build with a backend HTTPS URL reachable from the phone; `localhost` is not your laptop on the phone. Configure Android SDK and internet access.
7. Configure Xendit callback/webhook endpoint on a public HTTPS backend at `/api/xendit/webhook`, using the same callback token as backend `.env`. Xendit must verify payment server-side before marking an order paid.

## Connection status

The code uses Supabase Auth and Supabase PostgreSQL. Live setup still requires running `supabase/schema.sql` and filling in the private backend environment values; the screenshot contains no API keys or database password. No live database connection or data transfer has been performed. The schema can be rerun safely.

## Important limitations and checks
- This is a migration code package, not a verified deployed app. Run `flutter analyze`, backend tests and end-to-end signup, checkout and webhook tests after adding credentials. SDK versions may require minor adjustments.
- Existing Firebase users and Firestore data do not automatically transfer to Supabase. Do not delete the old Firebase project until migration is validated.
- Username login depends on an existing username-to-UID record in the new database. Email login is the primary path.
- Supabase Auth email change/password recovery may require redirect URL configuration in the Supabase Dashboard.
- Uploaded product/profile photos are still stored on the Node backend local filesystem, not Supabase Storage. For cloud deployment, migrate uploads to object storage separately.
- Keep the backend private database credentials server-side. Do not relax RLS to allow client writes.
- Do not deploy before checking payment callbacks, refund/cancel flows, concurrency, catalog permissions, and all existing screens.
