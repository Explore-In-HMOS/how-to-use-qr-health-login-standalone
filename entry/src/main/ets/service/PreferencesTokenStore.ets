import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { SavedTokens } from '../model/AuthModels';
import { TokenStore } from './TokenStore';

const STORE_NAME: string = 'qr_health_tokens';
const KEY_ACCESS_TOKEN: string = 'access_token';
const KEY_REFRESH_TOKEN: string = 'refresh_token';
const KEY_EXPIRES_AT: string = 'expires_at';

export class PreferencesTokenStore implements TokenStore {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  async load(): Promise<SavedTokens | null> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, STORE_NAME);
      const accessToken: string = await store.get(KEY_ACCESS_TOKEN, '') as string;
      const refreshToken: string = await store.get(KEY_REFRESH_TOKEN, '') as string;
      const expiresAt: number = await store.get(KEY_EXPIRES_AT, 0) as number;
      if (!accessToken || !refreshToken) {
        return null;
      }
      const tokens: SavedTokens = {
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: expiresAt
      };
      return tokens;
    } catch (e) {
      console.error(`[TokenStore] load failed: ${JSON.stringify(e)}`);
      return null;
    }
  }

  async save(tokens: SavedTokens): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, STORE_NAME);
      await store.put(KEY_ACCESS_TOKEN, tokens.accessToken);
      await store.put(KEY_REFRESH_TOKEN, tokens.refreshToken);
      await store.put(KEY_EXPIRES_AT, tokens.expiresAt);
      await store.flush();
    } catch (e) {
      console.error(`[TokenStore] save failed: ${JSON.stringify(e)}`);
    }
  }

  async clear(): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, STORE_NAME);
      await store.clear();
      await store.flush();
    } catch (e) {
      console.error(`[TokenStore] clear failed: ${JSON.stringify(e)}`);
    }
  }
}