// Shared by the AudioWorklet and tests. Only numeric summaries leave the processor.
// 125 ms frames; L10-L90 spread; onsets above the running median + 10 dB.
export const DURATION_SECONDS = 10;
const db = power => Math.min(0, 10 * Math.log10(power + 1e-12));
export function percentile(values, q) {
  if (!values.length) throw new Error('No measured frames');
  const sorted = [...values].sort((a, b) => a - b);
  const p = (sorted.length - 1) * q, low = Math.floor(p), high = Math.ceil(p);
  return sorted[low] + (sorted[high] - sorted[low]) * (p - low);
}
export class AcousticAccumulator {
  constructor(rate) {
    if (!Number.isFinite(rate) || rate < 8000 || rate > 192000) throw new Error('Unsupported sample rate');
    this.rate = rate;
    this.frameSize = Math.round(rate / 8);
    this.target = rate * DURATION_SECONDS;
    this.samples = 0; this.sum = 0; this.frameSum = 0; this.frameFill = 0;
    this.levels = []; this.onsets = 0; this.above = false; this.peak = 0;
  }
  get done() { return this.samples >= this.target; }
  append(input) {
    for (const sample of input) {
      if (this.done) break;
      if (!Number.isFinite(sample)) throw new Error('Invalid microphone samples');
      const power = sample * sample;
      this.sum += power; this.frameSum += power; this.samples++; this.frameFill++;
      this.peak = Math.max(this.peak, Math.abs(sample));
      if (this.frameFill === this.frameSize) {
        const level = db(this.frameSum / this.frameFill);
        this.levels.push(level);
        const above = level > percentile(this.levels, 0.5) + 10;
        if (above && !this.above) this.onsets++;
        this.above = above; this.frameFill = 0; this.frameSum = 0;
      }
    }
  }
  progress() {
    return {seconds: this.samples / this.rate, level_dbfs: this.levels.at(-1) ?? null};
  }
  result() {
    if (!this.done) throw new Error('Measurement incomplete');
    return {
      duration_seconds: this.samples / this.rate,
      rms_dbfs: db(this.sum / this.samples),
      frame_level_spread_db: percentile(this.levels, 0.9) - percentile(this.levels, 0.1),
      peaks_per_min: this.onsets * 60 / (this.samples / this.rate),
      clipping_detected: this.peak >= 0.999,
      sample_peak_dbfs: db(this.peak * this.peak),
      frames: this.levels.length, sample_rate: this.rate,
    };
  }
}
