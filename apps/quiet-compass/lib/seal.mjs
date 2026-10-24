export async function seal(value, secret) {
  const key = await crypto.subtle.importKey('raw', Buffer.from(secret, 'hex'), 'AES-GCM', false, ['encrypt']);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, new TextEncoder().encode(JSON.stringify(value)));
  return Buffer.concat([Buffer.from(iv), Buffer.from(ciphertext)]).toString('base64url');
}
export async function unseal(value, secret, uid, now = Date.now()) {
  try {
    const data = Buffer.from(value, 'base64url');
    const key = await crypto.subtle.importKey('raw', Buffer.from(secret, 'hex'), 'AES-GCM', false, ['decrypt']);
    const clear = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: data.subarray(0, 12) }, key, data.subarray(12));
    const result = JSON.parse(new TextDecoder().decode(clear));
    return result.uid === uid && result.exp > now ? result : null;
  } catch { return null; }
}
