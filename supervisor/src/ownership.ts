/** Canonical session→root ownership (design 1, cluster C). Pure path logic: a session
 *  belongs to the longest configured root that is a path-boundary prefix of its
 *  directory, so nested roots (e.g. /a and /a/b) never double-judge the same session. */

const normalize = (path: string): string => (path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path)

/** Longest configured root that is a path-boundary prefix of `directory`, or undefined
 *  when no configured root matches. Trailing-separator compare: /a/b does not match /a/bc. */
export function canonicalRoot(directory: string, roots: readonly string[]): string | undefined {
  const target = normalize(directory)
  let best: string | undefined
  let bestLength = -1
  for (const root of roots) {
    const candidate = normalize(root)
    const prefix = candidate === "/" ? "/" : `${candidate}/`
    if ((target === candidate || target.startsWith(prefix)) && candidate.length > bestLength) {
      best = root
      bestLength = candidate.length
    }
  }
  return best
}

/** True when `root` owns a session whose `directory` is `directory`. Falls back to the
 *  listing root when no configured root matches (bench-worktree sessions live outside
 *  every configured root and must keep their current owner). */
export function ownsSession(root: string, directory: string, roots: readonly string[]): boolean {
  const canonical = canonicalRoot(directory, roots)
  return canonical === undefined || canonical === root
}
