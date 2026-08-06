// tests/git-safety/harness.ts
// Unit tests for the pure helpers exported by plugins/git-safety.ts __test__.
//
// These run via `bun test` (see tests/test_git_safety_runtime.sh).
// Putting the destructive-command strings inside this file (not inside a
// bash command) is deliberate: the git-safety plugin intercepts bash
// commands that contain `git reset --hard` etc., so the smoke test must
// run from a file, not from `bun -e '...git reset --hard...'`.

import { test, describe, it, expect } from "bun:test"
import { __test__ } from "../../plugins/git-safety.ts"

const { parseLeadingCd, resolveWorkdir, detectHistoryRewriteCommand } = __test__

const HOME = process.env.HOME ?? "/home/test"

describe("parseLeadingCd", () => {
  it("parses absolute path with &&", () => {
    expect(parseLeadingCd("cd /tmp && git status")).toBe("/tmp")
  })
  it("parses absolute path with ;", () => {
    expect(parseLeadingCd("cd /tmp; git status")).toBe("/tmp")
  })
  it("parses absolute path with newline", () => {
    expect(parseLeadingCd("cd /tmp\ngit status")).toBe("/tmp")
  })
  it("parses absolute path at end of command", () => {
    expect(parseLeadingCd("cd /tmp")).toBe("/tmp")
  })
  it("parses double-quoted path with spaces", () => {
    expect(parseLeadingCd('cd "/path with spaces" && git status')).toBe("/path with spaces")
  })
  it("parses single-quoted path with spaces", () => {
    expect(parseLeadingCd("cd '/path with spaces' && git status")).toBe("/path with spaces")
  })
  it("expands tilde", () => {
    expect(parseLeadingCd("cd ~/workdir && git status")).toBe(`${HOME}/workdir`)
  })
  it("rejects relative path (falls through to fallback)", () => {
    expect(parseLeadingCd("cd workdir && git status")).toBeUndefined()
  })
  it("returns undefined for non-cd command", () => {
    expect(parseLeadingCd("git status")).toBeUndefined()
  })
  it("returns undefined for empty string", () => {
    expect(parseLeadingCd("")).toBeUndefined()
  })
})

describe("resolveWorkdir", () => {
  it("uses explicit workdir arg first", () => {
    expect(resolveWorkdir({ workdir: "/wt", command: "git status" }, "/fb")).toBe("/wt")
  })
  it("expands tilde in workdir arg", () => {
    expect(resolveWorkdir({ workdir: "~/wt", command: "git" }, "/fb")).toBe(`${HOME}/wt`)
  })
  it("falls back to leading cd when workdir absent", () => {
    expect(resolveWorkdir({ workdir: undefined, command: "cd /wt && git status" }, "/fb")).toBe("/wt")
  })
  it("falls back to ctx.directory when nothing else resolves", () => {
    expect(resolveWorkdir({ workdir: undefined, command: "git status" }, "/ctx")).toBe("/ctx")
  })
  it("ignores empty string workdir", () => {
    expect(resolveWorkdir({ workdir: "", command: "git" }, "/ctx")).toBe("/ctx")
  })
  it("ignores non-string workdir", () => {
    expect(resolveWorkdir({ workdir: 42, command: "git" }, "/ctx")).toBe("/ctx")
  })
})

describe("detectHistoryRewriteCommand", () => {
  describe("the veran incident + neighbors", () => {
    // The veran reflog showed: agent committed, ran `git revert` x2, then
    // `git reset --hard 8e69813e` to discard the reverts. detectResetRewrite
    // (async) catches the reset; detectHistoryRewriteCommand (sync) catches
    // the sibling patterns below.
    it("does NOT sync-catch `git reset --hard <sha>` (handled by detectResetRewrite async)", () => {
      expect(detectHistoryRewriteCommand("git reset --hard 8e69813e")).toBeUndefined()
    })
  })

  describe("patterns that MUST sync-block", () => {
    const cases: Array<[string, string]> = [
      ['git commit --amend -m "x"', "amend"],
      ['git commit --amend --no-edit', "amend"],
      ["git rebase main", "rebase"],
      ["git rebase -i HEAD~3", "rebase"],
      ["git rebase --onto main feat/x", "rebase"],
      ["git push --force origin main", "force"],
      ["git push -f origin main", "-f"],
      ["git push --force-with-lease origin main", "force-with-lease"],
      ["git branch -D feat/x", "branch -D"],
      ["git stash clear", "stash clear"],
      ["git reflog expire --expire=now --all", "reflog expire"],
      ["git gc --prune=now", "--prune"],
      ["git gc --aggressive --prune=now", "--prune"],
    ]
    for (const [cmd, want] of cases) {
      it(`blocks: ${cmd}`, () => {
        const got = detectHistoryRewriteCommand(cmd)?.description ?? ""
        expect(got).toContain(want)
      })
    }
  })

  describe("safe commands that must NOT block", () => {
    const cases = [
      'git commit -m "normal commit"',
      "git push origin main",
      "git status",
      "git log --oneline",
      "git rebase --abort",
      "git rebase --continue",
      "git rebase --skip",
      "git stash push -m \"wip\"",
      "git stash pop",
      "git branch -d feat/x", // lowercase -d (safe delete, errors if unmerged)
      "git gc", // no --prune
      "git reflog show",
    ]
    for (const cmd of cases) {
      it(`allows: ${cmd}`, () => {
        expect(detectHistoryRewriteCommand(cmd)).toBeUndefined()
      })
    }
  })
})
