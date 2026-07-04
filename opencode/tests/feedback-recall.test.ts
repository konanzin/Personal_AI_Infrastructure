/**
 * Feedback recall analyzer — the on-demand consumer that finally reads the low-rating
 * archive back (see plugins/lib/feedback-recall.lib.js). Recall is deliberate and
 * read-only: these tests pin the query/summarize behavior, not any behavior change.
 */
import { describe, test, expect } from "bun:test";
import { analyzeFeedback } from "../plugins/lib/feedback-recall.lib.js";

const r = (rating: number, comment?: string, timestamp?: string, extra: object = {}) => ({
  rating,
  comment,
  timestamp,
  session_id: "ses_x",
  source: "explicit",
  ...extra,
});

describe("analyzeFeedback", () => {
  test("returns only low ratings (≤4 by default), ignores high ones", () => {
    const out = analyzeFeedback([r(3, "too verbose"), r(8, "great"), r(1, "wrong file")]);
    expect(out.total).toBe(3);
    expect(out.lowTotal).toBe(2);
    expect(out.recent.every((x) => x.rating <= 4)).toBe(true);
  });

  test("orders most-recent first by timestamp", () => {
    const out = analyzeFeedback([
      r(2, "old", "2026-01-01T00:00:00.000Z"),
      r(3, "new", "2026-07-01T00:00:00.000Z"),
      r(1, "mid", "2026-04-01T00:00:00.000Z"),
    ]);
    expect(out.recent.map((x) => x.comment)).toEqual(["new", "mid", "old"]);
  });

  test("limit caps the returned list but lowTotal reflects the full count", () => {
    const many = Array.from({ length: 25 }, (_, i) => r(2, `c${i}`, `2026-01-${String((i % 28) + 1).padStart(2, "0")}T00:00:00.000Z`));
    const out = analyzeFeedback(many, { limit: 5 });
    expect(out.returned).toBe(5);
    expect(out.lowTotal).toBe(25);
  });

  test("sinceMs filters out older ratings", () => {
    const cutoff = Date.parse("2026-06-01T00:00:00.000Z");
    const out = analyzeFeedback(
      [r(2, "before", "2026-05-01T00:00:00.000Z"), r(3, "after", "2026-06-15T00:00:00.000Z")],
      { sinceMs: cutoff },
    );
    expect(out.recent.map((x) => x.comment)).toEqual(["after"]);
  });

  test("query filters over comment and response_preview", () => {
    const out = analyzeFeedback(
      [
        r(2, "way too verbose"),
        r(3, "edited the wrong file", undefined, { response_preview: "I changed foo.ts" }),
        r(4, "verbose again"),
      ],
      { query: "verbose" },
    );
    expect(out.lowTotal).toBe(2);
  });

  test("byRating tallies the distribution", () => {
    const out = analyzeFeedback([r(2, "a"), r(2, "b"), r(4, "c")]);
    expect(out.byRating).toEqual({ "2": 2, "4": 1 });
  });

  test("themes surface a recurring complaint (count ≥ 2)", () => {
    const out = analyzeFeedback([
      r(2, "response was too verbose"),
      r(3, "verbose and slow"),
      r(1, "wrong file entirely"),
    ]);
    expect(out.themes.find((t) => t.term === "verbose")?.count).toBe(2);
    // one-off words are not themes
    expect(out.themes.find((t) => t.term === "slow")).toBeUndefined();
  });

  test("empty / malformed input is safe", () => {
    expect(analyzeFeedback([]).lowTotal).toBe(0);
    expect(analyzeFeedback(null as any).total).toBe(0);
    expect(analyzeFeedback([{ foo: 1 } as any]).total).toBe(0); // no numeric rating → dropped
  });

  test("does NOT mutate or inject — pure read (returns a plain summary object)", () => {
    const input = [r(2, "x")];
    const snapshot = JSON.stringify(input);
    analyzeFeedback(input);
    expect(JSON.stringify(input)).toBe(snapshot); // input untouched
  });
});
