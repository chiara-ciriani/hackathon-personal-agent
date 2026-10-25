import test from 'node:test';
import assert from 'node:assert/strict';
import {exchangeStatus, connectionGuide} from '../lib/mcp-exchange.mjs';

const capabilities = {protocol:'contribution-window-v1',access_window_seconds:900,mcp_path:'/mcp/shared',shared_endpoint_enabled:true,tools:['connect_phone','request_phone_measurement','phone_measurement_status','send_phone_recommendation','submit_observation','query_sound_map','find_suitable_places']};
test('connection requires configured URL and the exchange protocol', async()=>{
 let called=false;
 const fetcher=async()=>{called=true;return Response.json(capabilities)};
 assert.equal((await exchangeStatus(undefined,fetcher)).state,'not_configured');
 for(const url of ['http://remote.example','https://user:secret@api.example','https://api.example/mcp/private','https://api.example?token=private']) {
  assert.equal((await exchangeStatus(url,fetcher)).state,'invalid_config');
 }
 assert.equal(called,false);
 const status=await exchangeStatus('https://api.example',async(url,options)=>{
  assert.equal(url,'https://api.example/v1/exchange/status');
  assert.equal(options.redirect,'manual');assert.equal(options.cache,'no-store');
  assert.equal(options.headers,undefined);
  return Response.json({...capabilities,private_field:'must not reach browser'});
 });
 assert.deepEqual(status,{state:'available',endpoint:'https://api.example/mcp/shared',dotEndpoint:'https://api.example/mcp/dot',dotReady:false});
});
test('disabled, old and offline servers never appear available',async()=>{
 for(const [data,state] of [[{...capabilities,shared_endpoint_enabled:false},'disabled'], [{...capabilities,access_window_seconds:60},'incompatible'], [{status:'ok'},'incompatible']]) {
  assert.equal((await exchangeStatus('https://api.example',async()=>Response.json(data))).state,state);
 }
 assert.equal((await exchangeStatus('https://api.example',async()=>{throw Error('offline')})).state,'unavailable');
 assert.equal((await exchangeStatus('https://api.example',async()=>new Response(null,{status:404}))).state,'incompatible');
});
test('setup exposes only shared tools and placeholder credential',()=>{
 const guide=connectionGuide('https://api.example/mcp/shared');
 assert.equal(guide.access_window_seconds,900);
 assert.deepEqual(guide.tools.map(t=>t.name),capabilities.tools);
 assert.equal(guide.headers.Authorization,'Bearer <QC_SHARED_API_TOKEN>');
 assert.match(guide.workflow,/Never invent/);
});

test('phone availability requires the deployed phone protocol', async()=>{
 const result=await exchangeStatus('https://api.example',async()=>Response.json({...capabilities,phone_measurement:{protocol:'phone-bridge-v1'}}));
 assert.equal(result.phoneReady,true);
});

test('Dot is ready only when the deployed server advertises OAuth with the extended request lifetime',async()=>{
 const result=await exchangeStatus('https://api.example',async()=>Response.json({...capabilities,dot_mcp_enabled:true,dot_mcp_path:'/mcp/dot',dot_oauth_request_lifetime_seconds:3600}));
 assert.equal(result.dotReady,true);
 assert.equal(result.dotEndpoint,'https://api.example/mcp/dot');
 const old=await exchangeStatus('https://api.example',async()=>Response.json({...capabilities,dot_mcp_enabled:true,dot_mcp_path:'/mcp/dot'}));
 assert.equal(old.dotReady,false);
});
