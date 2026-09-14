#!/usr/bin/env node
// check-web-type.mjs — report-only web typography risk scanner (zero dependencies).
//
// Scans .css files and .html files (including inline <style> blocks) for four
// defect classes and prints one finding per line as `file:line: <CLASS-TAG>`:
//
//   px-body-copy             font-size in px/vw on a body-copy-likely selector
//                            with no rem counterpart in the same declaration/rule
//   zoom-lock                viewport meta disables zoom (user-scalable=no,
//                            maximum-scale=1)
//   fvs-out-of-range         font-variation-settings numeric axis outside 0-1000
//   motion-no-reduced-motion transition on a type property in a file with no
//                            prefers-reduced-motion block
//
// Usage: check-web-type.mjs <file.css|file.html> [...]
// Exit:  0 clean, 1 findings, 2 usage error.

import { readFileSync, existsSync, statSync } from "node:fs";
import { extname } from "node:path";

const USAGE = `Usage: check-web-type.mjs <file.css|file.html> [...]
Report-only scanner for web typography risks. Exits 1 when findings exist.`;

const TYPE_PROPS = ["font-variation-settings", "font-weight", "letter-spacing", "word-spacing"];
const HAS_PX_VW = /\d(?:px|vw)\b/i;
const HAS_REM = /\drem\b/i;

function fail(msg) {
  process.stderr.write(`check-web-type: ${msg}\n${USAGE}\n`);
  process.exit(2);
}

// Blank out comment bodies while preserving newlines, so line numbers stay valid.
function stripComments(text, kind) {
  const re = kind === "html" ? /<!--[\s\S]*?-->/g : /\/\*[\s\S]*?\*\//g;
  return text.replace(re, (m) => m.replace(/[^\n]/g, " "));
}

function makeLineOf(text) {
  const starts = [0];
  for (let i = 0; i < text.length; i++) if (text[i] === "\n") starts.push(i + 1);
  return (idx) => {
    let lo = 0;
    let hi = starts.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (starts[mid] <= idx) lo = mid;
      else hi = mid - 1;
    }
    return lo + 1;
  };
}

// Body-copy-likely heuristic: the rule's selector text mentions `body`, `.prose`,
// or contains a bare `p` element selector (p, p.foo, article p, p:hover, ...).
function isBodyCopySelector(selector) {
  if (/\bbody\b/.test(selector)) return true;
  if (/\.prose\b/.test(selector)) return true;
  return /(^|[\s,>+~])p(?=[\s,{.:#>+~\[]|$)/.test(selector);
}

// Scan CSS text (a .css file or the concatenated <style> blocks of an .html file).
function scanCss(text) {
  const lineOf = makeLineOf(text);
  const findings = [];
  const hasReducedMotion = /prefers-reduced-motion/.test(text);
  const ruleRe = /([^{}]+)\{([^{}]*)\}/g;
  let m;
  while ((m = ruleRe.exec(text)) !== null) {
    const selector = m[1].trim();
    const body = m[2];
    const bodyStart = m.index + m[1].length + 1;

    // (a) px/vw font-size on body-copy-likely selectors without a rem counterpart.
    if (isBodyCopySelector(selector)) {
      const declRe = /font-size\s*:\s*([^;}]+)/g;
      const decls = [];
      let d;
      while ((d = declRe.exec(body)) !== null) {
        decls.push({ value: d[1].trim(), idx: bodyStart + d.index });
      }
      const ruleHasRem = decls.some((x) => HAS_REM.test(x.value));
      for (const decl of decls) {
        if (HAS_PX_VW.test(decl.value) && !HAS_REM.test(decl.value) && !ruleHasRem) {
          findings.push({ line: lineOf(decl.idx), tag: "px-body-copy" });
        }
      }
    }

    // (c) font-variation-settings numeric axis outside 0-1000.
    const fvsRe = /font-variation-settings\s*:\s*([^;}]+)/g;
    let f;
    while ((f = fvsRe.exec(body)) !== null) {
      const axisRe = /["']([A-Za-z0-9]{4})["']\s+(-?\d+(?:\.\d+)?)/g;
      let a;
      while ((a = axisRe.exec(f[1])) !== null) {
        const num = Number(a[2]);
        if (num < 0 || num > 1000) {
          findings.push({ line: lineOf(bodyStart + f.index), tag: "fvs-out-of-range" });
        }
      }
    }

    // (d) motion transition on type properties, gated per-file by reduced-motion.
    if (!hasReducedMotion) {
      const trRe = /(?:^|[;{\s])(transition(?:-property)?)\s*:\s*([^;}]+)/g;
      let t;
      while ((t = trRe.exec(body)) !== null) {
        if (TYPE_PROPS.some((p) => t[2].includes(p))) {
          findings.push({ line: lineOf(bodyStart + t.index), tag: "motion-no-reduced-motion" });
        }
      }
    }
  }
  return findings;
}

// Blank everything except <style> block contents, preserving offsets/newlines.
function extractStyleText(text) {
  const chars = text.replace(/[^\n]/g, " ").split("");
  const re = /<style\b[^>]*>([\s\S]*?)<\/style>/gi;
  let m;
  while ((m = re.exec(text)) !== null) {
    const start = m.index + m[0].indexOf(">") + 1;
    for (let i = 0; i < m[1].length; i++) chars[start + i] = m[1][i];
  }
  return chars.join("");
}

function scanHtml(text) {
  const findings = [];
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (
      /user-scalable\s*=\s*["']?no["']?/i.test(line) ||
      /maximum-scale\s*=\s*["']?1["']?(?![\d.])/i.test(line)
    ) {
      findings.push({ line: i + 1, tag: "zoom-lock" });
    }
  }
  findings.push(...scanCss(extractStyleText(text)));
  return findings;
}

function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) fail("no input files");

  const findings = [];
  for (const arg of args) {
    if (arg.startsWith("-")) fail(`unknown option: ${arg}`);
    if (!existsSync(arg) || !statSync(arg).isFile()) fail(`no such file: ${arg}`);
    const ext = extname(arg).toLowerCase();
    if (ext !== ".css" && ext !== ".html" && ext !== ".htm") continue;
    let raw;
    try {
      raw = readFileSync(arg, "utf8");
    } catch (err) {
      fail(`cannot read ${arg}: ${err.message}`);
    }
    const text = stripComments(raw, ext === ".css" ? "css" : "html");
    const fileFindings = ext === ".css" ? scanCss(text) : scanHtml(text);
    for (const f of fileFindings) findings.push({ file: arg, ...f });
  }

  findings.sort(
    (a, b) => a.file.localeCompare(b.file) || a.line - b.line || a.tag.localeCompare(b.tag),
  );
  for (const f of findings) process.stdout.write(`${f.file}:${f.line}: ${f.tag}\n`);
  process.exitCode = findings.length > 0 ? 1 : 0;
}

main();
