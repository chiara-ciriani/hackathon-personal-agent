// Vercel only: `cloudflare:workers` does not exist there, so bindings fall back to process.env.
// next.config.ts aliases the module to this file when VERCEL is set; the Cloudflare build is untouched.
export const env = process.env as Record<string, string | undefined>;
