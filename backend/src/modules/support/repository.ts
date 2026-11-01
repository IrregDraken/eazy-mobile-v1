import type { Pool } from 'pg';

export type SupportCategory = 'bug' | 'account' | 'payments' | 'other';
export interface SupportReportInput {
  category: SupportCategory;
  subject: string;
  description: string;
}

export class SupportRepository {
  constructor(private readonly pool: Pool) {}

  async create(userId: string, input: SupportReportInput) {
    const result = await this.pool.query<{ id: string; status: string }>(
      `INSERT INTO support_reports (user_id, category, subject, description)
       VALUES ($1, $2, $3, $4)
       RETURNING id, status`,
      [userId, input.category, input.subject.trim(), input.description.trim()]
    );
    const report = result.rows[0];
    if (!report) throw new Error('SUPPORT_REPORT_NOT_CREATED');
    return { reportId: report.id, status: report.status };
  }
}
