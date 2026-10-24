import test from 'node:test';
import assert from 'node:assert/strict';
import {seal,unseal} from '../lib/seal.mjs';
const key='a1'.repeat(32);
test('encrypted tokens only open for their owner before expiry',async()=>{
const token=await seal({uid:'owner',exp:2000,accessToken:'private'},key);
assert.equal((await unseal(token,key,'owner',1000)).accessToken,'private');
assert.equal(await unseal(token,key,'other',1000),null);
assert.equal(await unseal(token,key,'owner',2001),null);
assert.equal(await unseal(token,'a2'.repeat(32),'owner',1000),null);
const bytes=Buffer.from(token,'base64url');bytes[15]^=1;
assert.equal(await unseal(bytes.toString('base64url'),key,'owner',1000),null);
assert.ok(!token.includes('private'));
});
