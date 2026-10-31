'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {CommerceService} = require('../lib/commerce');
const {ProfileService} = require('../lib/profile');
const {MemoryRepository} = require('../lib/repository');
const {createApp} = require('../server');

test('profile saves are persistent and usernames are unique without case sensitivity', async () => {
  const repository = new MemoryRepository();
  const profiles = new ProfileService(repository);
  const first = await profiles.save('customer-one', 'one@example.com', {
    username: 'PaperMuse', name: 'Paper Muse', contactEmail: 'orders@example.com',
    phoneNumber: '09123456789', address: '12 Stationery Street, Manila',
  });

  assert.equal(first.email, 'one@example.com');
  assert.equal(first.contactEmail, 'orders@example.com');
  await assert.rejects(
    profiles.save('customer-two', 'two@example.com', {
      username: 'papermuse', name: 'Another Customer', contactEmail: 'two@example.com',
      phoneNumber: '', address: '',
    }),
    error => error.status === 409 && /already in use/.test(error.message),
  );

  const renamed = await profiles.save('customer-one', 'one@example.com', {
    username: 'NotebookFan', name: 'Paper Muse', contactEmail: 'orders@example.com',
    phoneNumber: '09123456789', address: '12 Stationery Street, Manila',
  });
  assert.equal(renamed.username, 'NotebookFan');
  assert.equal(await repository.get('usernames/papermuse'), null);
  assert.equal((await repository.get('usernames/notebookfan')).uid, 'customer-one');
  assert.equal((await new ProfileService(repository).get('customer-one', 'one@example.com')).address,
    '12 Stationery Street, Manila');
});

test('authenticated profile update route saves details that are returned on the next login', async t => {
  const repository = new MemoryRepository();
  const profiles = new ProfileService(repository);
  const app = createApp({
    commerce: new CommerceService(repository),
    repository,
    profiles,
    supabaseAuth: {
      verifyIdToken: async token => ({uid: token, email: 'customer@example.com'}),
    },
  });
  const server = app.listen(0);
  t.after(() => new Promise(resolve => server.close(resolve)));
  await new Promise(resolve => server.once('listening', resolve));
  const url = `http://127.0.0.1:${server.address().port}/api/me/profile`;
  const update = await fetch(url, {
    method: 'PUT',
    headers: {
      authorization: 'Bearer customer-uid',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      username: 'PaperMuse',
      name: 'Paper Muse',
      contactEmail: 'orders@example.com',
      phoneNumber: '09123456789',
      address: '12 Stationery Street, Manila',
    }),
  });
  assert.equal(update.status, 200);
  assert.equal((await update.json()).profile.username, 'PaperMuse');

  const nextLogin = await fetch(url, {
    headers: {authorization: 'Bearer customer-uid'},
  });
  assert.equal(nextLogin.status, 200);
  const {profile} = await nextLogin.json();
  assert.equal(profile.address, '12 Stationery Street, Manila');
  assert.equal(profile.phoneNumber, '09123456789');
  assert.equal(profile.contactEmail, 'orders@example.com');
});

test('username login verifies the password with Supabase and rejects mismatched accounts', async t => {
  const repository = new MemoryRepository();
  const profiles = new ProfileService(repository);
  await profiles.save('customer-one', 'one@example.com', {
    username: 'PaperMuse', name: 'Paper Muse', contactEmail: 'one@example.com',
    phoneNumber: '', address: '',
  });
  let identityRequest;
  let identityUid = 'customer-one';
  const app = createApp({
    commerce: new CommerceService(repository),
    repository,
    profiles,
    supabaseAuth: {
      getUser: async uid => ({uid, email: 'one@example.com'}),
      loginWithPassword: async (email, password) => {
        identityRequest = {email, password};
        return {uid: identityUid, accessToken: 'supabase-access-token'};
      },
    },
  });
  const server = app.listen(0);
  t.after(() => {
    server.closeAllConnections();
    server.close();
  });
  await new Promise(resolve => server.once('listening', resolve));
  const url = `http://127.0.0.1:${server.address().port}/api/auth/username-login`;
  const success = await fetch(url, {
    method: 'POST', headers: {'content-type': 'application/json'},
    body: JSON.stringify({username: 'papermuse', password: 'correct-password'}),
  });
  assert.equal(success.status, 200);
  assert.deepEqual(await success.json(), {email: 'one@example.com'});
  assert.deepEqual(identityRequest, {
    email: 'one@example.com', password: 'correct-password',
  });

  identityUid = 'another-user';
  const failure = await fetch(url, {
    method: 'POST', headers: {'content-type': 'application/json'},
    body: JSON.stringify({username: 'PaperMuse', password: 'wrong-password'}),
  });
  assert.equal(failure.status, 401);
  assert.deepEqual(await failure.json(), {
    error: 'Incorrect username or password.', code: 'request_failed',
  });
});

test('profile photo upload persists, rejects invalid replacements, and removes the photo', async t => {
  const fs = require('node:fs/promises');
  const os = require('node:os');
  const path = require('node:path');
  const sharp = require('sharp');
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'ibasho-profile-'));
  const repository = new MemoryRepository();
  const app = createApp({
    commerce: new CommerceService(repository), repository,
    profileUploadsPath: directory,
    supabaseAuth: {verifyIdToken: async () => ({uid: 'photo-user', email: 'photo@example.com'})},
  });
  const server = app.listen(0);
  t.after(async () => {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    await fs.rm(directory, {recursive: true, force: true});
  });
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const headers = {authorization: 'Bearer test'};
  const upload = async bytes => {
    const form = new FormData();
    form.append('image', new Blob([bytes], {type: 'image/png'}), 'avatar.png');
    return fetch(`${base}/api/me/profile/photo`, {method: 'POST', headers, body: form});
  };
  const bytes = await sharp({create: {width: 24, height: 24, channels: 3, background: '#a24447'}}).png().toBuffer();
  const uploaded = await upload(bytes);
  assert.equal(uploaded.status, 201);
  const photo = (await uploaded.json()).profile.profilePhotoPath;
  assert.equal((await fetch(base + photo)).status, 200);
  const invalid = await upload(Buffer.from('invalid image'));
  assert.equal(invalid.status, 400);
  const saved = await fetch(`${base}/api/me/profile`, {headers});
  assert.equal((await saved.json()).profile.profilePhotoPath, photo);
  const removed = await fetch(`${base}/api/me/profile/photo`, {method: 'DELETE', headers});
  assert.equal(removed.status, 200);
  assert.equal((await removed.json()).profile.profilePhotoPath, '');
  assert.equal((await fetch(base + photo)).status, 404);
});
