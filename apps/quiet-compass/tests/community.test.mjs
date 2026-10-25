import test from 'node:test';
import assert from 'node:assert/strict';
import {shareCommunity,activateMapAccess} from '../lib/community.mjs';
const receipt='r'.repeat(43);
const request=body=>new Request('https://map.example/api/community',{method:'POST',headers:{'Content-Type':'application/json',Origin:'https://map.example'},body:JSON.stringify(body)});
test('native sharing forwards only the summary to the fixed backend without account credentials',async()=>{
 const response=await shareCommunity(request({share_consent:true}),'https://server.example',async(url,options)=>{
  assert.equal(url,'https://server.example/v1/community/contributions');
  assert.equal(options.headers.Authorization,undefined);
  assert.equal(options.redirect,'error');
  return Response.json({status:'withheld',reason:'Needs another sample',access_receipt:receipt});
 });
 assert.equal((await response.json()).access_receipt,receipt);
});
test('community submission bounds input and rejects cross-origin requests',async()=>{
 const never=()=>{throw Error('must not call')};
 assert.equal((await shareCommunity(request({text:'a'.repeat(8193)}),'https://server.example',never)).status,413);
 const foreign=new Request('https://map.example/api/community',{method:'POST',headers:{Origin:'https://other.example'},body:'{}'});
 assert.equal((await shareCommunity(foreign,'https://server.example',never)).status,403);
 assert.equal((await shareCommunity(request({}),'https://name:secret@server.example',never)).status,503);
});
test('native map handoff validates access and sets only an HttpOnly map cookie',async()=>{
 const response=await activateMapAccess(request({receipt}),'https://server.example',async(url,options)=>{
  assert.equal(url,'https://server.example/v1/map/view');
  assert.equal(options.headers.Authorization,'Bearer '+receipt);
  return Response.json({aggregates:[]});
 });
 assert.equal(response.status,200);
 assert.match(response.headers.get('set-cookie'),/HttpOnly; Secure; SameSite=Strict; Path=\/api\/map/);
 assert.deepEqual(await response.json(),{ok:true});
 const expired=await activateMapAccess(request({receipt}),'https://server.example',async()=>new Response('',{status:428}));
 assert.equal(expired.status,403);
 assert.equal(expired.headers.get('set-cookie'),null);
});
