import {AcousticAccumulator} from './acoustics.mjs';

class QuietMeasurement extends AudioWorkletProcessor {
  constructor() {
    super();
    this.meter = new AcousticAccumulator(sampleRate);
    this.lastFrames = 0;
    this.started = false;
    this.port.onmessage = event => { if (event.data === 'start') this.started = true; };
  }
  process(inputs, outputs) {
    // Never play microphone input back through the speaker.
    for (const output of outputs) for (const channel of output) channel.fill(0);
    if (!this.started) return true;
    const mono = inputs[0]?.[0];
    if (!mono?.length) return true;
    try {
      this.meter.append(mono);
      if (this.meter.done) {
        this.port.postMessage({type: 'complete', result: this.meter.result()});
        return false;
      }
      if (this.meter.levels.length !== this.lastFrames) {
        this.lastFrames = this.meter.levels.length;
        this.port.postMessage({type: 'progress', ...this.meter.progress()});
      }
      return true;
    } catch {
      this.port.postMessage({type: 'error'});
      return false;
    }
  }
}
registerProcessor('quiet-measurement', QuietMeasurement);
