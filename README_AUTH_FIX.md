# IBASHO / BMCFinals: signup and email confirmation fix

## What's changed
- Store the requested username in Supabase signup user metadata, even when email confirmation means there is no session yet.
- On successful email/password login, try to finish creating the profile using that metadata, without overwriting an existing username. If the profile backend isn't available, login remains possible.
- Show a dedicated **Resend confirmation email** action on the login form. Do not repeatedly press **Create account** for an existing unconfirmed account. Supabase applies server-side rate limits; this UI cannot remove them.
- Retry countdown resets when switching between login and signup, so a signup email rate limit doesn't lock the login button.

## Required Supabase dashboard configuration (cannot be changed by code)
1. Authentication > Users: check whether the account exists and whether email is confirmed.
2. Authentication > URL Configuration: add `http://localhost:50371/**` to Redirect URLs for local web tests, and set the Site URL appropriately. Restrict allowed redirects to your actual origins in production.
3. Start Flutter with **the same fixed port** each time:
   `cd myapp && flutter pub get && flutter run -d edge --web-port 50371`
4. Keep email confirmation on. Click the **latest** email's verification link. Old links may have expired.
5. After verification, sign in using registered **email** first. Username login requires a profile and a reachable backend on port 3000.
6. For old unconfirmed accounts created *before* this fix, signup metadata may not contain a username. After confirming and signing in by email, edit your profile to set a username. Do not re-register to repair it.
7. Supabase rate limits are enforced by the provider. Wait until the server-side limit ends; the UI countdown does not guarantee the provider will accept a request at the exact second.

## Backend
Run `cd backend && npm install && npm start` (requires a locally configured `backend/.env`). The ZIP deliberately excludes real `.env` files, credentials, cache, node_modules, generated build outputs. Copy `.env.example` to `.env` and provide your OWN existing credentials locally; never post them in chat or commit them.

## Limitations
Unable to verify live Supabase email delivery, hosted redirect allowlisting, or end-to-end login here without access to your Supabase project and a Flutter SDK. Xendit code was not edited.
