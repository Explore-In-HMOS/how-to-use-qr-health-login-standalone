export class TokenExpiredError extends Error {
  constructor() {
    super('Huawei access_token expired');
  }
}

export interface StepResult {
  steps: number;
  fromMillis: number;
  toMillis: number;
  raw: string;
}
