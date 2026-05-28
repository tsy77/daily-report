import fetch from 'node-fetch';
import { readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

function loadProfile() {
  try {
    return readFileSync(join(__dirname, '..', 'profile.md'), 'utf-8');
  } catch {
    return '';
  }
}

function loadSystemPrompt() {
  try {
    return readFileSync(join(__dirname, '..', 'prompts', 'system-prompt.md'), 'utf-8');
  } catch {
    return '';
  }
}

// Hard filter based on profile rules
export function hardFilter(signals, profile) {
  if (!profile) return signals;

  const hardRules = [
    /纯品牌营销|投放优化|跟.*AI.*工具无关/,
    /自建物流仓储/,
    /大品牌|年 GMV 过亿|年GMV过亿/,
    /纯技术论文|没有电商落地场景/,
  ];

  return signals.filter(signal => {
    const text = `${signal.title} ${signal.content}`;
    for (const rule of hardRules) {
      if (rule.test(text)) return false;
    }
    return true;
  });
}

// Score based on bonus rules
export function scoreSignal(signal, profile) {
  let score = 0;
  const text = `${signal.title} ${signal.content}`.toLowerCase();

  // Rule 1: 中小卖家能直接上手用
  if (/small|中小|smb|seller|卖家|独立站|个人/.test(text)) score += 2;
  // Rule 2: 商品图像、视频、内容生产
  if (/image|photo|video|视觉|图片|视频|内容生产|generat/.test(text)) score += 2;
  // Rule 3: 替代 Excel/人工场景
  if (/excel|手动|人工|manual|spreadsheets?|替代|自动化/.test(text)) score += 2;
  // Rule 4: 用户自发抱怨/求推荐
  if (/求推荐|抱怨|吐槽|recommend|frustrat|any tool|looking for|help/.test(text)) score += 2;
  // Rule 5: 1-2 周 MVP 验证
  if (/api|mvp|prototype|quick|简单|fast|集成/.test(text)) score += 1;

  return score;
}

// Deduplicate by link
export function deduplicate(signals) {
  const seen = new Set();
  return signals.filter(s => {
    if (seen.has(s.link)) return false;
    seen.add(s.link);
    return true;
  });
}

// Cluster using LLM
export async function clusterWithLLM(signals, dryRun = false) {
  if (dryRun) {
    return signals.map(s => ({
      theme: s.title.slice(0, 40),
      signals: [s],
      why_now: '(dry-run: 未调用 LLM)',
      possible_product: '',
      today_action: '',
      score: 0,
    }));
  }

  const apiKey = process.env.LLM_API_KEY;
  const baseUrl = process.env.LLM_BASE_URL || 'https://open.bigmodel.cn/api/paas/v4';
  const model = process.env.LLM_MODEL || 'glm-4-plus';

  if (!apiKey) {
    console.warn('[Cluster] No LLM_API_KEY. Falling back to dry-run mode.');
    return clusterWithLLM(signals, true);
  }

  const profile = loadProfile();
  const systemPrompt = loadSystemPrompt();

  const signalSummaries = signals.map((s, i) =>
    `[${i + 1}] [${s.source}] ${s.title}\n    ${s.link}\n    ${(s.content || '').slice(0, 200)}`
  ).join('\n\n');

  const userPrompt = `# Profile\n${profile}\n\n# Raw Signals (${signals.length} items)\n${signalSummaries}\n\n请对以上信号进行聚类分析，输出 JSON 数组，每个元素包含：\n- theme: 主题名称（中文）\n- signals: 相关信号编号数组\n- why_now: 为什么是现在（一句话）\n- possible_product: 可能的产品方向（一句话）\n- today_action: 今天可以做什么验证（一句话）\n\n只输出 JSON 数组，不要其他内容。`;

  try {
    const res = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: [
          ...(systemPrompt ? [{ role: 'system', content: systemPrompt }] : []),
          { role: 'user', content: userPrompt },
        ],
        temperature: 0.3,
        max_tokens: 4000,
      }),
      timeout: 60000,
    });

    if (!res.ok) {
      console.warn(`[Cluster] LLM API error: ${res.status}`);
      return clusterWithLLM(signals, true);
    }

    const data = await res.json();
    const content = data?.choices?.[0]?.message?.content || '[]';

    // Extract JSON from response (handle markdown code blocks)
    const jsonMatch = content.match(/\[[\s\S]*\]/);
    if (!jsonMatch) {
      console.warn('[Cluster] No JSON found in LLM response');
      return clusterWithLLM(signals, true);
    }

    const clusters = JSON.parse(jsonMatch[0]);

    // Map signal indices back to actual signals and add scores
    return clusters.map(c => {
      const clusterSignals = (c.signals || [])
        .map(i => signals[i - 1])
        .filter(Boolean);
      const score = clusterSignals.reduce((sum, s) => sum + scoreSignal(s, profile), 0);
      return {
        ...c,
        signals: clusterSignals,
        score,
      };
    }).sort((a, b) => b.score - a.score);
  } catch (err) {
    console.warn(`[Cluster] Error: ${err.message}`);
    return clusterWithLLM(signals, true);
  }
}
