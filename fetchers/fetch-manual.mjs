import { readFileSync } from 'fs';

export async function fetchManual(sourceConfig) {
  const { file } = sourceConfig;
  const signals = [];

  try {
    const content = readFileSync(file, 'utf-8');
    const lines = content.split('\n').filter(l => l.trim());

    for (const line of lines) {
      // Format: URL | title | optional note
      const parts = line.split('|').map(s => s.trim());
      if (parts.length < 2) continue;

      signals.push({
        source: 'manual',
        title: parts[1],
        link: parts[0],
        content: parts.slice(2).join(' | ') || parts[1],
        date: new Date().toISOString(),
      });
    }

    console.log(`[Manual] Loaded ${signals.length} items from ${file}`);
  } catch (err) {
    if (err.code === 'ENOENT') {
      console.log(`[Manual] No manual source file (${file}). Skipping.`);
    } else {
      console.warn(`[Manual] Error: ${err.message}`);
    }
  }

  return signals;
}
