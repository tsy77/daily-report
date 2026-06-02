import { XMLParser } from 'fast-xml-parser';
import { fetchWithTimeout, fetchErrorMessage } from './fetch-utils.mjs';

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: '@_',
  processEntities: false,
  htmlEntities: false,
});

function matchesKeywords(text, keywords) {
  if (!keywords || keywords.length === 0) return true;
  const lower = text.toLowerCase();
  return keywords.some(kw => lower.includes(kw.toLowerCase()));
}

export async function fetchReddit(sourceConfig) {
  const { subreddits, keywords } = sourceConfig;
  const signals = [];

  for (const sub of subreddits) {
    try {
      const url = `https://www.reddit.com/r/${sub}/new.rss`;
      const res = await fetchWithTimeout(url, {
        headers: { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36' },
      }, 15000);
      if (!res.ok) {
        console.warn(`[Reddit] Failed to fetch r/${sub}: ${res.status}`);
        continue;
      }

      const xml = await res.text();
      const parsed = parser.parse(xml);
      const entries = parsed?.feed?.entry || [];
      const raw = Array.isArray(entries) ? entries : [entries];

      let matched = 0;
      for (const entry of raw) {
        if (!entry || typeof entry !== 'object') continue;

        const title = entry.title || '';
        const link = entry.link?.['@_href'] || entry.link || '';
        const content = entry.content?.['#text'] || entry.content || entry.summary || '';
        const text = `${title} ${content}`;

        if (matchesKeywords(text, keywords)) {
          matched++;
          signals.push({
            source: `reddit/r/${sub}`,
            title,
            link,
            content,
            date: entry.published || entry.updated || new Date().toISOString(),
          });
        }
      }

      console.log(`[Reddit] r/${sub}: ${matched}/${raw.length} posts matched`);
    } catch (err) {
      console.warn(`[Reddit] Error fetching r/${sub}: ${fetchErrorMessage(err)}`);
    }
  }

  return signals;
}
