import test from 'node:test';
import assert from 'node:assert/strict';
import {loadVenueReadings,venueReadings,rankReadings,levelOf,venuePin} from '../lib/venue-data.mjs';

// Mocked /api/map payloads: test fixtures only, never shipped to the page.
const feat=(areaId,dbfs,profile='p1',observedOn='2026-10-24T10:00:00Z',label=areaId)=>({type:'Feature',geometry:{type:'Point',coordinates:[-122.4,37.78]},properties:{evidence:'measured_device',areaId,label,dbfs,count:2,captureProfile:profile,observedOn}});
const reply=(body,ok=true)=>async()=>({ok,status:ok?200:500,json:async()=>body});

test('a failing /api/map yields failed with no features',async()=>{
 assert.deepEqual(await loadVenueReadings(reply({},false)),{state:'failed',features:[]});
 assert.deepEqual(await loadVenueReadings(async()=>{throw new Error('net')}),{state:'failed',features:[]});
});

test('an empty released layer yields ok with no features',async()=>{
 assert.deepEqual(await loadVenueReadings(reply({device:{type:'FeatureCollection',features:[]},deviceState:'empty'})),{state:'ok',features:[]});
 assert.deepEqual(await loadVenueReadings(reply({})),{state:'ok',features:[]});
});

test('only the requested venue and its zones are read',()=>{
 const r=venueReadings('moscone',[feat('venue:moscone',-40),feat('venue:moscone:hall',-45,'p1','2026-10-24T10:00:00Z','Hall'),feat('venue:chase',-30),feat('venue:moscone2',-20),feat('cell:37.770,-122.420',-35)]);
 assert.deepEqual(r.map(x=>x.zone).sort(),['','hall']);
 assert.equal(r.find(x=>x.zone==='hall').name,'Hall');
});

test('no readings means none, never quiet',()=>{
 assert.deepEqual(rankReadings(venueReadings('moscone',[])),{status:'none',profile:null,zones:[]});
});

test('a lone reading is measured but not comparable',()=>{
 const s=rankReadings(venueReadings('moscone',[feat('venue:moscone:hall',-40)]));
 assert.equal(s.status,'single');assert.equal(s.zones[0].relative,undefined);
});

test('relative ranking only inside one capture profile; the quietest is 0 and the loudest is 1',()=>{
 const s=rankReadings(venueReadings('moscone',[feat('venue:moscone:a',-50),feat('venue:moscone:b',-30),feat('venue:moscone:c',-40),feat('venue:moscone:d',-10,'other-phone')]));
 assert.equal(s.profile,'p1');
 const z=Object.fromEntries(s.zones.map(x=>[x.zone,x]));
 assert.equal(z.a.relative,0);assert.equal(z.b.relative,1);assert.equal(z.c.relative,.5);
 assert.equal(z.d.status,'single');assert.equal(z.d.otherProfile,true);assert.equal(z.d.relative,undefined);
});

test('only the latest bucket per area and profile counts',()=>{
 const r=venueReadings('moscone',[feat('venue:moscone:a',-50,'p1','2026-10-24T09:00:00Z'),feat('venue:moscone:a',-45,'p1','2026-10-24T10:00:00Z')]);
 assert.equal(r.length,1);assert.equal(r[0].dbfs,-45);
});

test('malformed features are ignored',()=>{
 assert.deepEqual(venueReadings('moscone',[null,{},{properties:{areaId:'venue:moscone',dbfs:'x',evidence:'measured_device',captureProfile:'p'}},{properties:{areaId:'venue:moscone',dbfs:-30,evidence:'report',captureProfile:'p'}}]),[]);
});

test('level words are relative, not dB',()=>{
 assert.deepEqual([0,.5,1].map(levelOf),['lower','middle','higher']);
});

test('a venue pin stays unmeasured without its own released reading and takes values only from it',()=>{
 const base={id:'moscone',evidence:'unmeasured_candidate'};
 assert.equal(venuePin(base,'moscone',[]),base);
 assert.equal(venuePin(base,'moscone',[feat('venue:moscone:hall',-40)]),base);
 const pin=venuePin(base,'moscone',[feat('venue:moscone',-42)]);
 assert.equal(pin.evidence,'measured_device');assert.equal(pin.dbfs,-42);
});
