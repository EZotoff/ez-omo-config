import { machineWriterPatterns } from "./patterns"

/**
 * Autonomous-origin classification (ISS-08 / ISS-18). A session is autonomous
 * when it was machine-initiated and has no human owner — bench-runner judge
 * sessions, ASTRA research kickoffs, heartbeat workers. Operator-attention
 * semantics misfire on these: they must be driven to completion, not escalated.
 *
 * Signals (any one fires):
 *   (a) session directory matches a configured path glob,
 *   (b) session title matches a configured prefix,
 *   (c) the kickoff text matches the existing astra-automation pattern.
 */
export type AutonomousOriginConfig = {
  readonly pathGlobs: readonly string[]
  readonly titlePrefixes: readonly string[]
}

export type AutonomousOriginInput = {
  readonly directory: string
  readonly title?: string
  /** First user message text of the session (kickoff), when available. */
  readonly kickoffText?: string
}

export const AUTONOMOUS_ORIGIN_LABEL = "[origin: autonomous]"

const ASTRA_WRITER = "astra-automation"

/**
 * The ASTRA autonomous-research kickoff regex already lives in patterns.ts
 * (writer "astra-automation"). Reuse it verbatim — never duplicate the pattern.
 */
const astraKickoff = machineWriterPatterns.find((entry) => entry.writer === ASTRA_WRITER)

export function matchesAstraKickoff(text: string): boolean {
  return astraKickoff !== undefined && astraKickoff.regex.test(text)
}

const escapeLiteral = (text: string): string => text.replace(/[.+^${}()|[\]\\]/g, "\\$&")

/**
 * Glob → anchored RegExp. `**` spans path separators; `*`/`?` stay within one
 * segment. `**\/` matches zero or more leading segments, so `**\/benchmarks/**`
 * matches both `benchmarks/x` and `/home/u/benchmarks/x`.
 */
export function globToRegExp(glob: string): RegExp {
  let out = "^"
  for (let index = 0; index < glob.length; index += 1) {
    const char = glob[index]!
    if (char === "*") {
      if (glob[index + 1] === "*") {
        index += 1
        if (glob[index + 1] === "/") {
          index += 1
          out += "(?:[^/]*/)*"
        } else {
          out += ".*"
        }
      } else {
        out += "[^/]*"
      }
    } else if (char === "?") {
      out += "[^/]"
    } else {
      out += escapeLiteral(char)
    }
  }
  return new RegExp(`${out}$`)
}

export function matchesPathGlob(directory: string, globs: readonly string[]): boolean {
  return globs.some((glob) => globToRegExp(glob).test(directory))
}

export function matchesTitlePrefix(title: string | undefined, prefixes: readonly string[]): boolean {
  if (title === undefined) return false
  return prefixes.some((prefix) => title.startsWith(prefix))
}

export function classifyAutonomousOrigin(input: AutonomousOriginInput, config: AutonomousOriginConfig): boolean {
  if (matchesPathGlob(input.directory, config.pathGlobs)) return true
  if (matchesTitlePrefix(input.title, config.titlePrefixes)) return true
  if (input.kickoffText !== undefined && matchesAstraKickoff(input.kickoffText)) return true
  return false
}
