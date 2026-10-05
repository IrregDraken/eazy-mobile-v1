import { cert, getApps, initializeApp, type App } from 'firebase-admin/app';
import { getAuth, type Auth, type DecodedIdToken } from 'firebase-admin/auth';
import type { AppConfig } from '../config/env.js';
import { AppError } from '../middleware/errors.js';
import type { AuthContext, Authenticator } from '../middleware/auth.js';

export interface FirebaseIdentity {
  firebaseUid: string;
  claims: Record<string, unknown>;
}

export class FirebaseAuthProvider implements Authenticator {
  private readonly auth: Auth;

  constructor(config: AppConfig, app?: App) {
    if (!config.FIREBASE_PROJECT_ID || !config.FIREBASE_CLIENT_EMAIL || !config.FIREBASE_PRIVATE_KEY) {
      throw new AppError('SERVICE_UNAVAILABLE', 'Firebase authentication is not configured');
    }
    const firebaseApp = app ?? (getApps()[0] ?? initializeApp({
      credential: cert({
        projectId: config.FIREBASE_PROJECT_ID,
        clientEmail: config.FIREBASE_CLIENT_EMAIL,
        privateKey: config.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n')
      })
    }));
    this.auth = getAuth(firebaseApp);
    this.checkRevoked = config.FIREBASE_CHECK_REVOKED;
  }

  private readonly checkRevoked: boolean;

  async verifyIdentity(token: string): Promise<FirebaseIdentity> {
    try {
      const decoded = await this.auth.verifyIdToken(token, this.checkRevoked);
      return { firebaseUid: decoded.uid, claims: normalizedClaims(decoded) };
    } catch {
      throw new AppError('UNAUTHORIZED', 'Invalid authentication');
    }
  }

  async authenticate(token: string): Promise<AuthContext> {
    const identity = await this.verifyIdentity(token);
    return { userId: identity.firebaseUid, provider: 'firebase', claims: identity.claims };
  }

  /** Permanently removes the Firebase user. A user that is already gone counts as removed. */
  async deleteIdentity(firebaseUid: string): Promise<void> {
    try {
      await this.auth.deleteUser(firebaseUid);
    } catch (error) {
      if ((error as { code?: string }).code === 'auth/user-not-found') return;
      throw new AppError('SERVICE_UNAVAILABLE', 'Unable to remove the sign-in identity right now. Please try again.');
    }
  }

  async markEmailVerified(firebaseUid: string): Promise<void> {
    try {
      await this.auth.updateUser(firebaseUid, { emailVerified: true });
    } catch {
      throw new AppError('SERVICE_UNAVAILABLE', 'Unable to mark Firebase email as verified');
    }
  }
}

function normalizedClaims(decoded: DecodedIdToken): Record<string, unknown> {
  const { uid, iss, aud, sub, iat, exp, auth_time, firebase, ...customClaims } = decoded;
  return { uid, iss, aud, sub, iat, exp, auth_time, firebase, ...customClaims };
}
