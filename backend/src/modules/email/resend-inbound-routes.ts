import { createHmac, timingSafeEqual } from 'node:crypto';
import express, { type Request, type Router } from 'express';
import type { AppConfig } from '../../config/env.js';
import type { Logger } from 'pino';

const SUPPORT_INBOX = 'official.eazy.ind@gmail.com';
const ROUTABLE_RECIPIENTS = new Set([
  'support@eazy.name.ng',
  'help@eazy.name.ng',
  'privacy@eazy.name.ng',
  'legal@eazy.name.ng'
]);

interface ResendInboundEvent {
  type?: string;
  data?: { email_id?: string; to?: string[] };
}
interface InboundAttachment {
  filename?: string;
  content_type?: string;
  download_url?: string;
}
interface InboundEmail {
  from?: string;
  to?: string[];
  cc?: string[];
  subject?: string;
  text?: string | null;
  html?: string | null;
  created_at?: string;
  attachments?: InboundAttachment[];
}
interface OutboundAttachment {
  filename: string;
  content: string;
  content_type?: string;
}

export function createResendInboundRouter(config: AppConfig, logger: Logger): Router {
  const router = express.Router();
  router.post('/resend', async (request, response) => {
    if (!config.RESEND_WEBHOOK_SECRET || !config.RESEND_API_KEY) {
      return response.status(503).json({ error: 'Inbound email processing is not configured' });
    }
    const rawBody = request.rawBody;
    if (!rawBody || !verifyWebhookSignature(request, rawBody, config.RESEND_WEBHOOK_SECRET)) {
      return response.status(401).json({ error: 'Invalid webhook signature' });
    }

    let event: ResendInboundEvent;
    try {
      event = JSON.parse(rawBody) as ResendInboundEvent;
    } catch {
      return response.status(400).json({ error: 'Invalid JSON payload' });
    }
    if (event.type !== 'email.received') return response.status(200).json({ received: true, ignored: true });
    const emailId = event.data?.email_id;
    if (!emailId) return response.status(400).json({ error: 'Missing inbound email ID' });

    const recipients = (event.data?.to ?? []).map(value => value.toLowerCase().trim());
    const routedRecipient = recipients.find(value => ROUTABLE_RECIPIENTS.has(value));
    if (!routedRecipient) return response.status(200).json({ received: true, ignored: true });

    try {
      const inboundResponse = await fetch(`https://api.resend.com/emails/receiving/${encodeURIComponent(emailId)}`, {
        headers: { authorization: `Bearer ${config.RESEND_API_KEY}` },
        signal: AbortSignal.timeout(15_000)
      });
      if (!inboundResponse.ok) throw new Error(`Resend inbound fetch failed with status ${inboundResponse.status}`);
      const email = await inboundResponse.json() as InboundEmail;
      if (!email.from) throw new Error('Inbound email did not include a sender');

      const attachments: OutboundAttachment[] = [];
      for (const attachment of email.attachments ?? []) {
        if (!attachment.download_url) continue;
        const fileResponse = await fetch(attachment.download_url, { signal: AbortSignal.timeout(15_000) });
        if (!fileResponse.ok) throw new Error('Could not retrieve an inbound email attachment');
        const bytes = Buffer.from(await fileResponse.arrayBuffer());
        if (bytes.byteLength > 10 * 1024 * 1024) throw new Error('Inbound attachment exceeds the 10 MB forwarding limit');
        attachments.push({
          filename: safeFilename(attachment.filename ?? 'attachment'),
          content: bytes.toString('base64'),
          ...(attachment.content_type ? { content_type: attachment.content_type } : {})
        });
      }

      const subject = (email.subject ?? '(no subject)').slice(0, 240);
      const text = [
        'EAZY SUPPORT INBOX',
        `Received at: ${email.created_at ?? new Date().toISOString()}`,
        `Original recipient: ${routedRecipient}`,
        `From: ${email.from}`,
        `Subject: ${subject}`,
        '',
        email.text ?? '(No plain-text body. See the original HTML content below.)',
        ...(email.html ? ['', 'Original HTML body is included as a separate section in this message.'] : [])
      ].join('\n');
      const safeFrom = escapeHtml(email.from);
      const safeRecipient = escapeHtml(routedRecipient);
      const safeSubject = escapeHtml(subject);
      const safeText = escapeHtml(email.text ?? '(No plain-text body provided.)');
      const html = `<!doctype html><html><body style="margin:0;background:#f2f5f1;font-family:Arial,sans-serif;color:#15251d;padding:24px"><div style="max-width:680px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;border:1px solid #dce5dd"><div style="background:#071b12;padding:24px 28px"><div style="color:#b8f34a;font-size:13px;font-weight:700;letter-spacing:3px">EAZY</div><h1 style="color:#fff;font-size:22px;margin:12px 0 0">New support email</h1></div><div style="padding:26px 28px"><div style="font-size:13px;color:#52645a;line-height:1.8"><b>From:</b> ${safeFrom}<br><b>To:</b> ${safeRecipient}<br><b>Subject:</b> ${safeSubject}<br><b>Received:</b> ${escapeHtml(email.created_at ?? new Date().toISOString())}</div><hr style="border:0;border-top:1px solid #e3e9e3;margin:22px 0"><div style="font-size:15px;line-height:1.7;white-space:pre-wrap;overflow-wrap:anywhere">${safeText}</div>${email.html ? `<details style="margin-top:22px"><summary style="cursor:pointer;color:#315d3d;font-weight:700">View original HTML email</summary><div style="margin-top:12px;padding:14px;background:#f6f8f5;border-radius:10px;overflow-wrap:anywhere">The original HTML is available in the received message stored by Resend.</div></details>` : ''}<p style="margin:28px 0 0;font-size:12px;color:#68776d">Reply to this message in Gmail to respond to the sender, provided your mail client keeps the original sender as Reply-To.</p></div></div></body></html>`;

      const forwardResponse = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { authorization: `Bearer ${config.RESEND_API_KEY}`, 'content-type': 'application/json' },
        body: JSON.stringify({
          from: config.RESEND_FROM_EMAIL,
          to: [SUPPORT_INBOX],
          reply_to: [email.from],
          subject: `[Eazy ${routedRecipient.split('@')[0]}] ${subject}`,
          text,
          html,
          ...(attachments.length ? { attachments } : {})
        }),
        signal: AbortSignal.timeout(15_000)
      });
      if (!forwardResponse.ok) {
        const errorText = await forwardResponse.text().catch(() => '');
        throw new Error(`Resend forward failed with status ${forwardResponse.status}: ${errorText.slice(0, 160)}`);
      }
      logger.info({ event: 'email.inbound.forwarded', recipient: routedRecipient, attachmentCount: attachments.length }, 'Inbound support email forwarded');
      return response.status(200).json({ received: true, forwarded: true });
    } catch (error) {
      logger.error({ event: 'email.inbound.forward_failed', recipient: routedRecipient, error: error instanceof Error ? error.message : 'unknown' }, 'Inbound support email forwarding failed');
      return response.status(500).json({ error: 'Unable to forward inbound email' });
    }
  });
  return router;
}

