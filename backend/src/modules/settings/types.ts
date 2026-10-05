export type ThemePreference = 'system' | 'light' | 'dark';

export interface UserSettings {
  languageCode: string;
  theme: ThemePreference;
  notifications: {
    follows: boolean;
    likes: boolean;
    comments: boolean;
  };
}

export interface UserSettingsRow {
  language_code: string;
  theme: ThemePreference;
  notify_follows: boolean;
  notify_likes: boolean;
  notify_comments: boolean;
}

export function projectUserSettings(row: UserSettingsRow): UserSettings {
  return {
    languageCode: row.language_code,
    theme: row.theme,
    notifications: {
      follows: row.notify_follows,
      likes: row.notify_likes,
      comments: row.notify_comments
    }
  };
}

export const DEFAULT_USER_SETTINGS: UserSettings = {
  languageCode: 'en',
  theme: 'system',
  notifications: { follows: true, likes: true, comments: true }
};
