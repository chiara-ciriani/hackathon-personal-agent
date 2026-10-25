import test from 'node:test';
import assert from 'node:assert/strict';
import {FIELD_PATH,ago,describe,fieldBounds,fieldLayers,hasData,isField,liveLabel,loadField,relLevel,serverBase} from '../lib/sound-field.mjs';

const ll=(x,y)=>[x,y];
const field={session_id:'s',generated_at:'2026-10-24T21:00:00Z',cell_m:.5,origin:{x:-1,z:-1},cols:4,rows:2,level_range_db:[-52,-32],
 cells:[{x:-.75,z:-.75,level_db:-52,confidence:.9},{x:-.25,z:-.75,level_db:-32,confidence:.4},{x:.25,z:-.75,level_db:null,confidence:0},{x:.75,z:-.75,level_db:-42,confidence:.6}],
 samples:[{x:-.7,z:-.7,level_db:-52,age_min:3.5},{x:-.2,z:-.7,level_db:-32,age_min:.2}],
 path:[{x:0,z:0},{x:1,z:2}],places:[{id:'p',label:'Hallway',x:-.5,z:-.5}],user:{x:.5,z:.2},
 quiet_spots:[{x:-.75,z:-.75,level_db:-52,confidence:.9,age_min:4,distance_m:6.2}],message:null};

test('server base comes from ?server= first, then the env, and only http(s)',()=>{
 assert.equal(serverBase('https://api.example.com/',''),'https://api.example.com');
 assert.equal(serverBase('https://api.example.com','?server=http://localhost:8000'),'http://localhost:8000');
 assert.equal(serverBase('https://api.example.com','?server=javascript:alert(1)'),'https://api.example.com');
 assert.equal(serverBase(undefined,''),null);assert.equal(serverBase('not a url',''),null);
});
test('unknown cells are never quiet; levels are relative to the measured range',()=>{
 assert.equal(relLevel(null,[-52,-32]),-1);assert.equal(relLevel(-52,[-52,-32]),0);assert.equal(relLevel(-32,[-52,-32]),1);
 assert.equal(relLevel(-40,[-40,-40]),.5);assert.equal(relLevel(-60,[-52,-32]),0);
 const cells=fieldLayers(field,ll).cells.features.map(f=>f.properties);
 assert.deepEqual(cells.map(p=>p.score),[0,1,-1,.5]);assert.equal(cells[2].confidence,0);
});
test('layers: cell squares, path line, dots, places, user and quiet spots',()=>{
 const d=fieldLayers(field,ll);
 assert.deepEqual(d.cells.features[0].geometry.coordinates[0],[[-1,-1],[-.5,-1],[-.5,-.5],[-1,-.5],[-1,-1]]);
 assert.equal(d.path.features[0].geometry.type,'LineString');assert.equal(d.samples.features.length,2);
 assert.equal(d.places.features[0].properties.name,'Hallway');assert.deepEqual(d.user.features[0].geometry.coordinates,[.5,.2]);
 assert.equal(d.spots.features[0].properties.rank,'1');
 assert.equal(fieldLayers({...field,path:[{x:0,z:0}],user:null},ll).path.features.length,0);
});
test('bounds cover the grid, path and user',()=>{
 assert.deepEqual(fieldBounds(field,ll),[[-1,-1],[1,2]]);
 assert.equal(fieldBounds({...field,cells:[],samples:[],path:[],places:[],user:null},ll),null);
});
test('card text: relative level, confidence and age, never dB',()=>{
 const spot=describe(field,'spot:-0.75,-0.75');
 assert.deepEqual(spot,{title:'Quiet spot 1',score:0,confidence:.9,detail:'measured 4 min ago · 6 m from you'});
 const cell=describe(field,'cell:-0.25,-0.75');assert.equal(cell.title,'Hallway');assert.equal(cell.detail,'nearest reading just now');
 assert.equal(describe(field,'cell:9,9'),null);assert.equal(describe(field,'cell:0.25,-0.75').score,-1);
 assert.equal(ago(75),'1 h ago');
 assert.equal(liveLabel(field).label,'Live · measured 2 spots');assert.doesNotMatch(liveLabel(field).label,/dB/);assert.match(liveLabel(field).title,/Grey = not measured/);
 assert.equal(liveLabel({...field,samples:[],message:'No positioned measurements yet'}).label,'Live · no measurements yet');
});
test('a 404, bad JSON shape or network error keeps the demo',async()=>{
 const reply=(status,body)=>async url=>{assert.ok(String(url).endsWith(FIELD_PATH));return new Response(JSON.stringify(body),{status})};
 assert.equal(await loadField('https://x',reply(404,{detail:'Not Found'})),null);
 assert.equal(await loadField('https://x',reply(200,{cells:'no'})),null);
 assert.equal(await loadField('https://x',async()=>{throw new TypeError('offline')}),null);
 assert.deepEqual(await loadField('https://x',reply(200,field)),field);
 const empty={...field,cell_m:null,cells:[],samples:[],path:[],places:[],user:null,quiet_spots:[]};
 assert.ok(isField(empty));assert.equal(hasData(empty),false);assert.equal(hasData(field),true);
});
