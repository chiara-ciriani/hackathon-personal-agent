'use client';
import {useEffect,useState} from 'react';
import {ArrowLeft,ArrowUpRight,MapPin,Map as MapIcon} from 'lucide-react';
import {DEFAULT_VENUE_ID,venues,venueById,venueVisitorSource,type VenuePlan,type VenueSource} from '../../lib/venues';
import {loadVenueReadings,venueReadings,rankReadings,levelOf} from '../../lib/venue-data.mjs';
import './venue.css';

function SourceLink({source,children}:{source:VenueSource;children?:React.ReactNode}){
 return <a className="venue-source" href={source.url} target="_blank" rel="noreferrer">{children||source.label}<ArrowUpRight size={14} aria-hidden="true"/><span className="venue-sr-only"> (opens in a new tab)</span></a>;
}

type Reading={zone:string;name:string;dbfs:number;n:number;profile:string;observedOn:string;status?:string;relative?:number;otherProfile?:boolean};
// Grey = no data. Colour (ink) appears only for a zone with a released, consented device measurement.
function SoundLevel({venueId,readings}:{venueId:string;readings:{state:'loading'|'ok'|'failed';features:unknown[]}}){
 const ranked=rankReadings(venueReadings(venueId,readings.features)) as {status:string;profile:string|null;zones:Reading[]};
 const empty=ranked.status==='none';
 return <section className="venue-sound" aria-labelledby="sound-title"><h2 id="sound-title">Sound level</h2>
  {readings.state==='loading'?<p className="venue-muted" role="status">Checking for shared measurements…</p>:empty?<div className="venue-nodata" role="status">
   <span className="venue-unmeasured"><i aria-hidden="true"/>{readings.state==='failed'?'Could not load measurements':'No measurements yet'}</span>
   <p>{readings.state==='failed'?'The shared map could not be reached, so nothing is shown. Nothing is estimated in its place.':'No shared phone measurement has been released for this venue. Grey means no data, not quiet.'}</p></div>:
   <div className="venue-zones"><ul>{ranked.zones.map(z=><li key={z.zone||'venue'}>
    <span className="venue-zone-name">{z.zone?z.name:'Whole venue'}</span>
    <span className="venue-zone-bar" aria-hidden="true"><b style={{width:`${z.status==='ranked'?8+92*(z.relative??0):100}%`}} className={z.status==='ranked'?'':'is-single'}/></span>
    <span className="venue-zone-level">{z.status==='ranked'?`${levelOf(z.relative??0)} than the other measured zones`:'Measured · nothing to compare with'}</span>
    <small>{z.dbfs} dBFS, uncalibrated · {z.n} contribution{z.n===1?'':'s'} · <time dateTime={z.observedOn}>{new Date(z.observedOn).toLocaleString('en-US',{timeZone:'America/Los_Angeles',month:'short',day:'numeric',hour:'numeric',minute:'2-digit'})}</time> SF time{z.otherProfile?' · different phone profile, not compared':''}</small>
   </li>)}</ul>
   <p className="venue-muted">Released shared phone measurements only. Relative to other zones in the same capture profile, not dB SPL. Zones with no measurement are not listed and are not quiet.</p></div>}
 </section>;
}

function Plan({plan,note}:{plan:VenuePlan;note:string}){
 const [failed,setFailed]=useState(false);
 return <section className="venue-plan" aria-labelledby={`plan-${plan.id}`}>
  <div className="venue-section-heading"><h2 id={`plan-${plan.id}`}>Official plan</h2><SourceLink source={{label:'Open full PDF',url:plan.url}}/></div>
  <h3>{plan.title}</h3><p className="venue-muted">{plan.scope}</p>
  {failed?<div className="venue-plan-unavailable" role="status"><MapIcon size={32} strokeWidth={1.3} aria-hidden="true"/><p>The plan preview could not load.</p><SourceLink source={{label:'Open the official PDF',url:plan.url}}/></div>:
   <a className="venue-plan-preview" href={plan.url} target="_blank" rel="noreferrer" aria-label={`Open the official ${plan.title} PDF in a new tab`}>
    {/* An unmodified rendering of the operator's PDF, not generated geometry. */}
    {/* eslint-disable-next-line @next/next/no-img-element */}
    <img src={plan.image} alt={plan.imageAlt} onError={()=>setFailed(true)}/>
   </a>}
  <div className="venue-plan-caption"><p>{note}</p><p className="venue-muted">{plan.edition}</p><SourceLink source={plan.source}/></div>
 </section>;
}

