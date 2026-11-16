export interface DeviceCode {
  deviceCode: string;
  userCode: string;
  verificationUrl: string;
  interval: number;
  expireIn: number;
  scanExpireIn: number;
}

export interface TokenBody {
  accessToken?: string;
  refreshToken?: string;
  idToken?: string;
  openId?: string;
  scope?: string;
  expiresIn?: number;
  error?: number | string;
  subError?: number | string;
  errorDescription?: string;
}

export type PollState = 'PENDING' | 'PENDING_SCANNED' | 'SUCCESS' | 'SLOW_DOWN' | 'EXPIRED' | 'UNKNOWN';

export interface PollResult {
  state: PollState;
  body: TokenBody;
}

export interface SavedTokens{
  accessToken:string;
  refreshToken:string;
  expiresAt:number;
}
