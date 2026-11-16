import { image } from '@kit.ImageKit';
import { CLIENT_ID, LANG } from '../common/config/HuaweiConfig';
import { ActivityLog } from '../common/utils/ActivityLog';
import { QrCodeFactory } from '../common/utils/QrCodeFactory';
import { DeviceCode, PollResult, SavedTokens, TokenBody } from '../model/AuthModels';
import { StepResult, TokenExpiredError } from '../model/HealthModels';
import { LoginUiState } from '../model/LoginUiState';
import { DeviceAuthService } from '../service/DeviceAuthService';
import { HealthApi } from '../service/HealthApi';
import { HealthService } from '../service/HealthService';
import { HuaweiAuthApi } from '../service/HuaweiAuthApi';
import { TokenStore } from '../service/TokenStore';

const SUCCESS_MESSAGE_MS: number = 2000;
const MAX_UNKNOWN_POLLS: number = 5;
const MAX_INTERVAL_MS: number = 15000;
const REFRESH_TOKEN_DAYS: number = 180;

const AS_WATCH: string = 'watch';
const AS_PHONE: string = 'phone';
const AS_HUAWEI: string = 'huawei';

export class DeviceLoginViewModel {
  state: LoginUiState = 'IDLE';
  qrPixelMap: image.PixelMap | null = null;
  errorMessage: string = '';
  steps: number | null = null;
  refreshTokenAvailable: boolean = false;
  tokenValidMinutes: number = 0;
  onChange: () => void = () => {};

  private readonly authService: DeviceAuthService;
  private readonly healthService: HealthService;
  private readonly tokenStore: TokenStore;
  private readonly activityLog: ActivityLog = new ActivityLog();
  private deviceCode: string = '';
  private refreshToken: string = '';
  private accessToken: string = '';
  private accessTokenExpiresAt: number = 0;
  private intervalMs: number = 5000;
  private deadline: number = 0;
  private qrStaleAt: number = 0;
  private timerId: number = -1;
  private successTimerId: number = -1;
  private paused: boolean = false;
  private generation: number = 0;
  private unknownPolls: number = 0;
  private qrScannedLogged: boolean = false;

  constructor(tokenStore: TokenStore,
    authService: DeviceAuthService = new HuaweiAuthApi(),
    healthService: HealthService = new HealthApi()) {
    this.tokenStore = tokenStore;
    this.authService = authService;
    this.healthService = healthService;
  }

  get logs(): string[] {
    return this.activityLog.entries;
  }

  async launch(): Promise<void> {
    const saved: SavedTokens | null = await this.tokenStore.load();
    if (saved === null) {
      await this.start();
      return;
    }
    this.generation++;
    this.refreshToken = saved.refreshToken;
    this.accessToken = saved.accessToken;
    this.accessTokenExpiresAt = saved.expiresAt;
    this.refreshTokenAvailable = true;
    this.tokenValidMinutes = Math.max(0, Math.round((saved.expiresAt - Date.now()) / 60000));
    this.log(AS_WATCH, 'saved session restored');
    this.log(AS_WATCH, 'no QR scan needed');
    this.state = 'READY';
    this.onChange();
  }

  async start(): Promise<void> {
    this.generation++;
    const gen = this.generation;

    this.stopTimer();
    this.clearSuccessTimer();
    this.state = 'LOADING';
    this.errorMessage = '';
    this.steps = null;
    this.deviceCode = '';
    this.refreshToken = '';
    this.accessToken = '';
    this.accessTokenExpiresAt = 0;
    this.refreshTokenAvailable = false;
    this.tokenValidMinutes = 0;
    this.unknownPolls = 0;
    this.qrScannedLogged = false;
    this.onChange();

    await this.tokenStore.clear();
    if (gen !== this.generation) {
      return;
    }

    try {
      const dc: DeviceCode = await this.authService.requestDeviceCode();
      if (gen !== this.generation) {
        return;
      }

      this.deviceCode = dc.deviceCode;
      this.intervalMs = dc.interval * 1000;
      this.deadline = Date.now() + dc.expireIn * 1000;
      this.qrStaleAt = Date.now() + dc.scanExpireIn * 1000;

      const qrContent: string = `${dc.verificationUrl}?user_code=${dc.userCode}&lang=${LANG}`;
      this.qrPixelMap = await this.renderQr(qrContent);
      if (gen !== this.generation) {
        return;
      }

      this.log(AS_HUAWEI, 'device_code received');
      this.log(AS_WATCH, `QR drawn · valid ${dc.scanExpireIn}s`);
      this.state = 'WAITING';
      this.onChange();
      this.scheduleNextPoll(gen, this.intervalMs);
    } catch (e) {
      if (gen !== this.generation) {
        return;
      }
      const msg: string = e instanceof Error ? e.message : JSON.stringify(e);
      console.error(`[Login] start failed: ${msg}`);
      this.log(AS_WATCH, `start failed: ${msg}`);
      this.fail('Could not reach Huawei. Try again.');
    }
  }

