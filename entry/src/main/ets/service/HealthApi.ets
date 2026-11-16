import { http } from '@kit.NetworkKit';
import { StepResult, TokenExpiredError } from '../model/HealthModels';
import { HealthService } from './HealthService';
import { HEALTH_BASE, CONSENT_BASE } from '../common/config/HuaweiConfig';
import { util } from '@kit.ArkTS';

const POLYMERIZE_PATH: string = '/healthkit/v2/sampleSet:polymerize';
const STEP_DATA_TYPE: string = 'com.huawei.continuous.steps.delta';
const STEP_DAYS_BACK: number = 5;

const CONSENT_PATH: string = '/healthkit/v2/consents';
const API_VERSION: string = '1.0.0';

interface PolymerizeItem {
  dataTypeName: string;
}

interface PolymerizeRequest {
  polymerizeWith: PolymerizeItem[];
  startTime: number;
  endTime: number;
}

export class HealthApi implements HealthService {
  async todaySteps(accessToken: string): Promise<StepResult> {
    const to: number = Date.now();
    const from: number = to - STEP_DAYS_BACK * 24 * 60 * 60 * 1000;

    const item: PolymerizeItem = { dataTypeName: STEP_DATA_TYPE };
    const payload: PolymerizeRequest = {
      polymerizeWith: [item],
      startTime: from,
      endTime: to
    };
    const body: string = JSON.stringify(payload);

    const raw: string = await HealthApi.post(POLYMERIZE_PATH, accessToken, body);
    HealthApi.logPointDays(raw);

    return {
      steps: HealthApi.sumIntegerValues(raw),
      fromMillis: from,
      toMillis: to,
      raw: raw
    };
  }

  async revokeConsent(accessToken: string, clientId: string): Promise<void> {
    const client = http.createHttp();
    try {
      const url: string = `${CONSENT_BASE}${CONSENT_PATH}/${clientId}?deleteData=false`;
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken}`,
        'x-client-id': clientId,
        'x-version': API_VERSION,
        'x-caller-trace-id': HealthApi.traceId()
      };
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.DELETE,
        header: headers,
        connectTimeout: 10000,
        readTimeout: 10000
      };
      const res = await client.request(url, options);
      const text: string = typeof res.result === 'string' ? res.result : JSON.stringify(res.result);
      console.info(`[HealthApi] revoke -> HTTP ${res.responseCode} body=${text}`);

      if (res.responseCode === 401 || text.indexOf('"NSP_STATUS":6') >= 0) {
        throw new TokenExpiredError();
      }
      if (res.responseCode < 200 || res.responseCode >= 300) {
        throw new Error(`Revoke HTTP ${res.responseCode}: ${text}`);
      }
    } finally {
      client.destroy();
    }
  }

  private static logPointDays(raw: string): void {
    const hits: RegExpMatchArray | null = raw.match(/"startTime"\s*:\s*"?\d+/g);
    if (!hits) {
      console.info('[HealthApi] point days: none');
      return;
    }
    const days: Map<string, number> = new Map<string, number>();
    for (let i = 0; i < hits.length; i++) {
      let t: number = Number.parseInt(hits[i].replace(/[^0-9]/g, ''));
      if (t > 1e15) {
        t = Math.floor(t / 1e6);
      }
      const day: string = new Date(t).toISOString().substring(0, 10);
      days.set(day, (days.get(day) ?? 0) + 1);
    }
    let out: string = '';
    days.forEach((n: number, day: string) => {
      out += `${day} x${n}  `;
    });
    console.info(`[HealthApi] point days: ${out}`);
  }

  private static traceId(): string {
  return util.generateRandomUUID(false).replace(/-/g, '');
}

  private static async post(path: string, accessToken: string, body: string): Promise<string> {
    const client = http.createHttp();
    try {
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken}`
      };
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: body,
        connectTimeout: 10000,
        readTimeout: 10000
      };
      const res = await client.request(`${HEALTH_BASE}${path}`, options);

      const text: string = typeof res.result === 'string' ? res.result : JSON.stringify(res.result);
      console.info(`[HealthApi] ${path} -> HTTP ${res.responseCode} body=${text}`);

      if (res.responseCode === 401 || text.indexOf('"NSP_STATUS":6') >= 0) {
        throw new TokenExpiredError();
      }
      if (res.responseCode < 200 || res.responseCode >= 300) {
        throw new Error(`Health Kit HTTP ${res.responseCode}: ${text}`);
      }
      return text;
    } finally {
      client.destroy();
    }
  }

  private static sumIntegerValues(raw: string): number {
    let total: number = 0;
    let matches: number = 0;
    const needle: string = '"integerValue"';
    let i: number = raw.indexOf(needle);
    while (i >= 0) {
      let j: number = i + needle.length;
      while (j < raw.length && (raw.charAt(j) === ':' || raw.charAt(j) === ' ')) {
        j++;
      }
      let digits: string = '';
      while (j < raw.length && raw.charAt(j) >= '0' && raw.charAt(j) <= '9') {
        digits += raw.charAt(j);
        j++;
      }
      if (digits.length > 0) {
        total += Number.parseInt(digits);
        matches++;
      }
      i = raw.indexOf(needle, j);
    }
    console.info(`[HealthApi] integerValue fields found: ${matches}, total: ${total}`);
    return total;
  }
}