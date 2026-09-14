#!/usr/bin/env node
// Report-only prose lint. Never rewrites files.
//
// Modes:
//   default            -> `--` pseudo-dashes + anti-slop patterns
//   --profile zero-em-dash -> em-dash characters (U+2014/U+2015/U+2013) + `--`
//
// Exemptions (both modes): blockquote lines (`>`), fenced code blocks, and
// inline backtick spans. Quoted/source text is preserved verbatim.
//
// Output: one `file:line: pattern` finding per line. Exit 1 on findings,
// 0 when clean, 2 on usage error (unknown flag, missing file, no input).

import { readFileSync, existsSync } from 'node:fs'

const USAGE =
  'Usage: check-prose.mjs [--profile zero-em-dash] <file> [file...]\n' +
  '  default mode: pseudo-dashes + anti-slop patterns\n' +
  '  --profile zero-em-dash: em-dash characters + pseudo-dashes'

const EM_DASH = /[\u2014\u2015\u2013]/
const PSEUDO_DASH = /--/

// Anti-slop patterns (default mode only). Tags are short and machine-readable.
const SLOP = [
  { tag: 'slop:leverag', re: /leverag/i },
  { tag: 'slop:utiliz', re: /utiliz/i },
  { tag: 'slop:facilitat', re: /facilitat/i },
  { tag: 'slop:enables-seamless', re: /enables seamless/i },
  { tag: 'slop:harness', re: /\bharness(?:es|ed|ing)?\b/i },
  { tag: 'slop:empower', re: /\bempower/i },
  { tag: 'slop:delve-into', re: /delve into/i },
  { tag: 'slop:tapestry', re: /\btapestry/i },
  { tag: 'slop:seamlessly', re: /\bseamlessly/i },
  { tag: 'slop:realm', re: /\brealm/i },
  { tag: 'slop:landscape', re: /the landscape of/i },
  { tag: 'slop:throat-clearing', re: /it is (?:important|worth) (?:to )?(?:note|mention)/i },
  { tag: 'slop:opener-furthermore', re: /^\s*furthermore\s*,/i },
  { tag: 'slop:opener-moreover', re: /^\s*moreover\s*,/i },
]

function usage() {
  process.stderr.write(USAGE + '\n')
  process.exit(2)
}

// Remove inline code spans so their contents are never linted.
function stripInlineCode(line) {
  return line.replace(/``[^`]*``/g, ' ').replace(/`[^`]*`/g, ' ')
}

function lintFile(file, mode) {
  const lines = readFileSync(file, 'utf8').split(/\r?\n/)
  const findings = []
  let inFence = false

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i]

    if (/^\s*```/.test(raw)) {
      inFence = !inFence
      continue
    }
    if (inFence) continue
    if (/^\s*>/.test(raw)) continue

    const line = stripInlineCode(raw)
    const tags = []

    if (PSEUDO_DASH.test(line)) tags.push('pseudo-dash')
    if (mode === 'zero-em-dash' && EM_DASH.test(line)) tags.push('em-dash')
    if (mode === 'default') {
      for (const { tag, re } of SLOP) {
        if (re.test(line)) tags.push(tag)
      }
    }

    for (const tag of tags) findings.push(`${file}:${i + 1}: ${tag}`)
  }

  return findings
}

function main() {
  const args = process.argv.slice(2)
  let mode = 'default'
  const files = []

  for (let i = 0; i < args.length; i++) {
    const arg = args[i]
    if (arg === '--profile') {
      if (args[++i] !== 'zero-em-dash') usage()
      mode = 'zero-em-dash'
    } else if (arg.startsWith('--profile=')) {
      if (arg.slice('--profile='.length) !== 'zero-em-dash') usage()
      mode = 'zero-em-dash'
    } else if (arg.startsWith('-')) {
      usage()
    } else {
      files.push(arg)
    }
  }

  if (files.length === 0) usage()

  for (const file of files) {
    if (!existsSync(file)) usage()
  }

  const findings = files.flatMap((file) => lintFile(file, mode))

  if (findings.length > 0) {
    process.stdout.write(findings.join('\n') + '\n')
    process.exit(1)
  }
  process.exit(0)
}

main()
