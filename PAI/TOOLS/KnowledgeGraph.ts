#!/usr/bin/env bun
import {
  buildKnowledgeGraph,
  excerptFor,
  getKnowledgeDir,
  readKnowledgeNotes,
  tokenize,
  type GraphEdge,
  type KnowledgeGraph,
  type KnowledgeNote,
} from "./lib/knowledge.ts";

function usage(exitCode = 0): never {
  console.log(`KnowledgeGraph - navigate PAI/MEMORY/KNOWLEDGE as an in-memory graph

Usage:
  bun KnowledgeGraph.ts stats [--json]
  bun KnowledgeGraph.ts find <query-or-tag> [--json]
  bun KnowledgeGraph.ts related <slug> [--json]
  bun KnowledgeGraph.ts traverse <slug> [--hops 2] [--json]

Options:
  --hops N            Traversal depth (default: 2)
  --json              Emit machine-readable JSON
  --knowledge-dir DIR Override KNOWLEDGE directory
`);
  process.exit(exitCode);
}

function parseArgs(args: string[]) {
  let command = "stats";
  let target = "";
  let hops = 2;
  let json = false;
  let knowledgeDir: string | undefined;
  const positional: string[] = [];

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--help" || arg === "-h") usage(0);
    if (arg === "--json") {
      json = true;
    } else if (arg === "--hops") {
      hops = Number(args[++i]);
    } else if (arg === "--knowledge-dir") {
      knowledgeDir = args[++i];
    } else if (arg.startsWith("--")) {
      console.error(`Unknown option: ${arg}`);
      usage(2);
    } else {
      positional.push(arg);
    }
  }

  if (positional.length > 0) command = positional[0];
  if (positional.length > 1) target = positional.slice(1).join(" ");

  return {
    command,
    target,
    hops: Number.isFinite(hops) && hops > 0 ? hops : 2,
    json,
    knowledgeDir: getKnowledgeDir(knowledgeDir),
  };
}

function notePayload(note: KnowledgeNote) {
  return {
    slug: note.slug,
    title: note.title,
    type: note.type,
    domain: note.domain,
    tags: note.tags,
    related: note.related,
    wikilinks: note.wikilinks,
    path: note.relativePath,
  };
}

function edgePayload(edge: GraphEdge) {
  return {
    source: edge.source,
    target: edge.target,
    type: edge.type,
    label: edge.label,
  };
}

function components(graph: KnowledgeGraph): string[][] {
  const seen = new Set<string>();
  const groups: string[][] = [];

  for (const note of graph.notes) {
    if (seen.has(note.slug)) continue;
    const group: string[] = [];
    const queue = [note.slug];
    seen.add(note.slug);

    while (queue.length > 0) {
      const slug = queue.shift()!;
      group.push(slug);
      for (const edge of graph.adjacency.get(slug) || []) {
        if (!seen.has(edge.target)) {
          seen.add(edge.target);
          queue.push(edge.target);
        }
      }
    }

    groups.push(group.sort());
  }

  return groups.sort((a, b) => b.length - a.length);
}

function stats(graph: KnowledgeGraph) {
  const groups = components(graph);
  const degrees = graph.notes
    .map((note) => ({
      slug: note.slug,
      title: note.title,
      degree: graph.adjacency.get(note.slug)?.length || 0,
      tags: note.tags,
    }))
    .sort((a, b) => b.degree - a.degree || a.slug.localeCompare(b.slug));

  return {
    status: graph.notes.length === 0 ? "empty_archive" : "ok",
    nodes: graph.notes.length,
    edges: graph.edges.length,
    components: groups.map((nodes) => ({ size: nodes.length, nodes })),
    hubs: degrees.filter((item) => item.degree > 0).slice(0, 10),
    isolated: degrees.filter((item) => item.degree === 0).map((item) => item.slug),
    missing_targets: graph.missingTargets.map(edgePayload),
  };
}

function find(graph: KnowledgeGraph, query: string) {
  const terms = tokenize(query);
  return graph.notes
    .map((note) => {
      let score = 0;
      for (const term of terms) {
        if (note.slug.includes(term)) score += 5;
        if (note.title.toLowerCase().includes(term)) score += 5;
        if (note.tags.includes(term)) score += 8;
        if (note.body.toLowerCase().includes(term)) score += 1;
      }
      return {
        ...notePayload(note),
        score,
        excerpt: excerptFor(note, terms, 260),
      };
    })
    .filter((note) => note.score > 0)
    .sort((a, b) => b.score - a.score || a.slug.localeCompare(b.slug));
}

