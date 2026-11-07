// Sends visible notifications through APNs with token-based auth (a .p8 key, ES256 provider token).

export type ApnsEnvironment = 'production' | 'sandbox';

export interface ApnsConfig {
  /** The .p8 key's PEM text. A secret, set with `wrangler secret put APNS_KEY`, never committed. */
  key: string;
  keyId: string;
  teamId: string;
  /** The app's bundle id. */
  topic: string;
}

export interface Push {
  token: string;
  environment: ApnsEnvironment;
  title: string;
  body: string;
  /** Epoch milliseconds after which APNs drops the notification instead of delivering it late. */
  expiration: number;
  /** Custom keys beside `aps`: trip id and service date for the deep link (rule 10). */
  data: Record<string, string>;
}

/**
 * - sent: APNs accepted it.
 * - unregistered: 410, the app is no longer on the device, so its installation is removed (rule 9).
 * - badToken: the token is not valid for this app or environment; it is cleared until the app registers again.
 * - retry: a temporary failure (network, 429, 5xx, expired provider token); the next cycle tries again.
 * - failed: rejected for another reason, logged and not retried.
 */
export type PushResult = 'sent' | 'unregistered' | 'badToken' | 'retry' | 'failed';

const HOSTS: Record<ApnsEnvironment, string> = {
  production: 'https://api.push.apple.com',
  sandbox: 'https://api.sandbox.push.apple.com',
};

/** Apple accepts a provider token for an hour and asks for a new one no more than every 20 min. */
const TOKEN_LIFETIME_MS = 50 * 60_000;

function base64url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToDer(pem: string): Uint8Array {
  const base64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
}

export class ApnsClient {
  config: ApnsConfig;
  fetch: typeof fetch;
  private token: { value: string; issuedAt: number } | null = null;

  constructor(config: ApnsConfig, fetchImpl: typeof fetch = (input, init) => fetch(input, init)) {
    this.config = config;
    this.fetch = fetchImpl;
  }

  /** The ES256 provider token (JWT), reused for 50 min. */
  async providerToken(now: number): Promise<string> {
    if (this.token && now - this.token.issuedAt < TOKEN_LIFETIME_MS) return this.token.value;
    const encode = (value: object) => base64url(new TextEncoder().encode(JSON.stringify(value)));
    const input = `${encode({ alg: 'ES256', kid: this.config.keyId })}.${encode({ iss: this.config.teamId, iat: Math.floor(now / 1000) })}`;
    const key = await crypto.subtle.importKey(
      'pkcs8',
      pemToDer(this.config.key),
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['sign'],
    );
    // WebCrypto signs ECDSA in the raw r || s form that JWS ES256 expects.
    const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(input));
    const value = `${input}.${base64url(new Uint8Array(signature))}`;
    this.token = { value, issuedAt: now };
    return value;
  }

  async send(push: Push, now: number): Promise<PushResult> {
    let response: Response;
    try {
      response = await this.fetch(`${HOSTS[push.environment]}/3/device/${push.token}`, {
        method: 'POST',
        headers: {
          authorization: `bearer ${await this.providerToken(now)}`,
          'apns-topic': this.config.topic,
          'apns-push-type': 'alert',
          'apns-priority': '10',
          'apns-expiration': String(Math.floor(push.expiration / 1000)),
        },
        // Default sound and interruption level; no critical or time-sensitive alerts in v1.
        body: JSON.stringify({ aps: { alert: { title: push.title, body: push.body }, sound: 'default' }, ...push.data }),
      });
    } catch (error) {
      console.warn('APNs request failed', error);
      return 'retry';
    }
    if (response.status === 200) return 'sent';
    const reason = await response
      .json()
      .then((body) => (body as { reason?: string }).reason ?? '')
      .catch(() => '');
    console.warn(`APNs ${response.status} ${reason}`);
    if (response.status === 410) return 'unregistered';
    if (reason === 'BadDeviceToken' || reason === 'DeviceTokenNotForTopic') return 'badToken';
    if (reason === 'ExpiredProviderToken') {
      this.token = null;
      return 'retry';
    }
    if (response.status === 429 || response.status >= 500) return 'retry';
    return 'failed';
  }
}
