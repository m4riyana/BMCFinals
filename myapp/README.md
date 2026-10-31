# myapp

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Commerce backend

The storefront uses the existing Flutter, Firebase Authentication, Firestore,
and Express stack. From the `backend` directory, configure Firebase Admin
credentials using Application Default Credentials and set
`FIREBASE_PROJECT_ID`. Set `ADMIN_EMAILS` to a comma-separated list of verified
administrator email addresses, then run `npm start`.

The backend seeds missing starter products and categories from
`catalog/products.json` without replacing existing stock or catalog edits.
Uploaded product images are normalized to WebP and stored under
`backend/uploads/products`; keep that directory on persistent storage. Run
`npm test` in `backend` to exercise commerce validation, checkout, inventory,
and API authorization.
