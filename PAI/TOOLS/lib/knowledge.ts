import { existsSync, readdirSync, readFileSync, statSync } from "fs";
import { basename, dirname, join, relative } from "path";

export interface RelatedLink {
  slug: string;
  type: string;
}

export interface KnowledgeNote {
  slug: string;
  title: string;
  domain: string;
  type: string;
  tags: string[];
  related: RelatedLink[];
  wikilinks: string[];
  path: string;
  relativePath: string;
  body: string;
  frontmatter: string;
  status?: string;
  quality?: number;
  updated?: string;
}

export interface GraphEdge {
  source: string;
  target: string;
  type: string;
  label?: string;
}

export interface KnowledgeGraph {
  notes: KnowledgeNote[];
  bySlug: Map<string, KnowledgeNote>;
  edges: GraphEdge[];
  adjacency: Map<string, GraphEdge[]>;
  missingTargets: GraphEdge[];
}

export function getPaiDir(): string {
  return process.env.PAI_DIR || join(process.env.HOME || "", ".config", "opencode", "PAI");
}

export function getKnowledgeDir(explicit?: string): string {
  return explicit || process.env.KNOWLEDGE_DIR || join(getPaiDir(), "MEMORY", "KNOWLEDGE");
}

export function normalizeSlug(value: string): string {
  return value
    .trim()
    .replace(/\.md$/i, "")
    .replace(/^.*\//, "")
    .toLowerCase();
}

export function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, " ")
    .split(/\s+/)
    .filter((token) => token.length > 1);
}

export function unique<T>(items: T[]): T[] {
  return [...new Set(items)];
}

function stripQuotes(value: string): string {
  return value.trim().replace(/^['"]|['"]$/g, "");
}

function findMarkdownFiles(root: string): string[] {
  if (!existsSync(root)) return [];

  const files: string[] = [];
  const walk = (dir: string) => {
    for (const entry of readdirSync(dir)) {
      if (entry === "node_modules") continue;
      if (entry.startsWith("_")) continue;

      const path = join(dir, entry);
      const stats = statSync(path);
      if (stats.isDirectory()) {
        walk(path);
      } else if (stats.isFile() && entry.endsWith(".md")) {
        files.push(path);
      }
    }
  };

  walk(root);
  return files.sort();
}

function splitFrontmatter(content: string): { frontmatter: string; body: string } {
  if (!content.startsWith("---")) {
    return { frontmatter: "", body: content };
  }

  const end = content.indexOf("\n---", 3);
  if (end === -1) {
    return { frontmatter: "", body: content };
  }

  const afterEnd = content.indexOf("\n", end + 4);
  return {
    frontmatter: content.slice(3, end).trim(),
    body: afterEnd === -1 ? "" : content.slice(afterEnd + 1),
  };
}

function scalar(frontmatter: string, key: string): string | undefined {
  const match = frontmatter.match(new RegExp(`^${key}:[ \\t]*(.+)$`, "im"));
  return match ? stripQuotes(match[1]) : undefined;
}

function blockFor(frontmatter: string, key: string): string[] {
  const lines = frontmatter.split(/\r?\n/);
  const start = lines.findIndex((line) => new RegExp(`^${key}:\\s*$`, "i").test(line));
  if (start === -1) return [];

  const block: string[] = [];
  for (let i = start + 1; i < lines.length; i++) {
    const line = lines[i];
    if (/^[A-Za-z0-9_-]+:\s*/.test(line)) break;
    block.push(line);
  }
  return block;
}

function arrayValue(frontmatter: string, key: string): string[] {
  const inline = scalar(frontmatter, key);
  if (inline) {
    if (inline.startsWith("[") && inline.endsWith("]")) {
      return inline
        .slice(1, -1)
        .split(",")
        .map(stripQuotes)
        .filter(Boolean);
    }
    return inline
      .split(",")
      .map(stripQuotes)
      .filter(Boolean);
  }

  return blockFor(frontmatter, key)
    .map((line) => line.match(/^\s*-\s*(.+)$/)?.[1])
    .filter((value): value is string => Boolean(value))
    .map(stripQuotes);
}

function relatedValue(frontmatter: string): RelatedLink[] {
  const block = blockFor(frontmatter, "related");
  const related: RelatedLink[] = [];
  let current: Partial<RelatedLink> | null = null;

  for (const line of block) {
    const itemSlug = line.match(/^\s*-\s*slug:\s*(.+)$/i)?.[1];
    if (itemSlug) {
      if (current?.slug) {
        related.push({ slug: normalizeSlug(current.slug), type: current.type || "related" });
      }
      current = { slug: stripQuotes(itemSlug), type: "related" };
      continue;
    }

    const inline = line.match(/^\s*-\s*(.+)$/)?.[1];
    if (inline && !inline.includes(":")) {
      if (current?.slug) {
        related.push({ slug: normalizeSlug(current.slug), type: current.type || "related" });
      }
      current = { slug: stripQuotes(inline), type: "related" };
      continue;
    }

    const type = line.match(/^\s*type:\s*(.+)$/i)?.[1];
    if (type && current) {
      current.type = stripQuotes(type);
    }
  }

  if (current?.slug) {
    related.push({ slug: normalizeSlug(current.slug), type: current.type || "related" });
  }

  return related;
}

function wikilinks(body: string): string[] {
  const links: string[] = [];
  const pattern = /\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]/g;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(body))) {
    links.push(normalizeSlug(match[1]));
  }
  return unique(links);
}

