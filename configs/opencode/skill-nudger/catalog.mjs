// configs/opencode/skill-nudger/catalog.mjs
// Skill catalog — built-in skill table + user skill frontmatter scan

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// Built-in skills shipped with OpenCode (names + short descriptions).
// Static table: builtin skills have no SKILL.md on disk to scan.
const BUILTIN_SKILLS = [
  { name: "agent-browser", description: "Browser automation via agent-browser CLI" },
  { name: "frontend", description: "Frontend/web UI/UX/visual work rulesets" },
  { name: "git-master", description: "Git operations: commits, rebase, history search" },
  { name: "review-work", description: "Post-implementation review orchestration" },
  { name: "remove-ai-slops", description: "Remove AI-generated code smells" },
  { name: "init-deep", description: "Initialize hierarchical AGENTS.md knowledge base" },
  { name: "debugging", description: "Runtime debugging loop: hypotheses, root cause, fix, QA" },
  { name: "security-research", description: "Vulnerability audit with PoC engineers" },
  { name: "security-review", description: "Alias for security-research" },
  { name: "visual-qa", description: "Visual QA for UI/TUI with screenshot evidence" },
  { name: "team-mode", description: "Parallel agent team orchestration" },
  { name: "ast-grep", description: "AST-aware code search and rewrite" },
  { name: "ulw-plan", description: "Explore-first planning consultant" },
  { name: "programming", description: "Strict-type coding standards for py/rs/ts/go" },
  { name: "refactor", description: "Intelligent refactor command" },
  { name: "lsp-setup", description: "Configure language servers" },
  { name: "start-work", description: "Execute a Prometheus work plan" },
  { name: "ultimate-browsing", description: "Escalation skill for blocked web access" },
  { name: "coding-agent-sessions", description: "Find and read coding-agent session logs" },
];

const USER_SKILLS_DIR = join(homedir(), ".config", "opencode", "skills");

function parseFrontmatter(text) {
  const match = /^---\n([\s\S]*?)\n---/.exec(text);
  if (!match) return {};
  const out = {};
  for (const line of match[1].split("\n")) {
    const m = /^([A-Za-z_][\w-]*)\s*:\s*(.*)$/.exec(line);
    if (m) out[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
  return out;
}

function loadUserSkills() {
  const skills = [];
  try {
    if (!existsSync(USER_SKILLS_DIR)) return skills;
    for (const entry of readdirSync(USER_SKILLS_DIR, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const skillPath = join(USER_SKILLS_DIR, entry.name, "SKILL.md");
      try {
        if (!existsSync(skillPath)) continue;
        const fm = parseFrontmatter(readFileSync(skillPath, "utf8"));
        skills.push({
          name: fm.name ?? entry.name,
          description: fm.description ?? "",
          source: "user",
        });
      } catch {
        // Unreadable skill file — skip silently
      }
    }
  } catch {
    // Unreadable skills dir — return what we have
  }
  return skills;
}

export function loadCatalog() {
  const byName = new Map();
  for (const s of BUILTIN_SKILLS) byName.set(s.name, { ...s, source: "builtin" });
  for (const s of loadUserSkills()) byName.set(s.name, s);
  return byName;
}

export function getSkill(catalog, name) {
  if (!name) return null;
  return catalog.get(name) ?? { name, description: "", source: "unknown" };
}
