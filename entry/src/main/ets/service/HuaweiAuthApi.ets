import { http } from '@kit.NetworkKit';
import { CLIENT_ID, CLIENT_SECRET, SCOPE, OAUTH_BASE } from '../common/config/HuaweiConfig';
import { DeviceCode, PollResult, PollState, TokenBody } from '../model/AuthModels';
import { DeviceAuthService } from './DeviceAuthService';

const KEY_DEVICE_CODE: string = 'device_code';
const KEY_USER_CODE: string = 'user_code';
const KEY_VERIFICATION_URL: string = 'verification_url';
const KEY_INTERVAL: string = 'interval';
const KEY_EXPIRE_IN: string = 'expire_in';
const KEY_SCAN_EXPIRE_IN: string = 'scan_expire_in';

const KEY_ACCESS_TOKEN: string = 'access_token';
const KEY_REFRESH_TOKEN: string = 'refresh_token';
const KEY_ID_TOKEN: string = 'id_token';
const KEY_OPEN_ID: string = 'open_id';
const KEY_SCOPE: string = 'scope';
const KEY_EXPIRES_IN: string = 'expires_in';
const KEY_ERROR: string = 'error';
const KEY_SUB_ERROR: string = 'sub_error';
const KEY_ERROR_DESCRIPTION: string = 'error_description';

export class HuaweiAuthApi implements DeviceAuthService {
  async requestDeviceCode(): Promise<DeviceCode> {
    const text: string = await HuaweiAuthApi.postForm('/oauth2/v3/device/code', [
      ['client_id', CLIENT_ID],
      ['scope', SCOPE]
    ]);
    const obj = JSON.parse(text) as Record<string, string | number>;
    const dc: DeviceCode = {
    deviceCode: obj[KEY_DEVICE_CODE] as string,
    userCode: obj[KEY_USER_CODE] as string,
    verificationUrl: obj[KEY_VERIFICATION_URL] as string,
    interval: obj[KEY_INTERVAL] as number,
    expireIn: obj[KEY_EXPIRE_IN] as number,
    scanExpireIn: obj[KEY_SCAN_EXPIRE_IN] as number
};
    if (!dc.deviceCode) {
      throw new Error(`device_code missing: ${text}`);
    }
    return dc;
  }

  async pollToken(deviceCode: string): Promise<PollResult> {
    const text: string = await HuaweiAuthApi.postForm('/oauth2/v3/token', [
      ['grant_type', 'device_code'],
      ['code', deviceCode],
      ['client_id', CLIENT_ID],
      ['client_secret', CLIENT_SECRET]
    ]);
    let body: TokenBody;
    try {
      body = HuaweiAuthApi.parseTokenBody(text);
    } catch (e) {
      const empty: TokenBody = {};
      return { state: 'UNKNOWN', body: empty };
    }
    return { state: HuaweiAuthApi.classify(body), body: body };
  }

  async refresh(refreshToken: string): Promise<TokenBody> {
    const text: string = await HuaweiAuthApi.postForm('/oauth2/v3/token', [
      ['grant_type', 'refresh_token'],
      ['client_id', CLIENT_ID],
      ['client_secret', CLIENT_SECRET],
      ['refresh_token', refreshToken]
    ]);
    return HuaweiAuthApi.parseTokenBody(text);
  }

  private static parseTokenBody(text: string): TokenBody {
    const obj = JSON.parse(text) as Record<string, string | number>;
    return {
     accessToken: obj[KEY_ACCESS_TOKEN] as string | undefined,
     refreshToken: obj[KEY_REFRESH_TOKEN] as string | undefined,
     idToken: obj[KEY_ID_TOKEN] as string | undefined,
     openId: obj[KEY_OPEN_ID] as string | undefined,
     scope: obj[KEY_SCOPE] as string | undefined,
     expiresIn: obj[KEY_EXPIRES_IN] as number | undefined,
     error: obj[KEY_ERROR],
     subError: obj[KEY_SUB_ERROR],
     errorDescription: obj[KEY_ERROR_DESCRIPTION] as string | undefined
};
  }

  private static classify(body: TokenBody): PollState {
    if (body.accessToken) {
      return 'SUCCESS';
    }
    const err: string = body.error !== undefined ? String(body.error) : '';
    const sub: string = body.subError !== undefined ? String(body.subError) : '';
    if (err === '1101') {
      return sub === '20412' ? 'PENDING_SCANNED' : 'PENDING';
    }
    if (err === 'authorization_pending') {
      return 'PENDING';
    }
    if (err === 'slow_down') {
      return 'SLOW_DOWN';
    }
    if (err === 'expired_token') {
      return 'EXPIRED';
    }
    return 'UNKNOWN';
  }

  private static formEncode(value: string): string {
    return encodeURIComponent(value).split('%20').join('+');
  }

  private static async postForm(path: string, fields: string[][]): Promise<string> {
    const client = http.createHttp();
    try {
      const body: string = fields
        .map((f: string[]) => `${HuaweiAuthApi.formEncode(f[0])}=${HuaweiAuthApi.formEncode(f[1])}`)
        .join('&');
      const headers: Record<string, string> = {
        'Content-Type': 'application/x-www-form-urlencoded'
      };
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: body,
        connectTimeout: 10000,
        readTimeout: 10000
      };
      const res = await client.request(`${OAUTH_BASE}${path}`, options);
      const text: string = typeof res.result === 'string' ? res.result : JSON.stringify(res.result);
      const shown: string = text.indexOf('access_token') >= 0 ? '{tokens}' : text;
      console.info(`[HuaweiAuthApi] ${path} -> HTTP ${res.responseCode} body=${shown}`);
      return text;
    } finally {
      client.destroy();
    }
  }
}
