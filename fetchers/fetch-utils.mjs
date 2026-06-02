import fetch from 'node-fetch';

export async function fetchWithTimeout(url, options = {}, timeoutMs = 15000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, {
      ...options,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
}

export function fetchErrorMessage(err) {
  if (err?.name === 'AbortError') return 'request timed out';
  return err?.message || String(err);
}
