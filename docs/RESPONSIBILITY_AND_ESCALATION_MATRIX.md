# Eazy — Responsibility and Escalation Matrix

> **Internal operating draft.** Confirmed business ownership does not prove technical access to any provider account. Technical owner names remain open unless explicitly confirmed below.

## Confirmed people and business responsibility

| Area | Confirmed responsible party | Evidence/status | Escalation or decision needed |
|---|---|---|---|
| Business decisions and policy approval | Anthony, owner of Thony Dynamic Enterprises | Confirmed by supplied business information | Record approval against exact policy versions and dates |
| Privacy complaints and account-deletion oversight | Anthony initially | Confirmed by supplied business information | Approve identity verification, SLA, exceptions and backup/provider wording |
| Post-launch business operation | Thony Dynamic Enterprises | Confirmed by supplied business information | Name a backup operator and service administrators |
| Customer support | Not explicitly assigned | Proposed mailbox is `support@eazy.name.ng`; receipt unverified | Anthony assigns support owner, hours, languages and SLA |
| Payment disputes and refunds | Not explicitly assigned | Finance/payment owner is not confirmed | Anthony assigns finance authority and approves Paystack/refund process |
| Security incident escalation | Not explicitly assigned | `security@eazy.name.ng` is proposed; receipt unverified | Anthony assigns incident commander/security owner and notification authority |

## Technical and provider responsibility gaps

| Function | Current source/runbook state | Required owner before launch | Evidence required |
|---|---|---|---|
| Technical maintenance and deployment | Runbook exists; no named engineering owner | Anthony to name an engineering lead or service provider | Owner, backup, deployment approval and rollback authority |
| Firebase administration | Source uses Firebase identity and Admin SDK | Business-controlled administrator to be confirmed | Console owner, MFA/recovery, project ID match, admin list |
| Supabase database/storage | Source uses PostgreSQL/RLS and private `eazy-media` bucket | Business-controlled administrator to be confirmed | Project owner, service-role secret custody, backup and storage policy |
| Railway hosting | Backend deployment and health endpoints exist | Business-controlled hosting administrator to be confirmed | Account owner, deployment access, environment/recovery procedure |
| Resend/email | Adapter and optional Reply-To exist; domain/email setup in progress | Mail/provider administrator to be confirmed | Sender verification, inbound routing tests, recovery and bounce handling |
| Paystack/payment provider | Adapter exists; activation/mode/webhook unverified | Finance/provider administrator to be confirmed | Sandbox/live mode, webhook owner, reconciliation and dispute authority |
| Domain/DNS/HTTPS | Domain has authority and MX/DMARC/DKIM observations; no website A/AAAA/CNAME answer observed | Domain administrator to be confirmed | Registrar/DNS owner, zone export, HTTPS certificate and non-destructive DNS diff |
| Backup and restoration | Runbook exists; no drill recorded | Infrastructure owner to be confirmed | Isolated restore, RPO/RTO decision, result and sign-off |
| Monitoring and post-launch response | Health/readiness/logging code exists; no dashboard evidence | Operations owner to be confirmed | Alert routing, incident record, uptime/error/payment monitoring and on-call backup |
| Privacy/data-protection professional | None designated | Anthony to engage qualified lawyer/DPO/DPCO if required | Scope, advice, review record and any NDPC filing/verification evidence |

## Escalation procedure

1. Support records the minimum request reference and routes privacy, deletion, payment, UGC and security matters to the designated owner.
2. Privacy or deletion requests go to Anthony initially until a different owner is formally assigned. No passwords, tokens, PINs or one-time codes are collected.
3. Payment discrepancies remain pending until server and provider records reconcile. Support must not promise a refund or mark an ambiguous result successful.
4. Security reports preserve request IDs, timestamps and non-secret evidence, then escalate to the incident commander and Anthony. Public notification requires an approved decision.
5. Suspected personal-data incidents are escalated to Anthony and the professional reviewer, if engaged, for scope, containment, regulator and user-notification decisions.
6. Deployment, DNS, credential, backup and destructive database actions require the named technical owner and Anthony’s authorization where business or legal impact is material.

## Status

**Business ownership confirmed. Technical/provider ownership and escalation assignments incomplete.** This matrix is not evidence that any mailbox, cloud console, recovery method or billing account is accessible to the business.
