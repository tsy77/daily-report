#!/usr/bin/env node
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'fs';
import { join } from 'path';

const workdir = process.cwd();
const outdir = join(workdir, 'output');
const date = process.argv[2] || new Date().toISOString().slice(0, 10);

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function normalizeTheme(theme) {
  return String(theme || '未命名主题')
    .toLowerCase()
    .replace(/[\s\p{P}\p{S}]+/gu, '')
    .slice(0, 40);
}

function readJsonArray(path) {
  try {
    const data = JSON.parse(readFileSync(path, 'utf8'));
    return Array.isArray(data) ? data : [];
  } catch (err) {
    console.warn(`[merge] skip invalid JSON ${path}: ${err.message}`);
    return [];
  }
}

const clusterFiles = existsSync(outdir)
  ? readdirSync(outdir).filter(f => /^cluster-\d+\.json$/.test(f)).sort()
  : [];

let clusters = [];
for (const file of clusterFiles) {
  clusters.push(...readJsonArray(join(outdir, file)).map(c => ({ ...c, _file: file })));
}

const byTheme = new Map();
for (const c of clusters) {
  const key = normalizeTheme(c.theme);
  const current = byTheme.get(key);
  const score = Number(c.score || 0);
  const signalTitles = Array.isArray(c.signal_titles) ? c.signal_titles : [];
  if (!current) {
    byTheme.set(key, {
      theme: c.theme || '未命名主题',
      why_now: c.why_now || '',
      possible_product: c.possible_product || '',
      today_action: c.today_action || '',
      score,
      signal_titles: [...signalTitles],
      sources: [c._file],
    });
  } else {
    current.score = Math.max(current.score || 0, score);
    current.signal_titles = [...new Set([...current.signal_titles, ...signalTitles])].slice(0, 12);
    current.sources = [...new Set([...current.sources, c._file])];
    if (score >= (current.score || 0)) {
      current.why_now ||= c.why_now || '';
      current.possible_product ||= c.possible_product || '';
      current.today_action ||= c.today_action || '';
    }
  }
}

const merged = [...byTheme.values()].sort((a, b) => (b.score || 0) - (a.score || 0));
const topTheme = merged[0]?.theme || 'daily signal report';
let signals = [];
try {
  signals = JSON.parse(readFileSync(join(outdir, 'signals.json'), 'utf8')).slice(0, 20);
} catch {}

const cards = merged.map((c, i) => `
  <section class="card">
    <div class="card-head">
      <span class="rank">#${i + 1}</span>
      <h2>${escapeHtml(c.theme)}</h2>
      <span class="score">${escapeHtml(c.score)}/10</span>
    </div>
    <p><strong>为什么现在：</strong>${escapeHtml(c.why_now || '暂无')}</p>
    <p><strong>可能产品：</strong>${escapeHtml(c.possible_product || '暂无')}</p>
    <p><strong>今日验证动作：</strong>${escapeHtml(c.today_action || '暂无')}</p>
    <details>
      <summary>相关信号 ${c.signal_titles?.length || 0} 条</summary>
      <ul>${(c.signal_titles || []).map(t => `<li>${escapeHtml(t)}</li>`).join('')}</ul>
    </details>
  </section>`).join('\n');

const signalList = signals.map(s => `<li><a href="${escapeHtml(s.link || '#')}" target="_blank" rel="noreferrer">${escapeHtml(s.title)}</a><span>${escapeHtml(s.source || '')}</span></li>`).join('\n');

const html = `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>每日信号雷达 ${escapeHtml(date)}</title>
<style>
:root{color-scheme:dark;--bg:#0b1020;--panel:#121a2f;--muted:#95a3b8;--text:#edf2ff;--accent:#62d6ff;--line:#24314f;--hot:#ffb86b}
*{box-sizing:border-box}body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:radial-gradient(circle at top,#17213d,var(--bg));color:var(--text);line-height:1.6}.wrap{max-width:980px;margin:0 auto;padding:32px 18px 80px}header{padding:28px 0 18px}.eyebrow{color:var(--accent);font-weight:700;letter-spacing:.08em}h1{font-size:clamp(30px,6vw,56px);line-height:1.05;margin:8px 0 12px}.meta{color:var(--muted)}.hero,.card,.signals{background:rgba(18,26,47,.82);border:1px solid var(--line);border-radius:22px;padding:22px;margin:18px 0;box-shadow:0 20px 60px rgba(0,0,0,.25)}.hero strong{color:var(--hot)}.card-head{display:flex;gap:12px;align-items:center}.card h2{flex:1;margin:0;font-size:22px}.rank,.score{border:1px solid var(--line);border-radius:999px;padding:4px 10px;color:var(--accent);white-space:nowrap}.score{color:var(--hot)}p{margin:10px 0}details{margin-top:12px;color:var(--muted)}summary{cursor:pointer;color:var(--accent)}a{color:var(--accent);text-decoration:none}.signals li{margin:10px 0}.signals span{display:block;color:var(--muted);font-size:13px}@media(max-width:640px){.card-head{align-items:flex-start}.card h2{font-size:18px}.wrap{padding:20px 12px 60px}}
</style>
</head>
<body><main class="wrap">
<header>
  <div class="eyebrow">ECOMMERCE PAINPOINT RADAR</div>
  <h1>每日信号雷达</h1>
  <div class="meta">${escapeHtml(date)} · 聚类 ${merged.length} 个 · 信号 ${signals.length} 条预览</div>
</header>
<section class="hero">
  <p>今日主判断：<strong>${escapeHtml(topTheme)}</strong></p>
  <p>本报告基于 Reddit / Hacker News / Product Hunt / Shopify changelog / X 等公开信号自动聚类生成，用于发现电商商家的高频痛点和可验证产品机会。</p>
</section>
${cards || '<section class="card"><h2>暂无聚类</h2><p>今天没有生成有效聚类。</p></section>'}
<section class="signals"><h2>Top 信号预览</h2><ol>${signalList}</ol></section>
</main></body></html>`;

const htmlPath = join(outdir, `signal-${date}.html`);
writeFileSync(htmlPath, html, 'utf8');
writeFileSync(join(outdir, `summary-${date}.json`), JSON.stringify({ theme: topTheme, count: signals.length, clusters: merged.length, html: htmlPath }, null, 2), 'utf8');
console.log(JSON.stringify({ theme: topTheme, count: signals.length, clusters: merged.length, html: htmlPath }));
