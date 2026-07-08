# Retrieve Workflow

Multi-layer retrieval for DIFFICULT content. USE ONLY WHEN the user indicates
difficulty: "can't get this", "having trouble", "site is blocking", "protected
site", "keeps giving CAPTCHA", "won't let me scrape". DO NOT use for simple
"read this page" requests — plain WebFetch handles those.

**NOT for research questions** — use the Research modes for "research X" or
"find information about X".

## Retrieval Strategy — 3 Layers

```
Layer 1: Built-in tools (WebFetch, WebSearch, curl with browser headers)
  ↓ (if blocked, rate-limited, or fails)
Layer 2: Alternate routes (caches, archives, mirrors, APIs)
  ↓ (if the content is session-bound or behind hard bot detection)
Layer 3: Interceptor (the user's real Chrome — real sessions, zero automation fingerprint)
```

No proxy/scraping service ships with this harness (W2.15: the BrightData and
Apify layers retired with their skills — no keys ever existed on this
machine). Escalation ends at the real browser.

## Layer 1: Built-in Tools

1. **WebFetch** the URL directly. Follow redirects; retry once on transient
   errors.
2. If blocked, **curl with realistic browser headers** (User-Agent of current
   Chrome, `Accept-Language`, `Referer` of the site root). Light throttling
   between requests to the same domain.
3. For discovery, **WebSearch** the exact title or distinctive phrases —
   the content is often republished or quoted elsewhere.

## Layer 2: Alternate Routes

Try, in order of freshness needed:

- **Web archives**: `https://web.archive.org/web/<url>` (Wayback), and search
  archive.today for the URL.
- **Reader/cache endpoints**: AMP versions, `?output=json`/RSS feeds, print
  views (`/print`, `?print=1`).
- **Official APIs**: many "blocked" sites expose the same data via a public
  API or feed — check before fighting the HTML.
- **Mirrors/syndication**: the same article on a syndicating outlet.

## Layer 3: Interceptor (Real Browser)

For session-bound pages (logged-in content the user can see) or hard bot
detection, invoke `Skill("Interceptor")` — it drives the user's actual Chrome
via extension, using their real sessions, with no automation fingerprint.

- Best for: authenticated dashboards, paywalled content the user subscribes
  to, sites where Layers 1-2 hit CAPTCHA walls.
- Compound commands (open, read, act, inspect) collapse multi-step flows.
- Respect the obvious boundary: retrieve what the user can legitimately see
  in their own browser, nothing else.

## Failure Protocol

If all three layers fail, say so plainly: name the URL, which layers were
tried, and the exact failure mode of each. Never substitute a hallucinated
summary for content that could not be retrieved.
