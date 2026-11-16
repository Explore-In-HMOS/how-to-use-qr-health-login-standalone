export type LoginUiState =
  | 'IDLE'
  | 'LOADING'
  | 'WAITING'
  | 'QR_STALE'
  | 'SUCCESS'
  | 'READY'
  | 'FETCHING_STEPS'
  | 'STEPS_READY'
  | 'REFRESHING_TOKEN'
  | 'TOKEN_REFRESHED'
  | 'FAILED';
