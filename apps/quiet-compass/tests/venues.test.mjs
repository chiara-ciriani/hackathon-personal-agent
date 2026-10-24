import test from 'node:test';
import assert from 'node:assert/strict';
import {venueById,venueMapProperties,venues} from '../lib/venues.ts';
import {measurementText} from '../lib/real-map.mjs';

test('absent selection has a default but an invalid link cannot silently select a different venue',()=>{
 assert.equal(venueById(null)?.id,'moscone');
 for(const id of ['missing','', '__proto__','MOSCONE'])assert.equal(venueById(id),undefined);
});

test('old gardens links resolve to the canonical identity used by the map',()=>{
 const legacy=venueById('ybca');
 assert.equal(legacy,venueById('yerba-buena-gardens'));
 assert.equal(venueMapProperties(legacy).id,'yerba-buena-gardens');
});

test('visitor information and official plans do not turn map locations into acoustic readings',()=>{
 for(const venue of venues){
  const properties=venueMapProperties(venue);
  assert.equal(venueById(properties.id),venue);
  assert.equal(properties.evidence,'unmeasured_candidate');
  assert.equal(measurementText(properties),'No sound measurement');
  for(const acoustic of ['score','bias','dbfs','cnel','medianDb','maxDb'])assert.equal(properties[acoustic],undefined);
 }
});
