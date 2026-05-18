/**
 * Bootstrap helper: set default source local_path and sync.repo_path.
 * Invoked from configure-gbrain.sh after brain content is ready.
 *
 * Usage: GBRAIN_HOME=<data> bun run scripts/bootstrap/ensure-brain-path.ts <brain-repo-path>
 */

import { resolve } from 'path';
import { loadConfig, toEngineConfig } from '../../src/core/config.ts';
import { createEngine } from '../../src/core/engine-factory.ts';
import { connectWithRetry } from '../../src/core/db.ts';

const brainPath = resolve(process.argv[2] ?? '');
if (!brainPath) {
  console.error('Usage: ensure-brain-path.ts <absolute-brain-repo-path>');
  process.exit(2);
}

const config = loadConfig();
if (!config) {
  console.error('No brain configured. Run gbrain init first.');
  process.exit(3);
}

const engineCfg = toEngineConfig(config);
const engine = await createEngine(engineCfg);
await connectWithRetry(engine, engineCfg, { noRetry: true });

try {
  const updated = await engine.executeRaw<{ id: string }>(
    `UPDATE sources SET local_path = $1 WHERE id = 'default' RETURNING id`,
    [brainPath],
  );
  if (updated.length === 0) {
    console.error('No default source row found; run gbrain init first');
    process.exit(3);
  }
  await engine.setConfig('sync.repo_path', brainPath);
  console.log(`Registered brain repo: local_path + sync.repo_path → ${brainPath}`);
} finally {
  await engine.disconnect();
}
