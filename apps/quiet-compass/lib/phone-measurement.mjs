export function coarseLocation(position, now = Date.now()) {
  const {latitude, longitude, accuracy} = position.coords;
  if (![latitude, longitude, accuracy, position.timestamp].every(Number.isFinite) ||
      Math.abs(latitude) > 90 || Math.abs(longitude) > 180 || accuracy < 0 || accuracy > 100 ||
      Math.abs(now - position.timestamp) > 60000) {
    throw new Error('Location is not accurate enough. Try near a window or outside.');
  }
  return {lat: Number(latitude.toFixed(3)), lon: Number(longitude.toFixed(3)), timestamp: position.timestamp};
}
export function measurementProblem(result) {
  if (!result || ![result.duration_seconds, result.rms_dbfs, result.frame_level_spread_db,
    result.peaks_per_min, result.sample_peak_dbfs, result.frames, result.sample_rate].every(Number.isFinite) ||
    result.duration_seconds !== 30 || result.frames < 239 || result.sample_rate < 8000 ||
    result.rms_dbfs > 0 || result.rms_dbfs < -120 || result.frame_level_spread_db < 0 ||
    result.peaks_per_min < 0 || typeof result.clipping_detected !== 'boolean') {
    return 'Incomplete measurement. Try again.';
  }
  if (result.sample_peak_dbfs <= -119) return 'No microphone signal received. Check permissions and try again.';
  if (result.clipping_detected) return 'Microphone clipping detected. Move it away from the sound source and try again.';
  if (result.frame_level_spread_db > 60) return 'Variation exceeds the supported range. Try again.';
  return null;
}
export function captureProfile(session, settings, rate) {
  // Session-only random discriminator: never publish track/device IDs or microphone labels.
  // Different phones, processing settings and sample rates must not share a cohort.
  const flag = value => value === true ? '1' : value === false ? '0' : 'u';
  return 'web-v1:' + session + ':' + rate + ':a' + flag(settings.autoGainControl) +
    'e' + flag(settings.echoCancellation) + 'n' + flag(settings.noiseSuppression);
}
export function makeContribution({result, location, profile, id, endedAt}) {
  const problem = measurementProblem(result);
  if (problem) throw new Error(problem);
  if (!location || !Number.isFinite(location.lat) || !Number.isFinite(location.lon) ||
      Math.abs(location.lat) > 90 || Math.abs(location.lon) > 180 ||
      !Number.isFinite(location.timestamp) || Math.abs(endedAt - location.timestamp) > 60000) {
    throw new Error('Location expired. A fresh measurement is needed.');
  }
  if (!/^[a-f0-9-]{36}$/i.test(id) || typeof profile !== 'string' || profile.length > 80 ||
      !profile.startsWith('web-v1:') || !Number.isFinite(endedAt)) throw new Error('Invalid measurement metadata');
  const lat = Number(location.lat.toFixed(3)), lon = Number(location.lon.toFixed(3));
  const round = value => Math.round(value * 10) / 10;
  return {
    id, schema_version: '0.1', area_id: 'cell:' + lat.toFixed(3) + ',' + lon.toFixed(3), lat, lon,
    time_bucket: new Date(Math.floor(endedAt / 300000) * 300000).toISOString(),
    duration_seconds: result.duration_seconds,
    measurement: {kind: 'relative_uncalibrated', rms_dbfs: round(result.rms_dbfs),
      frame_level_spread_db: round(result.frame_level_spread_db), peaks_per_min: round(result.peaks_per_min),
      calibrated: false},
    quality: {capture_profile: profile, clipping_detected: result.clipping_detected},
    source: 'device',
  };
}
