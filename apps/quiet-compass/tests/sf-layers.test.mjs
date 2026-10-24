import test from 'node:test';
import assert from 'node:assert/strict';
import {CAVEATS,REFERENCE_LEVELS,latestSfoMonitors,loadSfLayers,parseClosure,parseLibrary,parseNightNoise,parsePopos} from '../lib/sf-layers.mjs';

const NOW=new Date('2026-10-24T21:00:00Z');
const pt=(lng,lat)=>({type:'Point',coordinates:[lng,lat]});

test('candidates are unmeasured seeds, never measured',()=>{
 const p=parsePopos({name:'Redwood Park',latitude:'37.795',longitude:'-122.403',type:'Park',hours_type:'Open Business Hours',indoor:false});
 assert.equal(p.properties.evidence,'unmeasured_candidate');assert.equal(p.properties.source,'seed');assert.match(p.properties.caveat,/Nobody has measured/);
 assert.equal(parsePopos({name:'x',latitude:'',longitude:''}),null);
 assert.equal(parseLibrary({common_name:'Library Support Services',latitude:'37.77',longitude:'-122.41'}),null);
 assert.equal(parseLibrary({common_name:'Main Library',latitude:'37.779',longitude:'-122.416'}).properties.kind,'Library');
});
test('night permits keep only plausible, non-denied, current ones',()=>{
 const base={start_date:'2026-10-24T00:00:00.000',end_date:'2026-10-25T00:00:00.000',address:'a',point:pt(-122.42,37.75)};
 assert.ok(parseNightNoise({...base,nnp:'111328'},NOW));
 assert.equal(parseNightNoise({...base,nnp:'DENIED'},NOW),null);
 assert.equal(parseNightNoise({...base,nnp:'1',end_date:'2219-11-22T00:00:00.000'},NOW),null);
 assert.equal(parseNightNoise({...base,nnp:'1',start_date:'2026-10-20T00:00:00.000',end_date:'2026-10-22T00:00:00.000'},NOW),null);
});
test('closures use the middle vertex; only SFO monitors are measured',()=>{
 const c=parseClosure({loc_desc:'OAK ST',shape:{coordinates:[[-122.454,37.7714],[-122.4533,37.7713]]}});
 assert.deepEqual(c.geometry.coordinates,[-122.4533,37.7713]);assert.equal(c.properties.evidence,'proxy');
 const m=latestSfoMonitors([
  {date:'2026-08-30T00:00:00.000',location_id:'21',latitude:'37.74',longitude:'-122.433',total_cnel:'60.1'},
  {date:'2026-08-31T00:00:00.000',location_id:'21',latitude:'37.74',longitude:'-122.433',total_cnel:'61.1',aircraft_cnel:'45.2'},
  {date:'2026-08-31T00:00:00.000',location_id:'23',latitude:'37.711',longitude:'-122.399',total_cnel:''}]);
 assert.equal(m.length,1);assert.equal(m[0].properties.cnel,61.1);assert.equal(m[0].properties.evidence,'measured');assert.equal(m[0].properties.observedOn,'2026-08-31');
});
test('reference table is cited and labelled',()=>{
 assert.ok(REFERENCE_LEVELS.length>=8);
 for(const r of REFERENCE_LEVELS){assert.equal(r.evidence,'reference_measured');assert.match(r.sourceUrl,/^https:\/\//)}
 assert.ok(Object.keys(CAVEATS).length===5);
});
test('loadSfLayers isolates a failing dataset and mocks the network',async()=>{
 const calls=[];
 const fetchFn=async url=>{calls.push(url);
  if(url.includes('qxw2-ncq3'))return {ok:false,status:503,json:async()=>[]};
  if(url.includes('65ik-7wqd'))return {ok:true,json:async()=>[{name:'Redwood Park',latitude:'37.795',longitude:'-122.403'}]};
  if(url.includes('fhhu-wqa7'))return {ok:true,json:async()=>[{common_name:'Main Library',latitude:'37.779',longitude:'-122.416'}]};
  if(url.includes('86e8-rfem'))return {ok:true,json:async()=>[{dba_name:'Gallery',point:pt(-122.399,37.787)}]};
  return {ok:false,status:500,json:async()=>[]};};
 const r=await loadSfLayers(fetchFn,NOW);
 assert.equal(r.candidates.features.length,2);assert.equal(r.proxies.features.length,1);
 assert.deepEqual(r.failed,['measured']);assert.equal(r.measured.features.length,0);
 assert.ok(calls.every(u=>u.startsWith('https://data.sf.gov/resource/')));
});
