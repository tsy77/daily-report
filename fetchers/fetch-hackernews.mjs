import fetch from 'node-fetch';

export async function fetchHackerNews(sourceConfig) {
  const { queries } = sourceConfig;
  const signals = [];
  const seen = new Set();

  for (const query of queries) {
    try {
      const url = `https://hn.algolia.com/api/v1/search?query=${encodeURIComponent(query)}&tags=story&hitsPerPage=20`;
      const res = await fetch(url, {
        headers: { 'User-Agent': 'DailyReportBot/1.0' },
        timeout: 15000,
      });
      if (!res.ok) {
        console.warn(`[HN] Failed: ${res.status}`);
        continue;
      }

      const data = await res.json();
      const hits = data?.hits || [];

      for (const hit of hits) {
        if (seen.has(hit.objectID)) continue;
        seen.add(hit.objectID);

        signals.push({
          source: 'hackernews',
          title: hit.title || '',
          link: hit.url || `https://news.ycombinator.com/item?id=${hit.objectID}`,
          content: hit.title || '',
          date: hit.created_at || new Date().toISOString(),
          score: hit.points || 0,
          numComments: hit.num_comments || 0,
        });
      }

      console.log(`[HN] "${query}": ${hits.length} hits`);
    } catch (err) {
      console.warn(`[HN] Error: ${err.message}`);
    }
  }

  return signals;
}
