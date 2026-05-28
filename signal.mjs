import 'dotenv/config';
import { readFileSync } from 'fs';
import { join } from 'path';

import { fetchRSS } from './fetchers/fetch-rss.mjs';
import { fetchReddit } from './fetchers/fetch-reddit.mjs';
import { fetchHackerNews } from './fetchers/fetch-hackernews.mjs';
import { fetchTwitter } from './fetchers/fetch-twitter.mjs';
import { fetchManual } from './fetchers/fetch-manual.mjs';

import { hardFilter, deduplicate, scoreSignal, clusterWithLLM } from './processors/cluster.mjs';
import { generateReport, saveReport } from './processors/report.mjs';
import { writeFileSync } from 'fs';

const dryRun = process.argv.includes('--dry-run');
const exportMode = process.argv.includes('--export');

async function loadSources() {
  const raw = readFileSync(join(process.cwd(), 'sources.json'), 'utf-8');
  return JSON.parse(raw).sources.filter(s => s.enabled);
}

async function fetchAll(sources) {
  const fetcherMap = {
    rss: fetchRSS,
    reddit: fetchReddit,
    hackernews: fetchHackerNews,
    twitter: fetchTwitter,
    manual: fetchManual,
  };

  // Group sources by type and run each type in parallel
  const promises = sources.map(async (source) => {
    const fetcher = fetcherMap[source.type];
    if (!fetcher) {
      console.warn(`[Main] Unknown source type: ${source.type}`);
      return [];
    }
    try {
      return await fetcher(source);
    } catch (err) {
      console.warn(`[Main] Error in ${source.id}: ${err.message}`);
      return [];
    }
  });

  const results = await Promise.allSettled(promises);
  const allSignals = [];

  for (const result of results) {
    if (result.status === 'fulfilled') {
      allSignals.push(...result.value);
    }
  }

  return allSignals;
}

async function main() {
  console.log('📡 电商痛点需求雷达');
  console.log(`   模式: ${dryRun ? 'DRY-RUN' : '正式运行'}`);
  console.log('---');

  // Step 1: Load sources
  const sources = await loadSources();
  console.log(`📋 已加载 ${sources.length} 个数据源\n`);

  // Step 2: Fetch all sources in parallel
  console.log('🔄 抓取信号中...\n');
  const rawSignals = await fetchAll(sources);
  console.log(`\n📊 原始信号: ${rawSignals.length} 条`);

  // Step 3: Deduplicate
  const uniqueSignals = deduplicate(rawSignals);
  console.log(`📊 去重后: ${uniqueSignals.length} 条`);

  // Step 4: Hard filter
  let profile;
  try {
    profile = readFileSync(join(process.cwd(), 'profile.md'), 'utf-8');
  } catch {
    profile = '';
  }
  const filtered = hardFilter(uniqueSignals, profile);
  console.log(`📊 硬过滤后: ${filtered.length} 条`);

  // Step 5: Score
  const scored = filtered
    .map(s => ({ ...s, _score: scoreSignal(s, profile) }))
    .sort((a, b) => b._score - a._score);

  // Export mode: save scored signals as JSON and exit
  if (exportMode) {
    const exportPath = join(process.cwd(), 'output', 'signals.json');
    const exportData = scored.map((s, i) => ({
      idx: i + 1,
      source: s.source,
      title: s.title,
      link: s.link,
      content: (s.content || '').slice(0, 300),
      date: s.date,
      score: s.score,
      numComments: s.numComments,
      _score: s._score,
    }));
    writeFileSync(exportPath, JSON.stringify(exportData, null, 2), 'utf-8');
    console.log(`\n✅ Exported ${exportData.length} scored signals to output/signals.json`);
    return;
  }

  // Step 6: Cluster
  console.log(`\n🧠 聚类分析中...`);
  const clusters = await clusterWithLLM(scored, dryRun);
  console.log(`📊 生成 ${clusters.length} 个聚类主题\n`);

  // Step 7: Generate and save report
  const { md } = generateReport(clusters, scored, dryRun);
  saveReport(md, new Date().toISOString().slice(0, 10));

  console.log(`\n✅ 完成！共处理 ${scored.length} 条信号`);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