  async cancelAuth(): Promise<void> {
    this.activityLog.clear();
    this.log(AS_WATCH, 'Signing out...');
    this.onChange();

    await this.revokeConsent();

    this.log(AS_WATCH, 'local tokens cleared');
    await this.start();
  }

  async refreshAccessToken(dueToExpiry: boolean = false): Promise<boolean> {
    if (!this.refreshToken) {
      return false;
    }
    const gen = this.generation;
    const previous: LoginUiState = this.state;

    this.state = 'REFRESHING_TOKEN';
    if (dueToExpiry) {
      this.log(AS_HUAWEI, 'access_token expired');
    }
    this.log(AS_WATCH, 'refreshing directly at Huawei');
    this.onChange();

    try {
      const body: TokenBody = await this.authService.refresh(this.refreshToken);
      if (gen !== this.generation) {
        return false;
      }
      if (!body.accessToken) {
        throw new Error('no access_token');
      }
      this.applyTokens(body);
      this.log(AS_HUAWEI, `renewed via refresh_token · ${this.tokenValidMinutes} min`);
      this.log(AS_WATCH, 'no QR scan needed');

      const back: LoginUiState = (previous === 'READY' || previous === 'STEPS_READY')
        ? previous
        : (this.steps !== null ? 'STEPS_READY' : 'READY');
      this.state = 'TOKEN_REFRESHED';
      this.onChange();
      this.scheduleTransition(gen, 'TOKEN_REFRESHED', back);
      return true;
    } catch (e) {
      if (gen !== this.generation) {
        return false;
      }
      this.log(AS_HUAWEI, 'refresh failed');
      this.expireSession();
      return false;
    }
  }

  resume(): void {
    if (!this.paused) {
      return;
    }
    this.paused = false;
    if (this.state === 'WAITING') {
      this.scheduleNextPoll(this.generation, 0);
    }
  }

  pause(): void {
    this.paused = true;
    this.stopTimer();
  }

  dispose(): void {
    this.generation++;
    this.stopTimer();
    this.clearSuccessTimer();
    this.qrPixelMap?.release();
    this.qrPixelMap = null;
    this.accessToken = '';
    this.refreshToken = '';
    this.accessTokenExpiresAt = 0;
  }

  canFetchSteps(): boolean {
    return this.state === 'READY' || this.state === 'STEPS_READY' ||
      this.state === 'FETCHING_STEPS' || this.state === 'REFRESHING_TOKEN' ||
      this.state === 'TOKEN_REFRESHED';
  }

  isBusy(): boolean {
    return this.state === 'FETCHING_STEPS' || this.state === 'REFRESHING_TOKEN' ||
    this.state === 'TOKEN_REFRESHED';
  }

  canCancel(): boolean {
    return this.accessToken.length > 0;
  }

  accessTokenSecondsLeft(): number {
    if (this.accessTokenExpiresAt === 0) {
      return 0;
    }
    return Math.max(0, Math.round((this.accessTokenExpiresAt - Date.now()) / 1000));
  }

  async fetchStepsNow(): Promise<void> {
    if (this.isBusy()) {
      return;
    }
    await this.fetchSteps(this.generation, true);
  }

  private async fetchSteps(gen: number, allowRefresh: boolean): Promise<void> {
    if (!this.accessToken) {
      this.fail('Sign in first.');
      return;
    }

    if (Date.now() >= this.accessTokenExpiresAt) {
      if (!allowRefresh || !(await this.refreshAccessToken(true))) {
        return;
      }
      if (gen !== this.generation) {
        return;
      }
    }

    this.state = 'FETCHING_STEPS';
    this.log(AS_WATCH, 'calling Health Kit directly');
    this.onChange();

    try {
      const result: StepResult = await this.healthService.todaySteps(this.accessToken);
      if (gen !== this.generation) {
        return;
      }
      this.steps = result.steps;
      this.log(AS_HUAWEI, `returned ${result.steps} steps`);
      this.state = 'STEPS_READY';
      this.onChange();
    } catch (e) {
      if (gen !== this.generation) {
        return;
      }
      if (e instanceof TokenExpiredError) {
        if (allowRefresh && await this.refreshAccessToken(true)) {
          if (gen === this.generation) {
            await this.fetchSteps(gen, false);
          }
          return;
        }
        this.expireSession();
        return;
      }
      this.fail('Could not fetch step data. Try again.');
    }
  }

  private async revokeConsent(): Promise<void> {
    if (!this.accessToken) {
      this.log(AS_WATCH, 'no access_token, nothing to revoke');
      return;
    }
    if (Date.now() >= this.accessTokenExpiresAt && this.refreshToken) {
      try {
        this.applyTokens(await this.authService.refresh(this.refreshToken));
      } catch (e) {
        this.log(AS_HUAWEI, 'refresh before revoke failed');
        return;
      }
    }

    this.log(AS_WATCH, 'revoking consent at Huawei');
    this.onChange();
    try {
      await this.healthService.revokeConsent(this.accessToken, CLIENT_ID);
      this.log(AS_HUAWEI, 'consent deleted, approval needed next time');
    } catch (e) {
      this.log(AS_HUAWEI, 'consent revoke failed');
    }
  }

