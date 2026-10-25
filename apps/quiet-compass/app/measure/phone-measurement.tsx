'use client';

import {useEffect, useRef, useState} from 'react';
import {Button} from '../../components/ui/button';
import {ArrowLeft, Check, Compass, Link2, Mic, ShieldCheck, Square} from 'lucide-react';
import {connectPhoneSensors, type PhoneSensor, type Reading} from '../../lib/browser-measurement';

type Stage = 'unlinked' | 'checking' | 'ready' | 'connecting' | 'waiting' | 'measuring' | 'sending' | 'disconnected' | 'native';
type Recommendation = {message: string; action: 'move' | 'stay' | 'unknown'; expires_at: string; destination: {name: string | null; lat: number; lon: number; walk_minutes: number; age_minutes: number} | null};
type PhoneReply = {status: string; client?: 'native' | 'browser'; error?: string; expires_at?: string; request_id?: string; duration_seconds?: number; recommendation?: Recommendation};
const agentInstruction = 'Connect my phone with Quiet Compass using connect_phone and give me the link. I want to open the iPhone app from that link for room mapping. After I approve access, check phone_measurement_status. If client is native, call request_phone_measurement with mode=walk and duration_seconds=60. Read the acoustic analysis and quiet_spots, then use send_phone_recommendation with spot_index to recommend a measured quieter spot. The app displays the advice and direction. If I choose the browser, use mode=sample and wait for phone_measurement_status. Use the access_receipt to find options for my goal, walking limit and return time. Send your recommendation in English with send_phone_recommendation. If comparable data is missing, say so; never invent a quieter place.';

