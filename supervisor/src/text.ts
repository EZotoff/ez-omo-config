/** Bound operator-answer propagation text at a sentence boundary.
 *
 * The propagation is a prompt into a worker session: cutting it mid-sentence
 * (the old `slice(0, 500)`) left workers with truncated non-answers. If the
 * text fits the limit it is returned unchanged; otherwise it is cut at the
 * last sentence terminator (., !, ?, or newline) before the limit. A text with
 * no terminator before the limit is cut at the last whitespace so no word is
 * split; a single uninterrupted run longer than the limit is hard-cut. */
export function truncateAtSentence(text: string, limit: number): string {
  if (text.length <= limit) return text
  const head = text.slice(0, limit)
  const sentence = Math.max(head.lastIndexOf("."), head.lastIndexOf("!"), head.lastIndexOf("?"), head.lastIndexOf("\n"))
  if (sentence >= Math.floor(limit * 0.5)) return text.slice(0, sentence + 1)
  const space = head.lastIndexOf(" ")
  if (space > 0) return text.slice(0, space)
  return head
}
