import test from 'node:test';
import assert from 'node:assert/strict';
import {AcousticAccumulator} from '../public/measure/acoustics.mjs';
import {coarseLocation, makeContribution, measurementProblem, captureProfile} from '../lib/phone-measurement.mjs';
import {relayPhone} from '../lib/phone-relay.mjs';

function signal(rate, amplitude = .1) {
  const meter = new AcousticAccumulator(rate);
  // Synthetic mathematical fixture; never sent to a live server.
  for (let start = 0; start < rate * 10; start += 128) {
    meter.append(Float32Array.from({length: Math.min(128, rate * 10 - start)},
      (_, i) => amplitude * Math.sin(2 * Math.PI * 1000 * (start + i) / rate)));
  }
  return meter.result();
}
test('energy RMS of a 0.1 sine is -23.0103 dBFS at both device sample rates', () => {
  for (const rate of [44100, 48000]) {
    const r = signal(rate);
    assert.ok(Math.abs(r.rms_dbfs - (-23.0103)) < .001);
    assert.equal(r.duration_seconds, 10);
    assert.ok(r.frame_level_spread_db < .02);
    assert.equal(r.peaks_per_min, 0);
    assert.equal(measurementProblem(r), null);
  }
});
test('a one-second loud event counts one onset, normalized to six per minute', () => {
  const meter = new AcousticAccumulator(8000);
  for (let second = 0; second < 10; second++) meter.append(new Float32Array(8000).fill(second === 5 ? .2 : .01));
  const result = meter.result();
  assert.equal(result.peaks_per_min, 6);
  const expected = 10 * Math.log10((9 * .0001 + .04) / 10);
  assert.ok(Math.abs(result.rms_dbfs - expected) < .001);
});
test('missing input, incomplete capture, invalid samples and clipping cannot be shared', () => {
  const meter = new AcousticAccumulator(8000);
  assert.throws(() => meter.result(), /incomplete/);
  assert.throws(() => meter.append([NaN]), /Invalid/);
  meter.append(new Float32Array(80000));
  assert.match(measurementProblem(meter.result()), /No microphone signal/);
  const clipped = new AcousticAccumulator(8000);
  clipped.append(new Float32Array(80000).fill(1));
  assert.match(measurementProblem(clipped.result()), /clipping/);
  assert.match(measurementProblem({...signal(8000), frame_level_spread_db: 90}), /Variation/);
});
test('only coarse position and bucket enter the existing contribution contract', () => {
  const endedAt = Date.parse('2026-10-24T21:04:35Z');
  const location = coarseLocation({coords:{latitude:37.777456,longitude:-122.419787,accuracy:20},timestamp:endedAt-30000}, endedAt);
  const contribution = makeContribution({result:signal(8000),location,profile:'web-v1:session:8000:a0e0n0',id:'11111111-1111-4111-8111-111111111111',endedAt});
  assert.equal(contribution.lat,37.777);
  assert.equal(contribution.lon,-122.42);
  assert.equal(contribution.time_bucket,'2026-10-24T21:00:00.000Z');
  assert.equal(contribution.source,'device');
  assert.equal(contribution.quality.clipping_detected,false);
  assert.equal(contribution.measurement.calibrated,false);
  assert.equal(contribution.area_id,'cell:37.777,-122.420');
  assert.ok(!JSON.stringify(contribution).includes('37.777456'));
  assert.throws(()=>coarseLocation({coords:{latitude:37,longitude:-122,accuracy:500},timestamp:endedAt},endedAt),/accurate/);
  assert.throws(()=>makeContribution({result:signal(8000),location,profile:'web-v1:test',id:contribution.id,endedAt:endedAt+60000}),/Location/);
});
test('capture profiles isolate sessions and record actual processing without device IDs', () => {
  const profile = captureProfile('session1',{deviceId:'private-id',autoGainControl:false,echoCancellation:true},48000);
  assert.match(profile,/a0e1nu$/);
  assert.ok(!profile.includes('private-id'));
  assert.notEqual(profile,captureProfile('session2',{},48000));
});
const token = 'a'.repeat(43);
const req = (body={},headers={}) => new Request('https://map.example/api/phone/poll',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json',...headers},body:JSON.stringify(body)});
test('phone relay forwards only to the configured phone route and returns no agent secrets', async () => {
  const response=await relayPhone(req(),'https://server.example','poll',async(url,options)=>{
    assert.equal(url,'https://server.example/v1/phone/poll');
    assert.equal(options.headers.Authorization,'Bearer '+token);
    assert.equal(options.redirect,'manual');
    return Response.json({status:'measure',request_id:'job',duration_seconds:10,expires_at:'later',agent_token:'never forward'});
  });
  assert.equal(response.status,200);
  assert.equal(response.headers.get('cache-control'),'no-store');
  assert.equal((await response.json()).agent_token,undefined);
});
test('relay refuses untrusted destinations, oversized bodies, cross-origin calls and arbitrary actions', async () => {
  const never=()=>{throw new Error('must not forward')};
  assert.equal((await relayPhone(req(),'http://server.example','poll',never)).status,503);
  assert.equal((await relayPhone(req(),'https://server.example','../../mcp',never)).status,404);
  assert.equal((await relayPhone(req({}, {Origin:'https://evil.example'}),'https://server.example','poll',never)).status,403);
  assert.equal((await relayPhone(req({text:'x'.repeat(9000)}),'https://server.example','result',never)).status,413);
  assert.equal((await relayPhone(req({}, {Authorization:'Bearer wrong'}),'https://server.example','poll',never)).status,401);
});
test('old server and expired phone links are reported honestly', async () => {
  for (const code of [404,410]) {
    const response=await relayPhone(req(),'https://server.example','status',async()=>new Response('',{status:code}));
    assert.equal(response.status,code===404?503:410);
  }
});

test('completed sharing puts map access only in an HttpOnly cookie',async()=>{
 const receipt='r'.repeat(43);
 const response=await relayPhone(req(),'https://server.example','result',async()=>Response.json({status:'complete',map_access:receipt}));
 assert.match(response.headers.get('set-cookie'),/qc_map_access=r+; HttpOnly; Secure; SameSite=Strict; Path=\/api\/map; Max-Age=900/);
 assert.equal((await response.json()).map_access,undefined);
 const failed=await relayPhone(req(),'https://server.example','result',async()=>Response.json({status:'failed',map_access:receipt}));
 assert.equal(failed.headers.get('set-cookie'),null);
});
