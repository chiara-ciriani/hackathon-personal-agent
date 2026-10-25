'use client';
import {useEffect,useRef,useState} from 'react';
export default function MapAccess(){
 const access=useRef<string|null>(null);
 const [message,setMessage]=useState('Opening the shared map…');
 useEffect(()=>{
  access.current ||= new URLSearchParams(window.location.hash.slice(1)).get('receipt');
  const receipt=access.current;
  window.history.replaceState(null,'','/map-access');
  const controller=new AbortController();
  void fetch('/api/map/access',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({receipt}),signal:controller.signal})
   .then(async r=>{if(!r.ok)throw Error();window.location.replace('/')})
   .catch(()=>{if(!controller.signal.aborted)setMessage('This map link expired. Share a new measurement from your phone.')});
  return()=>controller.abort();
 },[]);
 return <main style={{padding:32}}><p role="status">{message}</p></main>;
}