  private scheduleNextPoll(gen: number, delayMs: number): void {
    this.stopTimer();
    this.timerId = setTimeout(() => this.tick(gen), delayMs);
  }

  private async tick(gen: number): Promise<void> {
    if (gen !== this.generation || this.paused) {
      return;
    }

    if (Date.now() > this.deadline) {
      this.fail('Session expired. Try again.');
      return;
    }

    if (this.state === 'WAITING' && Date.now() > this.qrStaleAt) {
      this.log(AS_WATCH, 'QR expired, needs refresh');
      this.state = 'QR_STALE';
      this.onChange();
      return;
    }

    try {
      const r: PollResult = await this.authService.pollToken(this.deviceCode);
      if (gen !== this.generation) {
        return;
      }

      if (r.state === 'SUCCESS') {
        this.stopTimer();
        this.deviceCode = '';
        this.applyTokens(r.body);
        const granted: string = r.body.scope ?? '';
        console.info(`[Login] granted scope: ${granted}`);
        this.log(AS_PHONE, 'Permissions approved');
        this.log(AS_HUAWEI, granted.indexOf('step.read') >= 0 ? 'step.read granted' : 'step.read NOT granted');
        this.log(AS_HUAWEI, `access_token received · ${this.tokenValidMinutes} min`);
        if (this.refreshTokenAvailable) {
          this.log(AS_WATCH, `refresh_token stored on watch · ${REFRESH_TOKEN_DAYS} days`);
        }
        this.state = 'SUCCESS';
        this.onChange();
        this.scheduleTransition(gen, 'SUCCESS', 'READY');
        return;
      }

      if (r.state === 'EXPIRED') {
        this.fail('Authorization not completed. Try again.');
        return;
      }

      if (r.state === 'UNKNOWN') {
        this.unknownPolls++;
        if (this.unknownPolls >= MAX_UNKNOWN_POLLS) {
          this.fail('Authorization not completed. Try again.');
          return;
        }
      } else {
        this.unknownPolls = 0;
      }

      if (r.state === 'PENDING_SCANNED' && !this.qrScannedLogged) {
        this.qrScannedLogged = true;
        this.log(AS_PHONE, 'QR scanned, consent screen open');
        this.onChange();
      }

      if (r.state === 'SLOW_DOWN') {
        this.intervalMs = Math.min(this.intervalMs + 2000, MAX_INTERVAL_MS);
      }

      this.scheduleNextPoll(gen, this.intervalMs);
    } catch (e) {
      if (gen !== this.generation) {
        return;
      }
      this.scheduleNextPoll(gen, Math.min(this.intervalMs * 2, MAX_INTERVAL_MS));
    }
  }

  private applyTokens(body: TokenBody): void {
    this.accessToken = body.accessToken ?? '';
    const ttl: number = body.expiresIn ?? 3600;
    this.accessTokenExpiresAt = Date.now() + ttl * 1000;
    this.tokenValidMinutes = Math.round(ttl / 60);
    if (body.refreshToken) {
      this.refreshToken = body.refreshToken;
    }
    this.refreshTokenAvailable = this.refreshToken.length > 0;
    this.persistTokens();
  }

  private persistTokens(): void {
    const tokens: SavedTokens = {
      accessToken: this.accessToken,
      refreshToken: this.refreshToken,
      expiresAt: this.accessTokenExpiresAt
    };
    this.tokenStore.save(tokens);
  }

  private scheduleTransition(gen: number, from: LoginUiState, to: LoginUiState): void {
    this.clearSuccessTimer();
    this.successTimerId = setTimeout(() => {
      if (gen !== this.generation || this.state !== from) {
        return;
      }
      this.state = to;
      this.onChange();
    }, SUCCESS_MESSAGE_MS);
  }

  private clearSuccessTimer(): void {
    if (this.successTimerId !== -1) {
      clearTimeout(this.successTimerId);
      this.successTimerId = -1;
    }
  }

  private expireSession(): void {
    this.accessToken = '';
    this.refreshToken = '';
    this.accessTokenExpiresAt = 0;
    this.refreshTokenAvailable = false;
    this.steps = null;
    this.tokenStore.clear();
    this.fail('Session expired. Sign in again.');
  }

  private async renderQr(content: string): Promise<image.PixelMap> {
    this.qrPixelMap?.release();
    return QrCodeFactory.create(content);
  }

  private fail(message: string): void {
    this.stopTimer();
    this.clearSuccessTimer();
    this.state = 'FAILED';
    this.errorMessage = message;
    this.log(AS_WATCH, `ERROR: ${message}`);
    this.onChange();
  }

  private stopTimer(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  private log(actor: string, line: string): void {
    this.activityLog.add(actor, line);
  }
}