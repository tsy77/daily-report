import { fetchWithTimeout, fetchErrorMessage } from './fetch-utils.mjs';

export async function fetchTwitter(sourceConfig) {
  const { queries, accounts } = sourceConfig;
  const signals = [];

  const bearerToken = process.env.TWITTER_BEARER_TOKEN;
  const rapidApiKey = process.env.TWITTER_RAPIDAPI_KEY;
  const rapidApiHost = process.env.TWITTER_RAPIDAPI_HOST;

  // Prefer official API v2 if bearer token is available
  if (bearerToken) {
    return fetchTwitterOfficial(queries, accounts, bearerToken, signals);
  }

  // Fallback to RapidAPI (uses accounts-based fetching)
  if (rapidApiKey && rapidApiHost) {
    return fetchTwitterRapidAPI({ _accounts: accounts || [] }, rapidApiKey, rapidApiHost, signals);
  }

  console.warn('[Twitter] No API credentials configured. Skipping Twitter fetch.');
  console.warn('[Twitter] Set TWITTER_BEARER_TOKEN or TWITTER_RAPIDAPI_KEY in .env');
  return signals;
}

async function fetchTwitterOfficial(queries, accounts, bearerToken, signals) {
  const seen = new Set();

  for (const query of queries) {
    try {
      const url = `https://api.twitter.com/2/tweets/search/recent?query=${encodeURIComponent(query)}&max_results=20&tweet.fields=created_at,text,public_metrics,author_id`;
      const res = await fetchWithTimeout(url, {
        headers: {
          'Authorization': `Bearer ${bearerToken}`,
          'User-Agent': 'DailyReportBot/1.0',
        },
      }, 15000);

      if (!res.ok) {
        console.warn(`[Twitter] API error: ${res.status}`);
        continue;
      }

      const data = await res.json();
      const tweets = data?.data || [];

      for (const tweet of tweets) {
        if (seen.has(tweet.id)) continue;
        seen.add(tweet.id);

        signals.push({
          source: 'twitter',
          title: tweet.text?.slice(0, 100) || '',
          link: `https://twitter.com/i/web/status/${tweet.id}`,
          content: tweet.text || '',
          date: tweet.created_at || new Date().toISOString(),
          score: tweet.public_metrics?.like_count || 0,
          numComments: tweet.public_metrics?.reply_count || 0,
        });
      }

      console.log(`[Twitter] "${query}": ${tweets.length} tweets`);
    } catch (err) {
      console.warn(`[Twitter] Error: ${fetchErrorMessage(err)}`);
    }
  }

  return signals;
}

async function fetchTwitterRapidAPI(queries, apiKey, apiHost, signals) {
  const seen = new Set();
  const accounts = queries._accounts || [];

  for (const account of accounts) {
    const screenName = account.screen_name || account;
    const userId = account.id;

    if (!userId) {
      console.warn(`[Twitter/RapidAPI] Skipping @${screenName}: no numeric id configured`);
      continue;
    }

    try {
      const tweetsRes = await fetchWithTimeout(
        `https://${apiHost}/user-tweets?user=${userId}&count=20`,
        {
          headers: {
            'x-rapidapi-key': apiKey,
            'x-rapidapi-host': apiHost,
            'Content-Type': 'application/json',
          },
        },
        15000
      );

      if (!tweetsRes.ok) {
        console.warn(`[Twitter/RapidAPI] user-tweets error for @${screenName}: ${tweetsRes.status}`);
        continue;
      }

      const tweetsData = await tweetsRes.json();
      const entries = tweetsData?.result?.timeline?.instructions
        ?.flatMap(i => i.entries || [])
        .filter(e => e.content?.itemContent?.tweet_results?.result) || [];

      for (const entry of entries) {
        const tweet = entry.content.itemContent.tweet_results.result;
        const tweetId = tweet?.rest_id || tweet?.legacy?.id_str;
        if (!tweetId || seen.has(tweetId)) continue;
        seen.add(tweetId);

        const legacy = tweet?.legacy || {};
        const text = legacy.full_text || tweet?.note_tweet?.note_tweet_results?.result?.text || '';
        signals.push({
          source: 'twitter',
          title: text.slice(0, 100),
          link: `https://twitter.com/i/web/status/${tweetId}`,
          content: text,
          date: legacy.created_at || new Date().toISOString(),
          score: legacy.favorite_count || 0,
          numComments: legacy.reply_count || 0,
        });
      }

      console.log(`[Twitter/RapidAPI] @${screenName}: ${entries.length} tweets`);
    } catch (err) {
      console.warn(`[Twitter/RapidAPI] Error for @${screenName}: ${fetchErrorMessage(err)}`);
    }
  }

  return signals;
}
