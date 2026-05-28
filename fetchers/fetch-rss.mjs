import fetch from 'node-fetch';
import { XMLParser } from 'fast-xml-parser';

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: '@_',
});

function matchesKeywords(text, keywords) {
  if (!keywords || keywords.length === 0) return true;
  const lower = text.toLowerCase();
  return keywords.some(kw => lower.includes(kw.toLowerCase()));
}

function extractItems(parsed, feedUrl) {
  const rssItems = parsed?.rss?.channel?.item || [];
  const atomEntries = parsed?.feed?.entry || [];
  const raw = Array.isArray(rssItems) ? rssItems : [rssItems];
  const rawAtom = Array.isArray(atomEntries) ? atomEntries : [atomEntries];

  const items = [];

  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    items.push({
      source: feedUrl,
      title: item.title || '',
      link: item.link || item['@_href'] || '',
      content: item.description || item.summary || item.content || '',
      date: item.pubDate || item.updated || item.published || new Date().toISOString(),
    });
  }

  for (const entry of rawAtom) {
    if (!entry || typeof entry !== 'object') continue;
    const link = entry.link?.['@_href'] || entry.link || '';
    const content = entry.content?.['#text'] || entry.content || entry.summary || '';
    items.push({
      source: feedUrl,
      title: entry.title || '',
      link,
      content,
      date: entry.published || entry.updated || new Date().toISOString(),
    });
  }

  return items;
}

export async function fetchRSS(sourceConfig) {
  const { url, keywords } = sourceConfig;
  const signals = [];

  try {
    const res = await fetch(url, {
      headers: { 'User-Agent': 'DailyReportBot/1.0' },
      timeout: 15000,
    });
    if (!res.ok) {
      console.warn(`[RSS] Failed to fetch ${url}: ${res.status}`);
      return signals;
    }

    const xml = await res.text();
    const parsed = parser.parse(xml);
    const items = extractItems(parsed, url);

    for (const item of items) {
      const text = `${item.title} ${item.content}`;
      if (matchesKeywords(text, keywords)) {
        signals.push(item);
      }
    }

    console.log(`[RSS] ${url}: ${signals.length}/${items.length} items matched`);
  } catch (err) {
    console.warn(`[RSS] Error fetching ${url}: ${err.message}`);
  }

  return signals;
}