export function readKnowledgeNotes(knowledgeDir = getKnowledgeDir()): KnowledgeNote[] {
  return findMarkdownFiles(knowledgeDir).map((path) => {
    const content = readFileSync(path, "utf-8");
    const { frontmatter, body } = splitFrontmatter(content);
    const slug = normalizeSlug(scalar(frontmatter, "slug") || basename(path, ".md"));
    const domain = basename(dirname(path));
    const type = stripQuotes(scalar(frontmatter, "type") || domain);

    return {
      slug,
      title: stripQuotes(scalar(frontmatter, "title") || scalar(frontmatter, "name") || slug),
      domain,
      type,
      tags: unique(arrayValue(frontmatter, "tags").map(normalizeSlug)),
      related: relatedValue(frontmatter),
      wikilinks: wikilinks(body),
      path,
      relativePath: relative(knowledgeDir, path),
      body,
      frontmatter,
      status: scalar(frontmatter, "status"),
      quality: Number(scalar(frontmatter, "quality")) || undefined,
      updated: scalar(frontmatter, "updated"),
    };
  });
}

function edgeKey(edge: GraphEdge): string {
  const pair = [edge.source, edge.target].sort().join("::");
  return `${pair}::${edge.type}::${edge.label || ""}`;
}

export function buildKnowledgeGraph(notes: KnowledgeNote[]): KnowledgeGraph {
  const bySlug = new Map(notes.map((note) => [note.slug, note]));
  const edgeMap = new Map<string, GraphEdge>();
  const missingTargets: GraphEdge[] = [];

  const addEdge = (source: string, target: string, type: string, label?: string) => {
    if (source === target) return;

    const edge: GraphEdge = { source, target, type, label };
    if (!bySlug.has(target)) {
      missingTargets.push(edge);
      return;
    }

    edgeMap.set(edgeKey(edge), edge);
  };

  for (const note of notes) {
    for (const related of note.related) {
      addEdge(note.slug, related.slug, related.type || "related");
    }
    for (const link of note.wikilinks) {
      addEdge(note.slug, link, "wikilink");
    }
  }

  const byTag = new Map<string, string[]>();
  for (const note of notes) {
    for (const tag of note.tags) {
      const peers = byTag.get(tag) || [];
      peers.push(note.slug);
      byTag.set(tag, peers);
    }
  }

  for (const [tag, slugs] of byTag.entries()) {
    for (let i = 0; i < slugs.length; i++) {
      for (let j = i + 1; j < slugs.length; j++) {
        addEdge(slugs[i], slugs[j], "tag", tag);
      }
    }
  }

  const edges = [...edgeMap.values()].sort((a, b) =>
    `${a.source}:${a.target}:${a.type}`.localeCompare(`${b.source}:${b.target}:${b.type}`),
  );
  const adjacency = new Map<string, GraphEdge[]>();
  for (const note of notes) {
    adjacency.set(note.slug, []);
  }
  for (const edge of edges) {
    adjacency.get(edge.source)?.push(edge);
    adjacency.get(edge.target)?.push({ ...edge, source: edge.target, target: edge.source });
  }

  return { notes, bySlug, edges, adjacency, missingTargets };
}

export function noteText(note: KnowledgeNote): string {
  return `${note.title}\n${note.tags.join(" ")}\n${note.related.map((r) => r.slug).join(" ")}\n${note.body}`;
}

export function excerptFor(note: KnowledgeNote, terms: string[], maxChars: number): string {
  const normalizedBody = note.body.replace(/\s+/g, " ").trim();
  if (!normalizedBody) return "";

  const lower = normalizedBody.toLowerCase();
  const term = terms.find((candidate) => lower.includes(candidate.toLowerCase()));
  const index = term ? lower.indexOf(term.toLowerCase()) : 0;
  const start = Math.max(0, index - Math.floor(maxChars / 3));
  const excerpt = normalizedBody.slice(start, start + maxChars).trim();
  return `${start > 0 ? "..." : ""}${excerpt}${start + maxChars < normalizedBody.length ? "..." : ""}`;
}