function related(graph: KnowledgeGraph, slug: string) {
  const normalized = slug.toLowerCase();
  const note = graph.bySlug.get(normalized);
  if (!note) {
    return { status: "not_found", slug: normalized, related: [] };
  }

  const neighbors = new Map<string, { note: KnowledgeNote; edges: GraphEdge[] }>();
  for (const edge of graph.adjacency.get(note.slug) || []) {
    const target = graph.bySlug.get(edge.target);
    if (!target) continue;
    const entry = neighbors.get(edge.target) || { note: target, edges: [] };
    entry.edges.push(edge);
    neighbors.set(edge.target, entry);
  }

  return {
    status: "ok",
    note: notePayload(note),
    related: [...neighbors.values()]
      .map((entry) => ({
        ...notePayload(entry.note),
        edges: entry.edges.map(edgePayload),
      }))
      .sort((a, b) => b.edges.length - a.edges.length || a.slug.localeCompare(b.slug)),
  };
}

function traverse(graph: KnowledgeGraph, slug: string, maxHops: number) {
  const normalized = slug.toLowerCase();
  const start = graph.bySlug.get(normalized);
  if (!start) {
    return { status: "not_found", slug: normalized, nodes: [], edges: [] };
  }

  const visited = new Map<string, { depth: number; via?: GraphEdge }>();
  const queue: Array<{ slug: string; depth: number }> = [{ slug: start.slug, depth: 0 }];
  visited.set(start.slug, { depth: 0 });
  const traversedEdges: GraphEdge[] = [];

  while (queue.length > 0) {
    const current = queue.shift()!;
    if (current.depth >= maxHops) continue;

    for (const edge of graph.adjacency.get(current.slug) || []) {
      traversedEdges.push(edge);
      if (!visited.has(edge.target)) {
        visited.set(edge.target, { depth: current.depth + 1, via: edge });
        queue.push({ slug: edge.target, depth: current.depth + 1 });
      }
    }
  }

  return {
    status: "ok",
    start: notePayload(start),
    hops: maxHops,
    nodes: [...visited.entries()]
      .map(([nodeSlug, meta]) => ({
        ...notePayload(graph.bySlug.get(nodeSlug)!),
        depth: meta.depth,
        via: meta.via ? edgePayload(meta.via) : undefined,
      }))
      .sort((a, b) => a.depth - b.depth || a.slug.localeCompare(b.slug)),
    edges: traversedEdges.map(edgePayload),
  };
}

function printStats(data: ReturnType<typeof stats>) {
  if (data.status === "empty_archive") {
    console.log("empty archive: no markdown notes found in MEMORY/KNOWLEDGE");
    return;
  }
  console.log(`# Knowledge Graph Stats`);
  console.log(`Nodes: ${data.nodes}`);
  console.log(`Edges: ${data.edges}`);
  console.log(`Components: ${data.components.length}`);
  console.log(`Isolated: ${data.isolated.length}`);
  console.log("");
  console.log("## Hubs");
  for (const hub of data.hubs.slice(0, 10)) {
    console.log(`- ${hub.slug} (${hub.degree})`);
  }
}

function printList(title: string, items: Array<{ slug: string; title: string; path: string; score?: number; edges?: GraphEdge[]; depth?: number }>) {
  console.log(`# ${title}`);
  if (items.length === 0) {
    console.log("No matches.");
    return;
  }
  for (const item of items) {
    const extra = item.depth !== undefined ? ` depth=${item.depth}` : item.score !== undefined ? ` score=${item.score}` : "";
    console.log(`- ${item.slug}${extra} - ${item.title} (${item.path})`);
  }
}

const options = parseArgs(process.argv.slice(2));
const notes = readKnowledgeNotes(options.knowledgeDir);
const graph = buildKnowledgeGraph(notes);

let result: unknown;
switch (options.command) {
  case "stats":
    result = stats(graph);
    break;
  case "find":
    if (!options.target) usage(2);
    result = { status: notes.length === 0 ? "empty_archive" : "ok", query: options.target, results: find(graph, options.target) };
    break;
  case "related":
    if (!options.target) usage(2);
    result = related(graph, options.target);
    break;
  case "traverse":
    if (!options.target) usage(2);
    result = traverse(graph, options.target, options.hops);
    break;
  default:
    console.error(`Unknown command: ${options.command}`);
    usage(2);
}

if (options.json) {
  console.log(JSON.stringify(result, null, 2));
} else if (options.command === "stats") {
  printStats(result as ReturnType<typeof stats>);
} else if (options.command === "find") {
  const data = result as { status: string; query: string; results: ReturnType<typeof find> };
  if (data.status === "empty_archive") {
    console.log("empty archive: no markdown notes found in MEMORY/KNOWLEDGE");
  } else {
    printList(`Find: ${data.query}`, data.results);
  }
} else if (options.command === "related") {
  const data = result as ReturnType<typeof related>;
  if (data.status !== "ok") {
    console.log(`not found: ${data.slug}`);
  } else {
    printList(`Related: ${data.note.title}`, data.related);
  }
} else if (options.command === "traverse") {
  const data = result as ReturnType<typeof traverse>;
  if (data.status !== "ok") {
    console.log(`not found: ${data.slug}`);
  } else {
    printList(`Traverse: ${data.start.title}`, data.nodes);
  }
}
