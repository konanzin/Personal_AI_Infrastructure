/**
 * Feedback recall analyzer — the ON-DEMAND consumer for the low-rating archive.
 *
 * Today a low rating is captured to ratings.jsonl + a LEARNING .md and then read by
 * nothing that reaches the model, so it never influences future work. This turns the
 * archive into something you can pull DELIBERATELY (via `/feedback` or bin/recall-feedback.js)
 * — it does NOT auto-inject into any prompt. Nothing here changes harness behavior;
 * it only summarizes what you already told the system, when asked.
 *
 * Pure and dependency-free (no I/O) so it is unit-testable; the bin/ wrapper feeds it
 * the parsed ratings.jsonl rows.
 */

// Ratings at or below this are "low" — the improvement-opportunity signal.
export const LOW_RATING_MAX = 4;

/**
 * @param {Array<object>} ratings  Parsed ratings.jsonl rows.
 * @param {object} opts
 * @param {number} [opts.limit=10]      Max recent low ratings to return.
 * @param {number} [opts.maxRating=4]   Treat rating <= this as low.
 * @param {number} [opts.sinceMs=null]  If set, only ratings with a timestamp newer than this.
 * @param {string} [opts.query=null]    Case-insensitive substring filter over comment/preview.
 * @returns {{
 *   total: number, lowTotal: number, returned: number,
 *   byRating: Record<string, number>,
 *   themes: Array<{ term: string, count: number }>,
 *   recent: Array<{ rating: number, comment: string|null, when: string|null, session_id: string|null, response_preview: string|null }>,
 * }}
 */
export function analyzeFeedback(ratings, opts = {}) {
  const { limit = 10, maxRating = LOW_RATING_MAX, sinceMs = null, query = null } = opts;

  const rows = (Array.isArray(ratings) ? ratings : []).filter(
    (r) => r && typeof r.rating === "number",
  );

  const parseWhen = (r) => {
    if (!r.timestamp) return 0;
    const ms = Date.parse(r.timestamp);
    return Number.isNaN(ms) ? 0 : ms;
  };

  let low = rows.filter((r) => r.rating <= maxRating);
  if (sinceMs != null) low = low.filter((r) => parseWhen(r) >= sinceMs);
  if (query) {
    const q = query.toLowerCase();
    low = low.filter(
      (r) =>
        (r.comment && r.comment.toLowerCase().includes(q)) ||
        (r.response_preview && r.response_preview.toLowerCase().includes(q)),
    );
  }

  // Most recent first (stable for equal/absent timestamps → preserves input order).
  const sorted = low
    .map((r, i) => ({ r, i, t: parseWhen(r) }))
    .sort((a, b) => b.t - a.t || b.i - a.i)
    .map((x) => x.r);

  const byRating = {};
  for (const r of low) byRating[r.rating] = (byRating[r.rating] || 0) + 1;

  const recent = sorted.slice(0, limit).map((r) => ({
    rating: r.rating,
    comment: r.comment ?? null,
    when: r.timestamp ?? null,
    session_id: r.session_id ?? null,
    response_preview: r.response_preview ?? null,
  }));

  return {
    total: rows.length,
    lowTotal: low.length,
    returned: recent.length,
    byRating,
    themes: extractThemes(low),
    recent,
  };
}

// Lightweight recurring-word signal over the comment text — surfaces "verbose",
// "wrong file", etc. when the same complaint keeps coming back. Not NLP; a stopword-
// filtered frequency count, enough to spot a theme at a glance.
const STOPWORDS = new Set(
  ("the a an and or but is are was were be been to of in on for with this that it too very " +
    "you your i me my we not no do did does response answer output was das dos que uma um para " +
    "com muito e ou mas nao não está esta isso").split(/\s+/),
);

function extractThemes(rows, top = 5) {
  const counts = new Map();
  for (const r of rows) {
    if (!r.comment) continue;
    const words = String(r.comment)
      .toLowerCase()
      .replace(/[^a-zà-ÿ0-9\s]/gi, " ")
      .split(/\s+/)
      .filter((w) => w.length >= 4 && !STOPWORDS.has(w));
    for (const w of new Set(words)) counts.set(w, (counts.get(w) || 0) + 1);
  }
  return [...counts.entries()]
    .filter(([, c]) => c >= 2) // a theme needs to recur
    .sort((a, b) => b[1] - a[1])
    .slice(0, top)
    .map(([term, count]) => ({ term, count }));
}
