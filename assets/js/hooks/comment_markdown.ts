type Context = {el: HTMLElement}

async function renderMath({el}: Context): Promise<void> {
  if (!el.querySelector("[data-math-style]:not([data-math-rendered])")) return
  try {
    const {renderCommentMath} = await import("../comment_math")
    // An import can finish after this comment has been removed or replaced.
    if (el.isConnected) renderCommentMath(el)
  } catch {
    // The server-escaped formula stays readable if the optional bundle is unavailable.
  }
}

export const CommentMarkdown = {
  mounted(this: Context) {
    void renderMath(this)
  },
  updated(this: Context) {
    void renderMath(this)
  },
}