export default function PhoneMeasurement() {
  const [recommendation, setRecommendation] = useState<Recommendation | null>(null);
  const [stage, setStage] = useState<Stage>('unlinked'), [consent, setConsent] = useState(false);
  const [seconds, setSeconds] = useState(0), [level, setLevel] = useState<number | null>(null);
  const [reading, setReading] = useState<Reading | null>(null), [delivered, setDelivered] = useState(false);
  const [message, setMessage] = useState(''), [expires, setExpires] = useState(''), [now, setNow] = useState(0);
  const [serverReady, setServerReady] = useState<boolean | null>(null);
  const token = useRef(''), controller = useRef<AbortController | null>(null), sensor = useRef<PhoneSensor | null>(null);
  const mounted = useRef(true), joined = useRef(false);
  const active = ['waiting', 'measuring', 'sending'].includes(stage);
  const remaining = expires ? Math.max(0, Math.ceil((Date.parse(expires) - now) / 60000)) : 15;

  async function phone(action: string, body: object = {}, signal?: AbortSignal): Promise<PhoneReply> {
    const response = await fetch('/api/phone/' + action, {
      method: 'POST', headers: {'Content-Type': 'application/json', Authorization: 'Bearer ' + token.current},
      body: JSON.stringify(body), signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(15000)]) : AbortSignal.timeout(15000),
      cache: 'no-store',
    });
    const data = await response.json() as PhoneReply;
    if (!response.ok) throw new Error(data.error || 'Could not connect to the server.');
    return data;
  }
  function revoke() {
    if (!token.current) return;
    void fetch('/api/phone/disconnect', {method: 'POST',
      headers: {'Content-Type': 'application/json', Authorization: 'Bearer ' + token.current},
      body: '{}', keepalive: true}).catch(() => {});
  }
  function stop(reason = 'Phone disconnected. Microphone off.') {
    const current = controller.current, currentSensor = sensor.current;
    controller.current = null; sensor.current = null; joined.current = false;
    current?.abort(); currentSensor?.close();
    revoke();
    if (mounted.current) { setStage('disconnected'); setMessage(reason); setConsent(false); }
  }
  useEffect(() => {
    mounted.current = true; setNow(Date.now());
    const hash = new URLSearchParams(window.location.hash.slice(1));
    const pair = hash.get('pair');
    if (pair && /^[A-Za-z0-9_-]{43}$/.test(pair)) {
      token.current = pair;
      // Keep the browser capability out of history, referrers, screenshots and clipboard.
      window.history.replaceState(null, '', window.location.pathname);
    }
    let alive = true;
    if (token.current) {
      setStage('checking');
      phone('status').then(data => {
        if (!alive) return;
        if (!data.expires_at || !Number.isFinite(Date.parse(data.expires_at))) throw new Error('Invalid connection link.');
        setExpires(data.expires_at); setStage('ready');
      }).catch(e => { if (alive) { setStage('disconnected'); setMessage(e.message); } });
    } else {
      fetch('/api/mcp/status', {cache: 'no-store', signal: AbortSignal.timeout(7000)})
        .then(r => r.json()).then(raw => { if (alive) { const data = raw as {phoneReady?: boolean}; setServerReady(data.phoneReady === true); } })
        .catch(() => { if (alive) setServerReady(false); });
    }
    const tick = setInterval(() => setNow(Date.now()), 1000);
    return () => {
      alive = false; mounted.current = false; clearInterval(tick);
      controller.current?.abort(); sensor.current?.close();
      if (joined.current) revoke();
    };
  }, []);
  useEffect(() => {
    if (controller.current && expires && now >= Date.parse(expires)) stop('Your 15-minute connection expired. Microphone off.');
  }, [now, expires]);

  function delay(signal: AbortSignal) {
    return new Promise<void>((resolve, reject) => {
      const abort = () => { clearTimeout(timer); reject(new Error('Disconnected')); };
      const timer = setTimeout(() => { signal.removeEventListener('abort', abort); resolve(); }, 2000);
      signal.addEventListener('abort', abort, {once: true});
      if (signal.aborted) abort();
    });
  }
  async function listen(capture: AbortController, connected: PhoneSensor) {
    while (!capture.signal.aborted) {
      const reply = await phone('poll', {}, capture.signal);
      setRecommendation(reply.recommendation || null);
      if (reply.status === 'measure') {
        if (!reply.request_id || reply.duration_seconds !== 30) throw new Error('The agent requested an invalid measurement.');
        setStage('measuring'); setSeconds(0); setLevel(null); setReading(null); setDelivered(false); setRecommendation(null); setMessage('');
        let result: object;
        try {
          const value = await connected.measure(reply.request_id, (s, l) => {
            if (mounted.current && !capture.signal.aborted) { setSeconds(s); setLevel(l); }
          });
          if (capture.signal.aborted) return;
          setReading(value); setSeconds(30);
          result = {request_id: reply.request_id, upload: {contract_version: 1, contribution: value.contribution, share_consent: true}};
        } catch (e) {
          if (capture.signal.aborted) return;
          setMessage(e instanceof Error ? e.message : 'Measurement interrupted.');
          result = {request_id: reply.request_id, error: 'capture_failed'};
        }
        setStage('sending');
        let confirmation: PhoneReply | undefined;
        // Retry exactly the same request/result. Never capture again to retry delivery.
        for (let attempt = 0; attempt < 3; attempt++) {
          try { confirmation = await phone('result', result, capture.signal); break; }
          catch (e) { if (attempt === 2 || capture.signal.aborted) throw e; await delay(capture.signal); }
        }
        if (capture.signal.aborted) return;
        setDelivered(confirmation?.status === 'complete');
        if (confirmation?.status === 'complete') setMessage('Summary received. Your agent can now use it to check nearby options.');
        else setMessage('This measurement did not grant access. Your agent can request another attempt.');
        setStage('waiting');
      }
      await delay(capture.signal);
    }
  }
  async function connect() {
    if (!consent || !token.current || controller.current) return;
    const capture = new AbortController(); controller.current = capture;
    setStage('connecting'); setMessage('');
    try {
      const connected = await connectPhoneSensors(capture.signal, reason => {
        if (joined.current && controller.current) stop(reason);
      });
      if (capture.signal.aborted) { connected.close(); return; }
      sensor.current = connected;
      const ready = await phone('consent', {microphone_consent: true, share_consent: true}, capture.signal);
      if (!ready.expires_at || Date.parse(ready.expires_at) <= Date.now()) throw new Error('This link expired. Ask your agent for a new one.');
      joined.current = true;
      setExpires(ready.expires_at); setStage('waiting');
      await listen(capture, connected);
    } catch (e) {
      if (capture.signal.aborted) return;
      const wasJoined = joined.current;
      const connected = sensor.current;
      controller.current = null; sensor.current = null; joined.current = false;
      capture.abort(); connected?.close();
      if (wasJoined) revoke();
      if (mounted.current) {
        setStage(wasJoined ? 'disconnected' : 'ready');
        setMessage(e instanceof Error ? e.message : 'Could not connect your phone.');
      }
    }
  }
  async function copySetup() {
    try { await navigator.clipboard.writeText(agentInstruction); setMessage('Copied. Paste it in your agent chat to get a connection link.'); }
    catch { setMessage(agentInstruction); }
  }

  const labels: Record<Stage, string> = {
    unlinked: 'Not linked', checking: 'Checking link', ready: 'Ready to connect',
    connecting: 'Waiting for permission', waiting: 'Connected', measuring: 'Measuring',
    sending: 'Sending summary', disconnected: 'Disconnected', native: 'Continue in the iPhone app',
  };
  const m = reading?.contribution.measurement;
  return <main className="phone-measure" lang="en">
    <header className="pm-header">
      <a className="pm-brand" href="/" aria-label="Quiet Compass map"><Compass size={22} strokeWidth={1.4}/><span>Quiet Compass</span></a>
      <a className="pm-back" href="/"><ArrowLeft size={14}/>Map</a>
    </header>
    <div className="pm-content">
      <div className="pm-intro"><h1>Connect your phone.</h1><p>Link once. Your agent analyzes the sound, finds measured quieter spots and sends advice back.</p></div>
      <section className="pm-panel" aria-label="Phone connection">
        <div className="pm-status"><span className={active ? 'pm-dot is-active' : 'pm-dot'}/><span>{labels[stage]}</span>{active && <small>{remaining} min left</small>}</div>
        <div className="pm-dial" aria-hidden="true">
          <svg viewBox="0 0 160 160"><circle cx="80" cy="80" r="73" className="pm-ring-track"/><circle cx="80" cy="80" r="73" className="pm-ring-progress" strokeDasharray={459} strokeDashoffset={459*(1-seconds/30)}/></svg>
          <div>{stage === 'measuring' ? <Mic size={24} strokeWidth={1.4}/> : delivered ? <Check size={24}/> : <Link2 size={24} strokeWidth={1.4}/>}
            <strong>{stage === 'measuring' ? Math.max(0,30-Math.floor(seconds)) + ' s' : stage === 'sending' ? 'Sending' : active ? 'Listening for agent' : 'Phone link'}</strong>
            <span>{stage === 'measuring' && level !== null ? level.toFixed(1)+' dBFS' : active ? 'Microphone enabled' : stage === 'connecting' ? 'Permission pending' : 'Microphone off'}</span>
          </div>
        </div>
        <div className="pm-sr-only" role="progressbar" aria-label="Measurement progress in seconds" aria-valuemin={0} aria-valuemax={30} aria-valuenow={Math.floor(seconds)}/>
        <p className="pm-hint" role="status">{stage === 'unlinked' ? 'Open the connection link from your agent on this phone.' : stage === 'checking' ? 'Checking your private connection link…' : stage === 'ready' ? 'Allow your agent to request 30-second measurements.' : stage === 'connecting' ? 'Allow microphone and location access in your browser.' : stage === 'measuring' ? 'Requested by your agent. Keep your phone still and this page open.' : stage === 'sending' ? 'Sending the summary directly to your agent.' : stage === 'waiting' ? 'Ready for your agent. Keep this page open and your phone unlocked.' : stage === 'native' ? 'Approve the connection in QC Walk Map. Your agent can then analyze the room and send advice there.' : 'Ask your agent for a new connection link.'}</p>
        {(stage === 'ready' || stage === 'native') && <div className="pm-native">
          <span className="pm-label">ROOM MAP + SOUND ANALYSIS</span>
          <p>Use QC Walk Map for a measured room map, sound analysis and directions from your agent.</p>
          <a className="pm-button pm-primary" href={'quietcompass-walk://connect#pair=' + token.current} onClick={()=>setStage('native')}>Open iPhone app<Compass size={15}/></a>
          <p className="pm-detail">Requires the updated QC Walk Map app installed on your iPhone. Approve access in the app; no audio or camera images are sent.</p>
          {stage === 'native' && <Button className="pm-button pm-secondary" onClick={()=>setStage('ready')}>Use browser instead</Button>}
        </div>}
        {stage === 'ready' && <p className="pm-label">OR MEASURE SOUND IN YOUR BROWSER</p>}
        {stage === 'ready' && <label className="pm-consent"><input type="checkbox" checked={consent} onChange={e=>setConsent(e.target.checked)}/><span>Allow measurements and automatic sharing of sound summaries, approximate area and time with Quiet Compass for up to 15 minutes.</span></label>}
        {stage === 'ready' && <Button className="pm-button pm-primary" onClick={connect} disabled={!consent}>Connect browser</Button>}
        {(active || stage === 'connecting') && <Button className="pm-button pm-secondary" onClick={()=>stop()}><Square size={13}/>Disconnect</Button>}
        {(stage === 'unlinked' || stage === 'disconnected') && <Button className="pm-button pm-primary" onClick={copySetup}>Copy connection request<Link2 size={14}/></Button>}
        {stage === 'unlinked' && serverReady === false && <p className="pm-notice">Server update needed before phones can connect.</p>}
        {message && <p className="pm-notice" role="status">{message}</p>}
        <div className="pm-footnote"><ShieldCheck size={14}/><span>No audio saved or uploaded. Leaving this page disconnects the microphone.</span></div>
      </section>
      {recommendation && <section className="pm-recommendation" aria-live="polite">
        <span className="pm-label">FROM YOUR AGENT</span>
        <h2>{recommendation.action === 'move' ? 'A quieter option.' : recommendation.action === 'stay' ? 'Stay here.' : 'More data needed.'}</h2>
        <p>{recommendation.message}</p>
        {recommendation.destination && <p className="pm-detail">{recommendation.destination.name || 'Area '+recommendation.destination.lat.toFixed(3)+', '+recommendation.destination.lon.toFixed(3)} · ~{recommendation.destination.walk_minutes} min walk · measured {recommendation.destination.age_minutes} min ago. Walking time is a straight-line estimate.</p>}
        {Date.parse(recommendation.expires_at)<=now && <p className="pm-notice">This recommendation needs a fresh measurement.</p>}
      </section>}
      {reading && m && <section className="pm-reading" aria-label="Latest phone measurement">
        <div className="pm-reading-title"><span className="pm-label">LATEST MEASUREMENT</span><span>{delivered ? 'Received by server' : 'Delivery unconfirmed'}</span></div>
        <dl><div><dt>Level</dt><dd>{m.rms_dbfs.toFixed(1)}<small>dBFS</small></dd></div><div><dt>Variation</dt><dd>{m.frame_level_spread_db.toFixed(1)}<small>dB</small></dd></div><div><dt>Peaks</dt><dd>{m.peaks_per_min.toFixed(1)}<small>/ min</small></dd></div></dl>
        <p className="pm-detail">30 seconds · no clipping · relative, uncalibrated levels</p>
      </section>}
      <details className="pm-how"><summary>How it works</summary><ol><li>Your agent creates a private link. Open the iPhone app for room mapping, or choose browser sound measurements. Approve access once.</li><li>The agent requests an analysis. The app returns private acoustic levels and a room map. The browser shares a coarse sound summary.</li><li>The agent sends a recommendation to the connected app or browser. The app shows a direction only to a measured spot; missing data stays unknown.</li></ol><p>Quiet Compass must be connected to your agent. This page does not install that connection.</p></details>
    </div>
  </main>;
}
