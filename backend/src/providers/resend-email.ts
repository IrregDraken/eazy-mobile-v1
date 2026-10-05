import { AppError } from '../middleware/errors.js';
import type { AppConfig } from '../config/env.js';

export interface EmailMessage {
  to: string;
  subject: string;
  text: string;
  html: string;
}

export interface EmailProvider {
  send(message: EmailMessage): Promise<void>;
}

export class ResendEmailProvider implements EmailProvider {
  constructor(private readonly config: AppConfig) {}

  async send(message: EmailMessage): Promise<void> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10_000);
    let response: Response;
    try {
      response = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          authorization: `Bearer ${this.config.RESEND_API_KEY}`,
          'content-type': 'application/json'
        },
        body: JSON.stringify({
          from: this.config.RESEND_FROM_EMAIL,
          to: [message.to],
          subject: message.subject,
          text: message.text,
          html: message.html
        }),
        signal: controller.signal
      });
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        throw new AppError('SERVICE_UNAVAILABLE', 'Email delivery timed out while contacting Resend.');
      }
      throw new AppError('SERVICE_UNAVAILABLE', `Email delivery request failed: ${error instanceof Error ? error.message : 'unknown network error'}`);
    } finally {
      clearTimeout(timeout);
    }
    if (!response.ok) {
      const body = await response.text().catch(() => '');
      throw new AppError('SERVICE_UNAVAILABLE', `Email delivery failed (${response.status})${body ? `: ${body.slice(0, 240)}` : ''}`);
    }
  }
}

export class UnavailableEmailProvider implements EmailProvider {
  async send(_message: EmailMessage): Promise<void> {
    throw new AppError('SERVICE_UNAVAILABLE', 'Email verification is not configured. Set RESEND_API_KEY and RESEND_FROM_EMAIL in Railway.');
  }
}
