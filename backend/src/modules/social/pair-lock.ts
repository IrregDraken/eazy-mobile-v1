import type { PoolClient } from 'pg';

export function canonicalUserPairLockKey(firstUserId: string, secondUserId: string): string {
  const [first, second] = [firstUserId, secondUserId].sort();
  return `direct:${first}:${second}`;
}

export async function lockUserPair(client: PoolClient, firstUserId: string, secondUserId: string): Promise<void> {
  await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [canonicalUserPairLockKey(firstUserId, secondUserId)]);
}
