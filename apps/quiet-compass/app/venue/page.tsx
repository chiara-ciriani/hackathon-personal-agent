'use client';
import {useEffect,useState} from 'react';
import {Building2,Compass,MapPin} from 'lucide-react';
import {venues,venueById} from '../../lib/venues';
import '../map.css';

export default function Venue(){
 const [venueId,setVenueId]=useState('moscone');
 useEffect(()=>{setVenueId(new URLSearchParams(window.location.search).get('v')||'moscone')},[]);
 const venue=venueById(venueId);
 return <main className="quiet-unavailable-page">
  <a className="quiet-back" href="/"><Compass size={22}/>Back to the map</a>
  <div className="quiet-venue-picker"><label htmlFor="venue">Venue</label><select id="venue" value={venue.id} onChange={e=>{setVenueId(e.target.value);window.history.replaceState(null,'','/venue?v='+encodeURIComponent(e.target.value))}}>{venues.map(v=><option key={v.id} value={v.id}>{v.name}</option>)}</select></div>
  <section className="quiet-unavailable-panel" aria-label="Venue data availability">
   <Building2 size={44} strokeWidth={1}/><h1>{venue.name}</h1><span className="quiet-card-none">No indoor data available</span>
   <p>No verified floor plan or acoustic measurements have been received for this venue.</p>
   <div className="quiet-empty-grid"><article><strong>Sound level</strong><b>—</b><span>No measurement</span></article><article><strong>Indoor map</strong><b>—</b><span>No verified plan</span></article><article><strong>Contributions</strong><b>—</b><span>No venue data connected</span></article></div>
   <a className="quiet-source-link" href={`https://www.openstreetmap.org/?mlat=${venue.lat}&mlon=${venue.lng}#map=17/${venue.lat}/${venue.lng}`} target="_blank" rel="noreferrer"><MapPin size={15}/>View venue location</a>
  </section>
 </main>;
}
