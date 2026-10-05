import type { DbClient } from '../../database/client.js';

export interface FoundationRepository { health(client: DbClient): Promise<{ ok: true }>; }
export interface FoundationService { health(): Promise<{ ok: true }>; }

export function createFoundationService(repository: FoundationRepository, clientFactory: () => Promise<DbClient>): FoundationService {
  return { health: async () => { const client = await clientFactory(); return repository.health(client); } };
}

// Routes should call a controller; controllers should translate HTTP to service calls;
// services own business orchestration; repositories own SQL; providers stay behind interfaces.
