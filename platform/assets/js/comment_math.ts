import katex from "katex"

export function renderCommentMath(root: HTMLElement): void {
  for (const node of root.querySelectorAll<HTMLElement>(
    "[data-math-style]:not([data-math-rendered])",
  )) {
    const source = node.textContent || ""
    try {
      katex.render(source, node, {
        displayMode: node.dataset.mathStyle === "display",
        output: "htmlAndMathml",
        trust: false,
        throwOnError: false,
        strict: "error",
        maxExpand: 1000,
        maxSize: 12,
        // Each expression owns its macros; one comment cannot change another.
        macros: {},
      })
    } catch {
      node.textContent = source
    }
    node.dataset.mathRendered = "true"
  }
}
