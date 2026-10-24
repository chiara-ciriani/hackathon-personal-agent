import test from 'node:test';
import assert from 'node:assert/strict';
import {connectPhoneSensors} from '../lib/browser-measurement.ts';

// Isolated API doubles: these tests never request real device permissions.
function browserFixture(t, {late = false} = {}) {
  const originals = new Map(['window','document','navigator','AudioContext','AudioWorkletNode'].map(k=>[k,Object.getOwnPropertyDescriptor(globalThis,k)]));
  t.after(()=>{ for(const [key,value] of originals) { if(value) Object.defineProperty(globalThis,key,value); else delete globalThis[key]; } });
  let captures = 0, tracksStopped = 0, nodes = 0, closed = 0, grant;
  class Track extends EventTarget {
    readyState='live'; muted=false;
    stop(){this.readyState='ended';tracksStopped++}
    getSettings(){return {autoGainControl:false,echoCancellation:false,noiseSuppression:false,deviceId:'private-device'}}
  }
  const track = new Track(), stream = {getTracks:()=>[track],getAudioTracks:()=>[track]};
  class Context {
    state='running'; sampleRate=8000; destination={}; onstatechange=null;
    audioWorklet={addModule:async()=>{}};
    resume(){return Promise.resolve()}
    close(){this.state='closed';closed++;return Promise.resolve()}
    createMediaStreamSource(){return {connect(){},disconnect(){}}}
  }
  class Node {
    constructor(){nodes++;this.port={onmessage:null,close(){},postMessage:()=>queueMicrotask(()=>this.port.onmessage?.({data:{type:'complete',result:{
      duration_seconds:30,rms_dbfs:-40,frame_level_spread_db:3,peaks_per_min:2,
      clipping_detected:false,sample_peak_dbfs:-20,frames:240,sample_rate:8000,
    }}}))}}
    connect(){} disconnect(){}
  }
  const document = Object.assign(new EventTarget(),{hidden:false});
  const window = Object.assign(new EventTarget(),{isSecureContext:true,AudioContext:Context});
  const navigator = {
    mediaDevices:{getUserMedia(){captures++;return late?new Promise(resolve=>{grant=()=>resolve(stream)}):Promise.resolve(stream)}},
    geolocation:{getCurrentPosition(resolve){resolve({coords:{latitude:37.77,longitude:-122.42,accuracy:15},timestamp:Date.now()})}},
  };
  for(const [key,value] of Object.entries({window,document,navigator,AudioContext:Context,AudioWorkletNode:Node})) Object.defineProperty(globalThis,key,{value,configurable:true});
  return {document,track,grant:()=>grant(),counts:()=>({captures,tracksStopped,nodes,closed})};
}
test('connection gets permission once but measures only after the agent request',async t=>{
  const env=browserFixture(t), control=new AbortController();
  const sensor=await connectPhoneSensors(control.signal,()=>{});
  assert.deepEqual(env.counts(),{captures:1,tracksStopped:0,nodes:0,closed:0});
  let tick=0; t.mock.method(performance,'now',()=>tick++===0?0:30000);
  const request='22222222-2222-4222-8222-222222222222';
  const result=await sensor.measure(request,()=>{});
  assert.equal(result.contribution.id,request);
  assert.equal(result.contribution.source,'device');
  assert.equal(env.counts().nodes,1);
  assert.equal(env.counts().tracksStopped,0);
  control.abort();
  assert.equal(env.counts().tracksStopped,1);
  assert.equal(env.counts().closed,1);
});
test('hiding the page stops sensors and rejects further agent capture',async t=>{
  const env=browserFixture(t), control=new AbortController();
  const sensor=await connectPhoneSensors(control.signal,()=>{});
  env.document.hidden=true;
  env.document.dispatchEvent(new Event('visibilitychange'));
  assert.equal(env.counts().tracksStopped,1);
  await assert.rejects(sensor.measure('ignored',()=>{}),/not connected/);
});
test('cancel before microphone permission resolves stops a late stream',async t=>{
  const env=browserFixture(t,{late:true}),control=new AbortController();
  const connection=connectPhoneSensors(control.signal,()=>{});
  control.abort();
  await assert.rejects(connection,/disconnected/);
  env.grant();
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(env.counts().tracksStopped,1);
  assert.equal(env.counts().nodes,0);
});
