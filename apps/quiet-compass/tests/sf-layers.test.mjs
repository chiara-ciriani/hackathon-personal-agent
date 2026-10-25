import test from 'node:test';
import assert from 'node:assert/strict';
import {cadNoiseAreas,latestSfoMonitors,loadSfLayers,parseClosure,parseLibrary,parseNightNoise,parsePark,parsePopos,parseStreetWork,sfoEventMonitors} from '../lib/sf-layers.mjs';

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
test('street work keeps noisy permit types valid today',()=>{
 const base={permit_start_date:'2026-05-01T00:00:00.000',permit_end_date:'2026-10-28T00:00:00.000',location:pt(-122.41188,37.77644)};
 const w=parseStreetWork({...base,permit_type:'Excavation',streetname:'08TH ST',cross_street_1:'NATOMA ST',cross_street_2:'HOWARD ST'},NOW);
 assert.deepEqual([w.properties.label,w.properties.detail,w.properties.evidence,w.properties.dataset],['08TH ST between NATOMA ST and HOWARD ST','Excavation · until 2026-10-28','proxy','x8nh-xzn6']);
 assert.match(w.properties.caveat,/may not be happening right now/);
 assert.equal(parseStreetWork({...base,permit_type:'Boring',streetname:'CLAY ST',cross_street_1:'LARKIN ST'},NOW).properties.label,'CLAY ST at LARKIN ST');
 assert.equal(parseStreetWork({...base,permit_type:'Wireless',streetname:'x'},NOW),null);
 assert.equal(parseStreetWork({...base,permit_type:'Excavation',permit_end_date:'2026-10-23T00:00:00.000'},NOW),null);
 assert.equal(parseStreetWork({...base,permit_type:'Excavation',location:null},NOW),null);
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
test('parks are unmeasured seeds with a loudness warning; wrong types and missing coords are dropped',()=>{
 const p=parsePark({property_name:'Dolores Park',latitude:'37.75965',longitude:'-122.42691',propertytype:'Neighborhood Park or Playground',acres:'15.9'});
 assert.equal(p.properties.evidence,'unmeasured_candidate');assert.equal(p.properties.source,'seed');assert.match(p.properties.detail,/15\.9 acres/);assert.match(p.properties.caveat,/loud/);
 assert.equal(parsePark({property_name:'Main Library',latitude:'37.779',longitude:'-122.416',propertytype:'Library'}),null);
 assert.equal(parsePark({property_name:'x',latitude:'',longitude:'',propertytype:'Mini Park'}),null);
});
test('SFO exceedance events: text max_level, per-monitor summary with date, unplaceable monitors skipped',()=>{
 const monitors=[{location_id:'21',latitude:'37.740',longitude:'-122.433'},{location_id:'99'}];
 const events=[{location_id:'21',max_date_time:'2026-10-19T23:30:03.000',max_level:'83.9'},{location_id:'21',max_date_time:'2026-01-02T01:00:00.000',max_level:'81.1'},
  {location_id:'21',max_date_time:'2025-12-01T01:00:00.000',max_level:'100.2'},{location_id:'21',max_date_time:'2025-11-01T01:00:00.000',max_level:'n/a'},{location_id:'99',max_date_time:'2026-08-02T01:03:50.000',max_level:'90.0'}];
 const out=sfoEventMonitors(monitors,events);
 assert.equal(out.length,1);const p=out[0].properties;
 assert.deepEqual([p.count,p.medianDb,p.maxDb,p.observedOn,p.evidence],[3,83.9,100.2,'2026-10-19','measured']);
 assert.match(p.caveat,/declares no license/);assert.equal(p.cnel,undefined);
 assert.deepEqual(sfoEventMonitors([],events),[]);
});
test('CAD noise calls: counts per masked intersection, sensitive and duplicate rows dropped, proxy only',()=>{
 const base={intersection_name:'MISSION ST \\ 16TH ST',intersection_point:pt(-122.41964,37.76481),sensitive_call:false};
 const out=cadNoiseAreas([{...base,cad_number:'A1',received_datetime:'2026-10-20T10:00:00.000'},{...base,cad_number:'A2',received_datetime:'2026-10-23T22:00:00.000'},{...base,cad_number:'A2',received_datetime:'2026-10-23T22:00:00.000'},
  {...base,cad_number:'A3',sensitive_call:true},{cad_number:'A4',intersection_name:'NO POINT'}]);
 assert.equal(out.length,1);const p=out[0].properties;
 assert.deepEqual([p.count,p.evidence,p.observedOn,p.label],[2,'proxy','2026-10-23','MISSION ST / 16TH ST']);assert.match(p.caveat,/not measurements/);
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
 assert.deepEqual(r.failed,['measured','sfoEvents','cad','parks','nightNoise','closures','streetWork']);assert.equal(r.measured.features.length,0);
 assert.ok(calls.filter(u=>!u.startsWith('/data/')).every(u=>u.startsWith('https://data.sf.gov/resource/')));
});
test('loadSfLayers loads the new layers, joins monitor coordinates, and queries the verified datasets',async()=>{
 const calls=[];
 const json=body=>({ok:true,json:async()=>body});
 const fetchFn=async url=>{calls.push(url);
  if(url.includes('gtr9-ntp6'))return json([{property_name:'Dolores Park',latitude:'37.75965',longitude:'-122.42691',propertytype:'Mini Park',acres:'2'}]);
  if(url.includes('tiju-qyvs'))return json([{location_id:'21',max_date_time:'2026-10-19T23:30:03.000',max_level:'83.9'}]);
  if(url.includes('qxw2-ncq3'))return json([{location_id:'21',latitude:'37.740',longitude:'-122.433',date:'2026-10-23T00:00:00.000',total_cnel:'61.1'}]);
  if(url.includes('x8nh-xzn6'))return json([{permit_type:'Excavation',streetname:'08TH ST',cross_street_1:'NATOMA ST',permit_start_date:'2026-10-01T00:00:00.000',permit_end_date:'2026-10-28T00:00:00.000',location:pt(-122.41188,37.77644)}]);
  if(url.includes('2zdj-bwza'))return json([{cad_number:'A1',received_datetime:'2026-10-23T22:00:00.000',intersection_name:'A \\ B',intersection_point:pt(-122.41964,37.76481),sensitive_call:false}]);
  return json([]);};
 const r=await loadSfLayers(fetchFn,NOW);
 assert.deepEqual(r.failed,[]);
 assert.equal(r.candidates.features.length,1);assert.equal(r.sfoEvents.features[0].properties.count,1);assert.equal(r.cad.features[0].properties.count,1);
 assert.equal(r.proxies.features.filter(f=>f.properties.dataset==='x8nh-xzn6').length,1);
 assert.match(decodeURIComponent(calls.find(u=>u.includes('x8nh-xzn6'))),/permit_start_date <= '2026-10-24T23:59:59'/);
 const ev=decodeURIComponent(calls.find(u=>u.includes('tiju-qyvs')));
 assert.match(ev,/location_id in\('21'\)/);assert.match(ev,/max_date_time >= '2026-09-24T00:00:00'/);
 assert.match(decodeURIComponent(calls.find(u=>u.includes('2zdj-bwza'))),/call_type_final_desc='NOISE NUISANCE'/);
});

test('fast layers render before a slow dataset finishes',async()=>{
 let release;
 const slow=new Promise(resolve=>{release=resolve});
 const updates=[];
 const pending=loadSfLayers(async url=>{
  if(url.includes('x8nh-xzn6'))await slow;
  return {ok:true,json:async()=>[]};
 },NOW,(key,data)=>updates.push([key,data]));
 await new Promise(resolve=>setTimeout(resolve,20));
 try{assert.ok(updates.some(([key])=>key==='cad'),'CAD must render while street work is pending')}finally{release();await pending}
});

test('old airport readings and events are excluded, and monitors are fetched once',async()=>{
 const calls=[];
 const r=await loadSfLayers(async url=>{
  calls.push(url);
  const body=url.includes('qxw2-ncq3')?[
   {location_id:'21',latitude:'37.74',longitude:'-122.43',date:'2026-10-20',total_cnel:'61'},
   {location_id:'23',latitude:'37.75',longitude:'-122.42',date:'2026-08-20',total_cnel:'70'},
  ]:url.includes('tiju-qyvs')?[
   {location_id:'21',max_date_time:'2026-10-20T10:00:00',max_level:'80'},
   {location_id:'21',max_date_time:'2026-03-20T10:00:00',max_level:'100'},
  ]:[];
  return {ok:true,json:async()=>body};
 },NOW);
 assert.equal(r.measured.features.length,1);
 assert.equal(r.sfoEvents.features[0].properties.count,1);
 assert.equal(r.sfoEvents.features[0].properties.maxDb,80);
 assert.equal(calls.filter(url=>url.includes('qxw2-ncq3')).length,1);
});
