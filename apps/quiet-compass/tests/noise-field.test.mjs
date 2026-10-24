import test from 'node:test';
import assert from 'node:assert/strict';
import {CELL_LAT,CELL_LNG,buildReportField,describeCell,load311Reports,parseReport,FIELD_NOTE,FILTER_NOTE} from '../lib/noise-field.mjs';

const NOW=new Date('2026-10-24T21:00:00Z');
const row=(lat,long,extra={})=>({requested_datetime:'2026-10-20T10:00:00.000',lat:String(lat),long:String(long),service_subtype:'other_excessive_noise',...extra});
const pt=(lng,lat)=>({type:'Feature',geometry:{type:'Point',coordinates:[lng,lat]},properties:{}});

test('parseReport keeps real SF coordinates and drops missing or out-of-city ones',()=>{
 assert.deepEqual(parseReport(row(37.7766,-122.4119)).geometry.coordinates,[-122.4119,37.7766]);
 assert.equal(parseReport(row(37.7766,-122.4119)).properties.kind,'other excessive noise');
 assert.equal(parseReport({lat:'',long:''}),null);assert.equal(parseReport(row(40.7,-74)),null);assert.equal(parseReport(null),null);
});
test('empty input yields no cells: no reports means unknown, never a quiet value',()=>{
 const f=buildReportField([],[]);
 assert.deepEqual([f.collection.features.length,f.total,f.cells],[0,0,0]);
});
test('reports and CAD counts are summed per area; empty areas are absent; no dB anywhere',()=>{
 const a=[-122.4119,37.7766],b=[-122.4,37.79];
 const reports=[pt(...a),pt(a[0]+0.0001,a[1]+0.0001),pt(...b)];
 const cad=[{...pt(a[0]+0.0002,a[1]),properties:{count:3}}];
 const f=buildReportField(reports,cad);
 assert.equal(f.total,6);assert.equal(f.cells,2);
 const big=f.collection.features.find(x=>x.properties.n===5);
 assert.deepEqual([big.properties.r311,big.properties.cad],[2,3]);
 const [w,s]=big.geometry.coordinates[0][0];
 assert.ok(a[0]>=w&&a[0]<w+CELL_LNG&&a[1]>=s&&a[1]<s+CELL_LAT);
 for(const x of f.collection.features){assert.ok(x.properties.t>0&&x.properties.t<=1);assert.ok(!('db' in x.properties)&&!('score' in x.properties))}
});
test('levels are terciles of non-empty areas and are relative (few/some/many)',()=>{
 const reports=[];
 // 6 areas with 1,2,3,4,5,6 reports
 for(let n=1;n<=6;n++)for(let k=0;k<n;k++)reports.push(pt(-122.5+n*0.02,37.7));
 const f=buildReportField(reports,[]);
 const lv=Object.fromEntries(f.collection.features.map(x=>[x.properties.n,x.properties.level]));
 assert.deepEqual(lv,{1:'few',2:'few',3:'some',4:'some',5:'many',6:'many'});
});
test('CAD rows with zero or invalid counts and out-of-city points are ignored',()=>{
 const f=buildReportField([],[{...pt(-122.41,37.77),properties:{count:0}},{...pt(-70,40),properties:{count:9}},{...pt(-122.41,37.77),properties:{count:2}}]);
 assert.equal(f.total,2);
});
test('describeCell and notes say reports, not dB',()=>{
 const t=describeCell({n:5,r311:2,cad:3,days:30});
 assert.match(t,/5 reports/);assert.match(t,/2 311 complaints/);assert.match(t,/3 police noise-nuisance calls/);assert.match(t,/not dB/);
 assert.match(FIELD_NOTE,/unknown, not quiet/);assert.match(FILTER_NOTE,/nothing about decibels/);
});
test('load311Reports queries the 30-day window on the real dataset, with mocked fetch',async()=>{
 const calls=[];
 const fetchFn=async url=>{calls.push(url);return {ok:true,json:async()=>[row(37.7766,-122.4119),{lat:'',long:''}]}};
 const out=await load311Reports(fetchFn,NOW);
 assert.equal(out.features.length,1);
 const u=decodeURIComponent(calls[0]);
 assert.ok(u.startsWith('https://data.sf.gov/resource/vw6y-z8j6.json?'));
 assert.match(u,/requested_datetime >= '2026-09-24T00:00:00'/);assert.match(u,/service_name in\('Noise','Noise Report'\)/);
});
test('load311Reports throws when DataSF fails: no fallback data',async()=>{
 await assert.rejects(load311Reports(async()=>({ok:false,status:503,json:async()=>[]}),NOW),/503/);
 await assert.rejects(load311Reports(async()=>({ok:true,json:async()=>({error:1})}),NOW),/unexpected/);
 await assert.rejects(load311Reports(async()=>{throw new Error('offline')},NOW),/offline/);
});
