import type { E2EConfig } from 'e2e';
import { web } from '@e2e-dev/web';

export default {
  workers: 1,
  retries: 0,
  timeout: 90_000,
  targets: [{
    engine: web({viewport: {width: 390, height: 844}}),
    app: {url: process.env.APP_URL ?? 'http://localhost:5180'},
  }],
} satisfies E2EConfig;
