import { writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';

function formatDate(date) {
  const offset = date.getTimezoneOffset();
  const local = new Date(date.getTime() - offset * 60000);
  return local.toISOString().slice(0, 10);
}

export function generateReport(clusters, signals, dryRun = false) {
  const today = formatDate(new Date());
  const topCluster = clusters[0];
  const top3Signals = signals.slice(0, 3);

  let md = `# 电商痛点需求雷达\n`;
  md += `**${today}** | 信号数: ${signals.length} | 聚类数: ${clusters.length}`;
  if (dryRun) md += ` | ⚠️ DRY-RUN 模式`;
  md += `\n\n---\n\n`;

  // 今日主判断
  md += `## 今日主判断\n\n`;
  if (topCluster && !dryRun) {
    md += `${topCluster.why_now || '—'}\n\n`;
    md += `**最值得做的方向**: ${topCluster.possible_product || '—'}\n\n`;
    md += `**今天可以验证**: ${topCluster.today_action || '—'}\n\n`;
  } else {
    md += `(需配置 LLM_API_KEY 后运行以生成分析)\n\n`;
  }

  // 聚类主题
  md += `## 信号聚类\n\n`;
  for (let i = 0; i < clusters.length; i++) {
    const c = clusters[i];
    md += `### ${i + 1}. ${c.theme}\n`;
    if (!dryRun) {
      md += `- **为什么是现在**: ${c.why_now || '—'}\n`;
      md += `- **可能的产品**: ${c.possible_product || '—'}\n`;
      md += `- **今天验证**: ${c.today_action || '—'}\n`;
      md += `- **得分**: ${c.score}\n`;
    }
    md += `\n相关信号:\n\n`;
    for (const s of (c.signals || [])) {
      md += `- [${s.title}](${s.link}) _(${s.source})_\n`;
    }
    md += `\n`;
  }

  // 今日 Top 3 信号
  md += `## 今日 Top 3 信号\n\n`;
  for (let i = 0; i < top3Signals.length; i++) {
    const s = top3Signals[i];
    md += `### ${i + 1}. ${s.title}\n`;
    md += `- 来源: ${s.source}\n`;
    md += `- 链接: ${s.link}\n`;
    if (s.score !== undefined) md += `- 热度: ${s.score}\n`;
    if (s.numComments !== undefined) md += `- 评论: ${s.numComments}\n`;
    if (s.content) md += `- 摘要: ${s.content.slice(0, 300)}\n`;
    md += `\n`;
  }

  // 机会拆解
  md += `## 机会拆解\n\n`;
  if (topCluster && !dryRun) {
    md += `| 维度 | 分析 |\n|------|------|\n`;
    md += `| 痛点 | ${topCluster.theme} |\n`;
    md += `| 买家 | 中小电商卖家、独立站运营 |\n`;
    md += `| 替代方案 | 人工/Excel/外包 |\n`;
    md += `| 小产品入口 | ${topCluster.possible_product || '—'} |\n`;
    md += `| 验证动作 | ${topCluster.today_action || '—'} |\n`;
  } else {
    md += `(需配置 LLM_API_KEY 后运行以生成分析)\n`;
  }
  md += `\n\n`;

  // 反向视角
  md += `## 反向视角 — 今天不要追\n\n`;
  if (!dryRun && clusters.length > 3) {
    const bottomClusters = clusters.slice(-2);
    for (const c of bottomClusters) {
      md += `- ${c.theme}: ${(c.why_now || '').slice(0, 60)}\n`;
    }
  } else {
    md += `(需配置 LLM_API_KEY 后运行)\n`;
  }
  md += `\n`;

  // 所有来源链接
  md += `## 所有信号来源\n\n`;
  for (const s of signals) {
    md += `- [${s.title}](${s.link}) _(${s.source})_\n`;
  }

  return { md, today };
}

export function saveReport(md, today) {
  const outputDir = join(process.cwd(), 'output');
  mkdirSync(outputDir, { recursive: true });

  const filename = `signal-${today}.md`;
  const filepath = join(outputDir, filename);
  writeFileSync(filepath, md, 'utf-8');
  console.log(`\n✅ Report saved to output/${filename}`);
  return filepath;
}
