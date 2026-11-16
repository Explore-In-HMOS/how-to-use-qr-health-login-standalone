import { DeviceCode, PollResult, TokenBody } from '../model/AuthModels';

export interface DeviceAuthService {
  requestDeviceCode(): Promise<DeviceCode>;
  pollToken(deviceCode: string): Promise<PollResult>;
  refresh(refreshToken: string): Promise<TokenBody>;
}
