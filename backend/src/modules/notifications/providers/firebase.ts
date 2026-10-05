import { cert, getApps, initializeApp, type App } from 'firebase-admin/app';
import { getMessaging as getAdminMessaging, type Messaging } from 'firebase-admin/messaging';
import type { Pool } from 'pg';
import type { NotificationProvider } from '../../../providers/interfaces.js';
import type { AppConfig } from '../../../config/env.js';

export class FirebaseNotificationProvider implements NotificationProvider {
  private readonly messaging: Messaging;
  constructor(private readonly pool: Pool, config: AppConfig, app?: App) {
    const firebaseApp = app ?? (getApps()[0] ?? initializeApp({
      credential: cert({ projectId: config.FIREBASE_PROJECT_ID!, clientEmail: config.FIREBASE_CLIENT_EMAIL!, privateKey: config.FIREBASE_PRIVATE_KEY!.replace(/\\n/g, '\n') })
    }, 'eazy-messaging'));
    if (!firebaseApp) throw new Error('Firebase Admin is not initialized');
    this.messaging = getAdminMessaging(firebaseApp);
  }

  async notify(input: { userId: string; title: string; body: string }): Promise<void> {
    const devices = await this.pool.query<{ id: string; device_token: string }>(
      'SELECT id, device_token FROM push_devices WHERE user_id = $1 AND is_active = true', [input.userId]
    );
    if (!devices.rows.length) return;
    const result = await this.messaging.sendEachForMulticast({
      tokens: devices.rows.map(device => device.device_token),
      notification: { title: input.title, body: input.body }
    });
    const stale = result.responses.flatMap((response, index) => {
      const code = response.error?.code;
      return code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token'
        ? [devices.rows[index]!.id] : [];
    });
    if (stale.length) await this.pool.query('UPDATE push_devices SET is_active = false, revoked_at = now(), updated_at = now() WHERE id = ANY($1::uuid[])', [stale]);
    if (result.failureCount > 0 && result.successCount === 0) throw new Error('Firebase push delivery failed');
  }
}
