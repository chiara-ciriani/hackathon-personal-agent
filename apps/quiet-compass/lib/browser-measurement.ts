import {captureProfile, coarseLocation, makeContribution, measurementProblem} from './phone-measurement.mjs';

export type AcousticResult = {
  duration_seconds: number; rms_dbfs: number; frame_level_spread_db: number; peaks_per_min: number;
  clipping_detected: boolean; sample_peak_dbfs: number; frames: number; sample_rate: number;
};
export type Reading = {contribution: ReturnType<typeof makeContribution>; endedAt: number};
export type PhoneSensor = {
  measure: (requestId: string, progress: (seconds: number, level: number | null) => void) => Promise<Reading>;
  close: () => void;
};

// One explicit phone gesture activates sensors for the bounded connection. Only an
// authenticated agent request starts a worklet; all sample buffers stay in that worklet.
export async function connectPhoneSensors(signal: AbortSignal, onDisconnect: (reason: string) => void): Promise<PhoneSensor> {
  if (!window.isSecureContext) throw new Error('Open the HTTPS link to connect your phone.');
  if (!navigator.mediaDevices?.getUserMedia || !window.AudioContext || !navigator.geolocation) {
    throw new Error('This browser cannot measure sound. Open the link in an up-to-date Safari or Chrome.');
  }
  if (signal.aborted || document.hidden) throw new Error('Keep this page open to connect.');
  const context = new AudioContext();
  let stream: MediaStream | undefined, active = true, measuring = false;
  let node: AudioWorkletNode | undefined, source: MediaStreamAudioSourceNode | undefined;
  let rejectInterruption: (reason: Error) => void = () => {};
  const interrupted = new Promise<never>((_, reject) => { rejectInterruption = reject; });
  const close = (reason = 'Phone disconnected. Microphone off.') => {
    if (!active) return;
    active = false;
    signal.removeEventListener('abort', abort);
    document.removeEventListener('visibilitychange', hidden);
    window.removeEventListener('pagehide', abort);
    context.onstatechange = null;
    stream?.getTracks().forEach(track => { track.removeEventListener('ended', lostInput); track.removeEventListener('mute', lostInput); track.stop(); });
    if (node) { node.port.onmessage = null; node.port.close(); node.disconnect(); node = undefined; }
    source?.disconnect(); source = undefined;
    if (context.state !== 'closed') void context.close().catch(() => {});
    rejectInterruption(new Error(reason));
    onDisconnect(reason);
  };
  const abort = () => close();
  const hidden = () => { if (document.hidden) close('Phone disconnected because this page is no longer visible.'); };
  const lostInput = () => close('Microphone interrupted. Reconnect your phone.');
  signal.addEventListener('abort', abort, {once: true});
  document.addEventListener('visibilitychange', hidden);
  window.addEventListener('pagehide', abort);
  const setupTimer = setTimeout(() => close('Permission setup timed out. Check microphone and location access.'), 60000);
  const resumed = context.resume(); // Must happen within the user's tap on iOS.
  const streamPromise = navigator.mediaDevices.getUserMedia({audio: {
    channelCount: {ideal: 1}, echoCancellation: false, noiseSuppression: false, autoGainControl: false,
  }, video: false}).then(value => {
    if (!active) { value.getTracks().forEach(track => track.stop()); throw new Error('Connection cancelled.'); }
    stream = value;
    return value;
  });
  function locate() {
    return new Promise<GeolocationPosition>((resolve, reject) => {
      navigator.geolocation.getCurrentPosition(resolve, () => reject(new Error('Allow location access to place your contribution on the map.')),
        {enableHighAccuracy: true, maximumAge: 0, timeout: 15000});
    });
  }
  try {
    const [input, position] = await Promise.race([Promise.all([streamPromise, locate(), resumed]), interrupted]);
    coarseLocation(position); // Check permission and usable accuracy before advertising readiness.
    if (!context.audioWorklet) throw new Error('Use an up-to-date Safari or Chrome to connect your microphone.');
    await Promise.race([context.audioWorklet.addModule('/measure/processor.js'), interrupted]);
    const track = input.getAudioTracks()[0];
    if (!track || track.readyState !== 'live' || track.muted) throw new Error('Microphone unavailable.');
    track.addEventListener('ended', lostInput, {once: true});
    track.addEventListener('mute', lostInput, {once: true});
    context.onstatechange = () => { if (active && context.state !== 'running') lostInput(); };
    const profile = captureProfile(crypto.randomUUID().replaceAll('-', '').slice(0, 20), track.getSettings(), context.sampleRate);
    clearTimeout(setupTimer);
    return {
      close,
      async measure(requestId, progress) {
        if (!active || signal.aborted || document.hidden) throw new Error('Phone is not connected.');
        if (measuring) throw new Error('A measurement is already running.');
        measuring = true;
        let timer: ReturnType<typeof setTimeout> | undefined;
        try {
          const location = coarseLocation(await Promise.race([locate(), interrupted]));
          node = new AudioWorkletNode(context, 'quiet-measurement', {channelCount: 1, channelCountMode: 'explicit', numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [1]});
          const completed = new Promise<AcousticResult>((resolve, reject) => {
            timer = setTimeout(() => reject(new Error('The phone did not finish measuring.')), 25000);
            node!.onprocessorerror = () => reject(new Error('The browser interrupted the measurement.'));
            node!.port.onmessage = event => {
              if (!active) return;
              const data = event.data;
              if (data.type === 'progress') progress(data.seconds, data.level_dbfs);
              else if (data.type === 'complete') resolve(data.result);
              else if (data.type === 'error') reject(new Error('Invalid microphone signal.'));
            };
          });
          source = context.createMediaStreamSource(input);
          source.connect(node); node.connect(context.destination);
          const started = performance.now();
          node.port.postMessage('start'); progress(0, null);
          const result = await Promise.race([completed, interrupted]);
          const elapsed = (performance.now() - started) / 1000;
          if (elapsed < 28 || elapsed > 40) throw new Error('Measurement was interrupted. Keep this page open.');
          const problem = measurementProblem(result);
          if (problem) throw new Error(problem);
          const endedAt = Date.now();
          return {contribution: makeContribution({result, location, profile, id: requestId, endedAt}), endedAt};
        } finally {
          clearTimeout(timer);
          if (node) { node.port.onmessage = null; node.port.close(); node.disconnect(); node = undefined; }
          source?.disconnect(); source = undefined;
          measuring = false;
        }
      },
    };
  } catch (error) {
    clearTimeout(setupTimer);
    close('Could not connect the microphone.');
    if (error instanceof DOMException && error.name === 'NotAllowedError') {
      throw new Error('Allow microphone and location access in this site\'s settings and try again.');
    }
    throw error;
  }
}
