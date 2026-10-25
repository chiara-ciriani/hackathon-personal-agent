import assert from 'node:assert/strict';
import { test } from '@e2e-dev/web';
import { expect } from 'e2e';

type ToolData = {phone_session_id: string; connect_url: string; request_id: string;
  job: {walk: {sample_count: number; analysis: {variation_db: number}}; contribution_result?: unknown}};
type PhoneData = {status: string; request_id: string; mode: string;
  recommendation: {destination: {kind: string; request_id: string}}};
const origin = process.env.APP_URL ?? 'http://localhost:5180';
const server = process.env.QC_E2E_SERVER ?? 'http://127.0.0.1:8810';
// These tests deliberately refuse deployed services and real accounts.
for (const value of [origin, server]) {
  if (!['127.0.0.1', 'localhost'].includes(new URL(value).hostname)) throw new Error('Use isolated local servers for phone fixtures.');
}
async function tool(name: string, args: object = {}) {
  const response = await fetch(server + '/mcp', {method: 'POST', headers: {
    'Content-Type': 'application/json', Accept: 'application/json, text/event-stream',
    Authorization: 'Bearer local-e2e-owner-only',
  }, body: JSON.stringify({jsonrpc: '2.0', id: 1, method: 'tools/call', params: {name, arguments: args}})});
  assert.equal(response.status, 200);
  const body = await response.json() as {error?: unknown; result: {isError?: boolean; structuredContent: ToolData}};
  assert.ok(!body.error && !body.result?.isError, JSON.stringify(body));
  return body.result.structuredContent;
}
async function phone(token: string, action: string, body: object = {}) {
  return fetch(origin + '/api/phone/' + action, {method: 'POST', headers: {
    'Content-Type': 'application/json', Authorization: 'Bearer ' + token,
  }, body: JSON.stringify(body)});
}

test('unlinked page explains the connection without claiming sensors are connected', async ({app, browser}) => {
  await app.open('/measure');
  await expect(browser.locator('h1')).toHaveText('Connect your phone.');
  await expect(browser.locator('.pm-status')).toContainText('Not linked');
  await expect(browser.locator('.pm-dial')).toContainText('Microphone off');
});

test('agent link → native relay → sound analysis → measured advice → disconnect (synthetic sensor fixture)', async ({app, browser}) => {
  const link = await tool('connect_phone');
  const token = new URLSearchParams(new URL(link.connect_url).hash.slice(1)).get('pair')!;
  try {
    await app.open('/measure#pair=' + token);
    await expect(browser.locator('.pm-native a')).toHaveAttribute('href', 'quietcompass-walk://connect#pair=' + token);
    await expect(browser.locator('.pm-status')).toContainText('Ready to connect');
    await expect(browser.locator('button').filter({hasText: 'Connect browser'})).toBeDisabled();
    assert.equal((await phone(token, 'native-consent', {microphone_consent: true, spatial_consent: true})).status, 200);
    const requested = await tool('request_phone_measurement', {phone_session_id: link.phone_session_id, mode: 'walk', duration_seconds: 30});
    const command = await (await phone(token, 'native-poll')).json() as PhoneData;
    assert.equal(command.request_id, requested.request_id);
    assert.equal(command.mode, 'walk');
    const started = new Date().toISOString();
    await new Promise(resolve => setTimeout(resolve, 30_100));
    const result = {request_id: requested.request_id, walk: {
      started_at: started, capture_profile: 'ios-walk-v1:e2e-fixture:48000:1', clipping_detected: false,
      samples: Array.from({length: 14}, (_, index) => ({t: (index+1)*2, x: (index+1)*.6, z: 0, level_dbfs: -55+(index+1)*1.5, tracking: 'normal'})),
    }};
    const receipt = await phone(token, 'native-result', result);
    assert.equal(receipt.status, 200);
    assert.equal((await receipt.json() as PhoneData).status, 'complete');
    const analysis = await tool('phone_measurement_status', {phone_session_id: link.phone_session_id});
    assert.equal(analysis.job.walk.sample_count, 14);
    assert.ok(analysis.job.walk.analysis.variation_db > 10);
    assert.ok(!analysis.job.contribution_result, 'Private room maps must not grant shared access');
    await tool('send_phone_recommendation', {phone_session_id: link.phone_session_id, action: 'move', spot_index: 0, message: 'A measured corner was quieter. Check the path before moving.'});
    const advice = await (await phone(token, 'native-poll')).json() as PhoneData;
    assert.equal(advice.recommendation.destination.kind, 'room');
    assert.equal(advice.recommendation.destination.request_id, requested.request_id);
  } finally {
    await phone(token, 'disconnect');
  }
  assert.equal((await phone(token, 'native-poll')).status, 410);
});
