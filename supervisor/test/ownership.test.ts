import { describe, expect, test } from "bun:test"
import { canonicalRoot, ownsSession } from "../src/ownership"

describe("canonicalRoot", () => {
  test("picks the longest configured root that is a path-boundary prefix", () => {
    expect(canonicalRoot("/a/b/x", ["/a", "/a/b"])).toBe("/a/b")
    expect(canonicalRoot("/a/b", ["/a", "/a/b"])).toBe("/a/b")
    expect(canonicalRoot("/a/x", ["/a", "/a/b"])).toBe("/a")
  })

  test("does not match a sibling sharing a name prefix", () => {
    expect(canonicalRoot("/a/bc", ["/a/b"])).toBeUndefined()
    expect(canonicalRoot("/a/bc/x", ["/a/b"])).toBeUndefined()
  })

  test("returns undefined when no configured root matches", () => {
    expect(canonicalRoot("/other/x", ["/a", "/a/b"])).toBeUndefined()
    expect(canonicalRoot("", ["/a"])).toBeUndefined()
  })

  test("tolerates trailing slashes on configured roots", () => {
    expect(canonicalRoot("/a/b/x", ["/a/", "/a/b/"])).toBe("/a/b/")
  })
})

describe("ownsSession", () => {
  test("the canonical root owns the session; a parent root does not", () => {
    expect(ownsSession("/a/b", "/a/b/x", ["/a", "/a/b"])).toBe(true)
    expect(ownsSession("/a", "/a/b/x", ["/a", "/a/b"])).toBe(false)
  })

  test("falls back to the listing root when no configured root matches", () => {
    expect(ownsSession("/a", "/worktree/bench", ["/a", "/a/b"])).toBe(true)
    expect(ownsSession("/a/b", "/worktree/bench", ["/a", "/a/b"])).toBe(true)
  })
})
