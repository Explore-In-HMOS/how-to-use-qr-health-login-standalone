import { StepResult } from '../model/HealthModels';

export interface HealthService {
  todaySteps(accessToken: string): Promise<StepResult>;
  revokeConsent(accessToken: string, clientId: string): Promise<void>;
}
