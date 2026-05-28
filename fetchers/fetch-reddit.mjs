import fetch from 'node-fetch';

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
      const url = `https://www.reddit.com/r/${sub}/new.json?limit=25`;
      const res = await fetch(url, {
        headers: { 'User-Agent': 'DailyReportBot/1.0' },
        timeout: 15000,
      });
      if (!res.ok) {
        console.warn(`[Reddit] Failed to fetch r/${sub}: ${res.status}`);
        continue;
      }

      const data = await res.json();
      const posts = data?.data?.children || [];

      for (const post of posts) {
        const d = post.data;
        const text = `${d.title} ${d.selftext || ''}`;
        if (matchesKeywords(text, keywords)) {
          signals.push({
            source: `reddit/r/${sub}`,
            title: d.title,
            link: `https://reddit.com${d.permalink}`,
            content: d.selftext || d.title,
            date: new Date(d.created_utc * 1000).toISOString(),
            score: d.score,
            numComments: d.num_comments,
          });
        }
      }

      console.log(`[Reddit] r/${sub}: fetched ${posts.length} posts`);
    } catch (err) {
      console.warn(`[Reddit] Error fetching r/${sub}: ${err.message}`);
    }
  }

  return signals;
}