function verifyWebhookSignature(request: Request, rawBody: string, secret: string): boolean {
  const id = request.header('svix-id');
  const timestamp = request.header('svix-timestamp');
  const signatures = request.header('svix-signature');
  if (!id || !timestamp || !signatures || !/^\d+$/.test(timestamp)) return false;
  const timestampMs = Number(timestamp) * 1000;
  if (!Number.isFinite(timestampMs) || Math.abs(Date.now() - timestampMs) > 5 * 60 * 1000) return false;
  const encodedSecret = secret.startsWith('whsec_') ? secret.slice(6) : secret;
  let key: Buffer;
  try { key = Buffer.from(encodedSecret, 'base64'); } catch { return false; }
  if (!key.length) return false;
  const expected = createHmac('sha256', key).update(`${id}.${timestamp}.${rawBody}`).digest('base64');
  return signatures.split(' ').some(value => {
    const parts = value.split(',');
    if (parts.length !== 2 || parts[0] !== 'v1') return false;
    const actual = Buffer.from(parts[1] ?? '', 'base64');
    const wanted = Buffer.from(expected, 'base64');
    return actual.length === wanted.length && timingSafeEqual(actual, wanted);
  });
}
function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character] ?? character);
}
function safeFilename(value: string): string {
  return value.replace(/[\\/\r\n\0]/g, '_').slice(0, 180) || 'attachment';
}
