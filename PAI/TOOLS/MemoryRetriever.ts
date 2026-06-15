#!/usr/bin/env bun
import {
  excerptFor,
  getKnowledgeDir,
  noteText,
  readKnowledgeNotes,
  tokenize,
  type KnowledgeNote,
} from "./lib/knowledge.ts";

interface SearchResult {
  note: KnowledgeNote;
  score: number;
  excerpt: string;
  termHits: string[];
}

function usage(exitCode = 0): never {
  console.log(`MemoryRetriever - BM25-lite search over PAI/MEMORY/KNOWLEDGE

Usage:
  bun MemoryRetriever.ts "query terms" [--top 5] [--budget 1200] [--raw] [--json]

Options:
  --top N             Number of notes to return (default: 5)
  --budget N          Approximate output character budget (default: 1200)
  --raw               Return larger raw excerpts
  --json              Emit machine-readable JSON
  --knowledge-dir DIR Override KNOWLEDGE directory
`);
  process.exit(exitCode);
}

function parseArgs(args: string[]) {
  let top = 5;
  let budget = 1200;
  let raw = false;
  let json = false;
  let knowledgeDir: string | undefined;
  const queryParts: string[] = [];

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--help" || arg === "-h") usage(0);
    if (arg === "--top") {
      top = Number(args[++i]);
    } else if (arg === "--budget") {
      budget = Number(args[++i]);
    } else if (arg === "--raw") {
      raw = true;
    } else if (arg === "--json") {
      json = true;
    } else if (arg === "--knowledge-dir") {
      knowledgeDir = args[++i];
    } else if (arg.startsWith("--")) {
      console.error(`Unknown option: ${arg}`);
      usage(2);
    } else {
      queryParts.push(arg);
    }
  }

  const query = queryParts.join(" ").trim();
  if (!query) usage(2);

  return {
    query,
    top: Number.isFinite(top) && top > 0 ? top : 5,
    budget: Number.isFinite(budget) && budget > 0 ? budget : 1200,
    raw,
    json,
    knowledgeDir: getKnowledgeDir(knowledgeDir),
  };
}

function idf(term: string, documents: string[][]): number {
  const containing = documents.filter((doc) => doc.includes(term)).length;
  return Math.log(1 + (documents.length - containing + 0.5) / (containing + 0.5));
}

function bm25Score(queryTerms: string[], docTerms: string[], documents: string[][], avgDocLength: number): number {
  const k1 = 1.2;
  const b = 0.75;
  let score = 0;

  for (const term of queryTerms) {
    const tf = docTerms.filter((token) => token === term).length;
    if (!tf) continue;

    const denom = tf + k1 * (1 - b + b * (docTerms.length / Math.max(avgDocLength, 1)));
    score += idf(term, documents) * ((tf * (k1 + 1)) / denom);
  }

  return score;
}

function search(notes: KnowledgeNote[], query: string, top: number, raw: boolean, budget: number): SearchResult[] {
  const queryTerms = [...new Set(tokenize(query))];
  const documents = notes.map((note) => tokenize(noteText(note)));
  const avgDocLength = documents.reduce((sum, doc) => sum + doc.length, 0) / Math.max(documents.length, 1);

  return notes
    .map((note, index) => {
      const titleTerms = tokenize(note.title);
      const slugTerms = tokenize(note.slug);
      const termHits = queryTerms.filter((term) => documents[index].includes(term));
      let score = bm25Score(queryTerms, documents[index], documents, avgDocLength);

      for (const term of queryTerms) {
        if (titleTerms.includes(term)) score += 10;
        if (note.tags.includes(term)) score += 5;
        if (note.related.some((link) => link.slug.includes(term))) score += 3;
        if (slugTerms.includes(term) || note.slug.includes(term)) score += 4;
      }

      return {
        note,
        score,
        termHits,
        excerpt: excerptFor(note, queryTerms, raw ? Math.min(budget, 2000) : Math.min(420, budget)),
      };
    })
    .filter((result) => result.score > 0)
    .sort((a, b) => b.score - a.score || a.note.slug.localeCompare(b.note.slug))
    .slice(0, top);
}

function printText(query: string, results: SearchResult[], totalNotes: number, budget: number, raw: boolean) {
  if (totalNotes === 0) {
    console.log("empty archive: no markdown notes found in MEMORY/KNOWLEDGE");
    return;
  }

  if (results.length === 0) {
    console.log(`no matches for "${query}" across ${totalNotes} notes`);
    return;
  }

  console.log(`# Knowledge Retrieval: ${query}`);
  console.log(`Notes searched: ${totalNotes}`);
  console.log(`Results: ${results.length}`);
  console.log("");

  const perResultBudget = Math.max(180, Math.floor(budget / Math.max(results.length, 1)));
  for (const result of results) {
    const excerpt = raw ? result.excerpt : result.excerpt.slice(0, perResultBudget);
    console.log(`## ${result.note.title}`);
    console.log(`- slug: ${result.note.slug}`);
    console.log(`- path: ${result.note.relativePath}`);
    console.log(`- score: ${result.score.toFixed(3)}`);
    console.log(`- tags: ${result.note.tags.join(", ") || "(none)"}`);
    console.log("");
    if (excerpt) console.log(excerpt);
    console.log("");
  }
}

const options = parseArgs(process.argv.slice(2));
const notes = readKnowledgeNotes(options.knowledgeDir);
const results = search(notes, options.query, options.top, options.raw, options.budget);

if (options.json) {
  console.log(JSON.stringify({
    status: notes.length === 0 ? "empty_archive" : results.length === 0 ? "no_matches" : "ok",
    query: options.query,
    knowledge_dir: options.knowledgeDir,
    total_notes: notes.length,
    results: results.map((result) => ({
      slug: result.note.slug,
      title: result.note.title,
      type: result.note.type,
      domain: result.note.domain,
      tags: result.note.tags,
      path: result.note.relativePath,
      score: Number(result.score.toFixed(4)),
      term_hits: result.termHits,
      excerpt: result.excerpt,
    })),
  }, null, 2));
} else {
  printText(options.query, results, notes.length, options.budget, options.raw);
}
