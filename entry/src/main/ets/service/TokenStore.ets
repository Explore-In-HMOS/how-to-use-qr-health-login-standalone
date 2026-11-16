import { SavedTokens } from '../model/AuthModels';

export interface TokenStore {
  load(): Promise<SavedTokens | null>;
  save(tokens: SavedTokens): Promise<void>;
  clear(): Promise<void>;
}