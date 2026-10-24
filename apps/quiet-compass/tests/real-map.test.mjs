import test from 'node:test';
import assert from 'node:assert/strict';
import {deviceReadings,loadDeviceReadings,noiseReports,loadNoiseReports,measurementText} from '../lib/real-map.mjs';
const now=new Date('2026-10-24T23:00:00Z');
const row={area_id:'sf:1',area_name:'Recorded place',lat:37.77,lon:-122.43,time_bucket:'2026-10-24T22:55:00Z',capture_profile:'phone-A',n:2,measurement_kind:'relative_uncalibrated',median_rms_dbfs:-35,source:'device',has_synthetic:false};
test('device observations retain their actual value, date and profile',()=>{
 const f=deviceReadings({aggregates:[row]},now).features[0];
 assert.equal(f.properties.dbfs,-35);assert.equal(f.properties.observedOn,row.time_bucket);assert.equal(f.properties.captureProfile,'phone-A');assert.equal(f.properties.score,undefined);
 assert.equal(measurementText(f.properties),'-35 dBFS · uncalibrated');
});
test('synthetic, mixed, missing provenance, invalid and stale observations cannot color the map',()=>{
 for(const patch of [{source:'simulated'},{source:'mixed'},{has_synthetic:true},{has_synthetic:undefined},{median_rms_dbfs:null},{median_rms_dbfs:'-35'},{median_rms_dbfs:5},{n:0},{lat:null},{lon:0},{time_bucket:'2026-10-22T22:55:00Z'},{time_bucket:'2026-10-25T23:00:00Z'},{time_bucket:''}]){
  assert.equal(deviceReadings({aggregates:[{...row,...patch}]},now).features.length,0,JSON.stringify(patch));
 }
});
test('same-place observations never merge device profiles',()=>{
 const data=deviceReadings({aggregates:[row,{...row,capture_profile:'phone-B',median_rms_dbfs:-10}]},now);
 assert.deepEqual(data.features.map(f=>f.properties.dbfs),[-35,-10]);
});
test('missing data has no measurement and zero remains a real value',()=>{
 assert.equal(measurementText({evidence:'measured',cnel:null}),'No sound measurement');
 assert.equal(measurementText({evidence:'proxy',cnel:70}),'No sound measurement');
 assert.match(measurementText({evidence:'measured_device',dbfs:0}),/^0 dBFS/);
});
test('access failures and unavailable servers return empty gray coverage',async()=>{
 for(const status of [401,403,428,500]){
  const r=await loadDeviceReadings(undefined,async()=>({status,ok:false}),now);
  assert.equal(r.state,status===500?'unavailable':'access_required');assert.equal(r.data.features.length,0);
 }
 assert.equal((await loadDeviceReadings(undefined,async()=>{throw Error()},now)).state,'unavailable');
});
test('empty or malformed server payload never becomes fake contributions',async()=>{
 assert.equal((await loadDeviceReadings(undefined,async()=>({ok:true,json:async()=>({aggregates:[]})}),now)).state,'empty');
 assert.equal((await loadDeviceReadings(undefined,async()=>({ok:true,json:async()=>({bad:true})}),now)).state,'unavailable');
});
test('public device request does not attach owner credentials',async()=>{
 const result=await loadDeviceReadings(undefined,async(url,options)=>{
  assert.match(url,/radius_m=5000/);assert.equal(options.headers,undefined);assert.equal(options.redirect,'error');
  return {ok:true,json:async()=>({aggregates:[row]})};
 },now);
 assert.equal(result.state,'available');
});
test('invalid upstream URL is rejected before any request',async()=>{
 for(const url of ['http://example.com','https://name:secret@example.com','https://example.com/path'])assert.equal((await loadDeviceReadings(url,()=>{throw Error('must not run')})).state,'invalid_config');
});
test('real complaints remain gray context, with the source time unchanged',()=>{
 const rows=[{lat:'37.77',long:'-122.43',requested_datetime:'2026-10-24T14:00:00',service_subtype:'Loud_Music'},{lat:'',long:'',requested_datetime:'x'}];
 const data=noiseReports(rows);assert.equal(data.features.length,1);
 const p=data.features[0].properties;assert.equal(p.evidence,'report');assert.equal(p.observedOn,rows[0].requested_datetime);assert.equal(p.score,undefined);assert.equal(measurementText(p),'No sound measurement');
});
test('311 errors remain errors, not empty successful readings',async()=>{
 await assert.rejects(loadNoiseReports(async()=>({ok:false,status:503})));
 await assert.rejects(loadNoiseReports(async()=>({ok:true,json:async()=>({error:'bad'})})));
});
