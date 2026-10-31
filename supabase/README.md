# Flutter + Supabase + Xendit

The production backend is the `commerce` Supabase Edge Function. Node.js remains the source of the tested business rules; no PC server or Render service is needed after deployment.

## Deploy from the repository root

```powershell
npx.cmd supabase login
node supabase/generate-edge.cjs
node supabase/deploy-commerce.cjs
```

The script reads backend/.env privately, uploads server secrets, configures the public `ibasho-images` Storage bucket, copies existing local uploads, deploys the function and checks the live catalog. Temporary secrets files are deleted even on failure. Never paste tokens into chat or commit .env. Backend npm dependencies must be installed.

The existing Supabase document table/data are reused. PostgreSQL transactions and the advisory lock continue protecting stock, unique usernames and payment idempotency. The function uses a single-connection pool with certificate verification. COMMERCE_DB_URL comes from backend's SUPABASE_DB_URL; use the project's Supavisor connection string if the current host is unreachable from Edge Functions.

Configured target (not proof of deployment):
https://yvzulpfohcxkfkbfwvmk.supabase.co/functions/v1/commerce

JWT gateway verification is disabled for the public catalog and Xendit callbacks. Private routes independently verify bearer tokens through Supabase Auth; admin routes check administrator authorization. Service-role/database/payment keys stay server-side.

## Xendit Test Mode

Set the Payment Session webhook in the Xendit Test Mode dashboard to:
https://yvzulpfohcxkfkbfwvmk.supabase.co/functions/v1/commerce/api/xendit/webhook

Match its callback token to XENDIT_CALLBACK_TOKEN in backend/.env before deployment. The function checks the token and verifies session/payment details with Xendit before marking an order paid. Only Test Mode keys are accepted. A real end-to-end Test Mode payment needs verification after deployment.

## Images

Product/profile uploads use Supabase Storage instead of a server filesystem. JPEG, PNG and WebP uploads are limited to 5 MB and 24 megapixels. Original bytes are kept; the old Sharp resizing is not used. Existing /uploads/... URLs redirect to the corresponding Storage objects, preserving records. Only authenticated backend routes write objects; no public write policy is created.

## Build

Flutter defaults to the function URL, even with a plain release build. Internet permission is enabled; the local HTTP exception is removed.

```powershell
cd myapp
.\build-remote-apk.ps1 -BackendUrl 'https://yvzulpfohcxkfkbfwvmk.supabase.co/functions/v1/commerce' -FlutterPath 'C:\Flutter\flutter\bin\flutter.bat'
```

This helper checks the live catalog before building. Test signup, login, profiles, uploads, checkout and Xendit Test Mode on mobile data before sharing.

## Maintain and test

Edit backend routes/business rules, then regenerate the Edge copies. Storage adaptations live in generate-edge.cjs and functions/commerce/storage.js.

```powershell
node supabase/generate-edge.cjs
npx.cmd deno check --config supabase/functions/commerce/deno.json supabase/functions/commerce/index.ts
npx.cmd deno test -A --config supabase/functions/commerce/deno.json supabase/functions/commerce/test
```