export default function Venue(){
 const [venueId,setVenueId]=useState<string|null>(null);
 useEffect(()=>{
  const read=()=>setVenueId(new URLSearchParams(window.location.search).get('v')??DEFAULT_VENUE_ID);
  read();window.addEventListener('popstate',read);return()=>window.removeEventListener('popstate',read);
 },[]);
 const [readings,setReadings]=useState<{state:'loading'|'ok'|'failed';features:unknown[]}>({state:'loading',features:[]});
 useEffect(()=>{let live=true;void loadVenueReadings().then(r=>{if(live)setReadings(r)});return()=>{live=false}},[]);
 const venue=venueId===null?undefined:venueById(venueId);
 function select(id:string){setVenueId(id);window.history.pushState(null,'','/venue?v='+encodeURIComponent(id))}
 return <main className="venue-guide">
  <header className="venue-header">
   <a className="venue-back" href="/"><ArrowLeft size={18} aria-hidden="true"/>City map</a>
   <div className="venue-picker"><label htmlFor="venue-select">Venue</label><select id="venue-select" value={venue?.id??''} onChange={e=>select(e.target.value)}>
    {!venue&&<option value="" disabled>{venueId===null?'Loading…':'Choose a venue'}</option>}
    {venues.map(v=><option key={v.id} value={v.id}>{v.name}</option>)}
   </select></div>
  </header>
  {venueId===null?<p className="venue-loading" role="status">Loading venue information…</p>:!venue?
   <section className="venue-not-found"><h1>Venue not found</h1><p>This link does not match a place in our directory. Choose a venue above or return to the city map.</p><a className="venue-button" href="/">Back to the map<ArrowUpRight size={16} aria-hidden="true"/></a></section>:
   <article className="venue-content" key={venue.id}>
    <div className="venue-intro"><h1>{venue.name}</h1><p className="venue-address"><MapPin size={16} aria-hidden="true"/>{venue.address}</p><p className="venue-description">{venue.description}</p></div>
    <SoundLevel venueId={venue.id} readings={readings}/>
    <div className="venue-layout">
     <div className="venue-facts">
      {([{key:'hours',title:'Visiting hours'},{key:'access',title:'Access'},{key:'facilities',title:'Facilities'}] as const).map(({key,title})=><section className="venue-fact" key={key} aria-labelledby={`venue-${key}`}>
       <h2 id={`venue-${key}`}>{title}</h2><strong>{venue[key].summary}</strong><p>{venue[key].note}</p><SourceLink source={venue[key].source}>View source</SourceLink>
      </section>)}
      <div className="venue-location"><SourceLink source={{label:'View approximate location',url:`https://www.openstreetmap.org/?mlat=${venue.lat}&mlon=${venue.lng}#map=17/${venue.lat}/${venue.lng}`}}/><p>Venue vicinity; entrance not verified.</p></div>
     </div>
     <div className="venue-plans">{venue.plans.length?venue.plans.map(plan=><Plan key={plan.id} plan={plan} note={venue.planNote}/>):
      <section className="venue-plan venue-plan-empty"><MapIcon size={40} strokeWidth={1.2} aria-hidden="true"/><h2>Plan not verified</h2><p>{venue.planNote}</p><SourceLink source={venueVisitorSource(venue)}>Open visitor information</SourceLink></section>}
     </div>
    </div>
    <div className="venue-checked"><p>Visitor sources reviewed <time dateTime={venue.checkedOn}>October 24, 2026</time>. Hours are in San Francisco time.</p><p>Published information may change. Unverified details are marked above.</p></div>
   </article>}
 </main>;
}
