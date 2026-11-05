import { loadConfig } from '../config/env.js';
import { closeDbPool, createDbPool, withTransaction } from '../database/client.js';
import { ORDER_ESCROW_RELEASE_BATCH_SIZE } from '../modules/orders/constants.js';
import { OrderRepository } from '../modules/orders/repository.js';

const config = loadConfig();
const pool = createDbPool(config);
try {
  const released = await withTransaction(pool, client =>
    new OrderRepository(pool).releaseDueEscrow(client, ORDER_ESCROW_RELEASE_BATCH_SIZE)
  );
  process.stdout.write(JSON.stringify({
    job: 'order-escrow-auto-release',
    releasedFulfillments: released,
    batchSize: ORDER_ESCROW_RELEASE_BATCH_SIZE
  }) + '\n');
} catch (error) {
  process.stderr.write('Order escrow auto-release job failed.\n');
  process.exitCode = 1;
} finally {
  await closeDbPool(pool);
}
