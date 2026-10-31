
import {HttpError} from './commerce.js';

const fail = message => { throw new HttpError(400, message); };
function requiredText(value, label, min, max) {
  if (typeof value !== 'string' || value.trim().length < min || value.trim().length > max || /[\u0000-\u001f]/.test(value)) {
    fail(`Enter a valid ${label}.`);
  }
  return value.trim();
}
function optionalText(value, label, max) {
  if (value === undefined || value === null) return '';
  if (typeof value !== 'string' || value.trim().length > max || /[\u0000-\u001f]/.test(value)) fail(`Enter a valid ${label}.`);
  return value.trim();
}
function username(value) {
  const result = requiredText(value, 'username', 3, 24);
  if (!/^[a-zA-Z][a-zA-Z0-9._-]*$/.test(result)) fail('Use 3–24 letters, numbers, periods, underscores, or hyphens for your username.');
  return result;
}
function email(value, label = 'email address') {
  const result = requiredText(value, label, 5, 254);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(result)) fail(`Enter a valid ${label}.`);
  return result;
}

class ProfileService {
  constructor(repository, {now = () => new Date().toISOString()} = {}) {
    this.repo = repository;
    this.now = now;
  }

  async get(uid, accountEmail = '') {
    const saved = await this.repo.get(`profiles/${uid}`) || {};
    return {
      username: saved.username || '',
      name: saved.name || '',
      email: accountEmail,
      contactEmail: saved.contactEmail || accountEmail,
      phoneNumber: saved.phoneNumber || '',
      address: saved.address || '',
      profilePhotoPath: saved.profilePhotoPath || '',
    };
  }

  async uidForUsername(value) {
    let key;
    try { key = username(value).toLowerCase(); }
    catch (_) { return null; }
    const reservation = await this.repo.get(`usernames/${key}`);
    return reservation?.uid || null;
  }

  async save(uid, accountEmail, body) {
    if (!body || typeof body !== 'object' || Array.isArray(body)) fail('Enter valid profile details.');
    const nextUsername = username(body.username);
    const key = nextUsername.toLowerCase();
    const name = optionalText(body.name, 'name', 100);
    const contactEmail = email(body.contactEmail || accountEmail || '');
    const phoneNumber = optionalText(body.phoneNumber, 'phone number', 20);
    if (phoneNumber && !/^(09\d{9}|\+639\d{9})$/.test(phoneNumber)) fail('Use a valid Philippine mobile number.');
    const address = optionalText(body.address, 'address', 600);

    return this.repo.transaction(async tx => {
      const [old, reserved] = await Promise.all([
        tx.get(`profiles/${uid}`),
        tx.get(`usernames/${key}`),
      ]);
      if (reserved && reserved.uid !== uid) {
        throw new HttpError(409, 'That username is already in use.', 'username_taken');
      }
      const oldKey = old?.usernameKey || old?.username?.toLowerCase();
      if (oldKey && oldKey !== key) {
        const oldReservation = await tx.get(`usernames/${oldKey}`);
        if (oldReservation?.uid === uid) tx.delete(`usernames/${oldKey}`);
      }
      const now = this.now();
      const profile = {
        uid, username: nextUsername, usernameKey: key, name, contactEmail,
        phoneNumber, address, profilePhotoPath: old?.profilePhotoPath || '',
        createdAt: old?.createdAt || now, updatedAt: now,
      };
      tx.set(`usernames/${key}`, {uid, username: nextUsername, updatedAt: now});
      tx.set(`profiles/${uid}`, profile);
      return {...profile, email: accountEmail};
    });
  }

  async setPhoto(uid, profilePhotoPath) {
    return this.repo.transaction(async tx => {
      const old = await tx.get(`profiles/${uid}`) || {uid, createdAt: this.now()};
      const next = {...old, profilePhotoPath, updatedAt: this.now()};
      tx.set(`profiles/${uid}`, next);
      return next;
    });
  }
}

export {ProfileService, username, email};
