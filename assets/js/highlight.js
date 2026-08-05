/**
 * Syntax highlighting for code blocks.
 *
 * Ported from the sibling `blog` project (assets/js/post.js): the same
 * hand-written Elixir and JavaScript scanners, with the string scanner widened
 * for heredocs and interpolation (see `scanElixirString`).
 *
 * The DOM plumbing differs from the original. MDEx renders fenced code as
 * `<pre><code class="language-elixir">` and the `<code>` element carries the
 * block padding, so the highlighted markup replaces the content of `<code>`
 * rather than the content of `<pre>`.
 *
 * A block opts in either through the `language-*` class MDEx emits or through
 * an explicit `data-language` on the `<pre>`. Unlabelled blocks are left
 * untouched: shell transcripts and plain output share too many words with
 * Elixir to be guessed at.
 */

const ELIXIR_KEYWORDS = [
  "def", "defp", "defmodule", "defstruct", "defprotocol", "defimpl", "defmacro", "defmacrop",
  "defguard", "do", "end", "fn", "case", "cond", "if", "else", "unless", "when", "with", "for",
  "receive", "try", "catch", "rescue", "after", "raise", "throw", "import", "require", "alias",
  "use", "true", "false", "nil", "and", "or", "not", "in", "quote", "unquote"
]

const SIGIL_DELIMITERS = {"[": "]", "{": "}", "(": ")", "<": ">", "/": "/", "\"": "\"", "'": "'"}

const JS_KEYWORDS = [
  "function", "const", "let", "var", "if", "else", "for", "while", "do",
  "switch", "case", "break", "continue", "return", "throw", "try", "catch",
  "finally", "new", "delete", "typeof", "instanceof", "in", "of",
  "class", "extends", "super", "this", "static", "get", "set",
  "import", "export", "default", "from", "as", "async", "await", "yield",
  "true", "false", "null", "undefined", "NaN", "Infinity"
]

const JS_BUILTINS = [
  "console", "window", "document", "Array", "Object", "String", "Number",
  "Boolean", "Function", "Symbol", "Map", "Set", "WeakMap", "WeakSet",
  "Promise", "Proxy", "Reflect", "JSON", "Math", "Date", "RegExp", "Error"
]

const escapeHtml = text =>
  text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")

/**
 * Returns the index just past the string literal starting at `pos`.
 *
 * Widened from the original scanner, which stopped at the first unescaped
 * quote: heredocs and `#{}` interpolation are too common in Elixir to
 * mis-tokenize, since `@moduledoc """` alone would desynchronise the rest of
 * the block.
 */
const scanElixirString = (code, pos) => {
  const quote = code.slice(pos, pos + 3) === '"""' ? '"""' : '"'
  let index = pos + quote.length

  while (index < code.length) {
    if (code[index] === "\\") {
      index += 2
    } else if (code.slice(index, index + 2) === "#{") {
      index = skipInterpolation(code, index)
    } else if (code.slice(index, index + quote.length) === quote) {
      return index + quote.length
    } else {
      index++
    }
  }

  return code.length
}

/** Returns the index just past the `#{...}` interpolation starting at `pos`. */
const skipInterpolation = (code, pos) => {
  let index = pos + 2
  let depth = 1

  while (index < code.length && depth > 0) {
    const char = code[index]

    if (char === "\\") {
      index += 2
    } else if (char === '"') {
      index = scanElixirString(code, index)
    } else {
      if (char === "{") depth++
      else if (char === "}") depth--
      index++
    }
  }

  return index
}

const toHtml = tokens =>
  tokens
    .map(token => {
      const escaped = escapeHtml(token.value)
      return token.type === "text" ? escaped : `<span class="hl-${token.type}">${escaped}</span>`
    })
    .join("")

const highlightElixirCode = code => {
  const tokens = []
  let pos = 0

  while (pos < code.length) {
    let matched = false

    // 1. Comments
    if (code[pos] === "#") {
      const end = code.indexOf("\n", pos)
      const comment = end === -1 ? code.slice(pos) : code.slice(pos, end)
      tokens.push({type: "comment", value: comment})
      pos += comment.length
      matched = true
    }

    // 2. Strings and heredocs
    else if (code[pos] === '"') {
      const end = scanElixirString(code, pos)
      tokens.push({type: "string", value: code.slice(pos, end)})
      pos = end
      matched = true
    }

    // 3. Sigils (~D[...], ~r/.../, ...)
    else if (code[pos] === "~" && /[A-Za-z]/.test(code[pos + 1])) {
      const endDelimiter = SIGIL_DELIMITERS[code[pos + 2]]
      if (endDelimiter) {
        const end = code.indexOf(endDelimiter, pos + 3)
        if (end !== -1) {
          tokens.push({type: "sigil", value: code.slice(pos, end + 1)})
          pos = end + 1
          matched = true
        }
      }
    }

    // 4. Binary notation <<...>>
    else if (code.slice(pos, pos + 2) === "<<") {
      const end = code.indexOf(">>", pos + 2)
      if (end !== -1) {
        tokens.push({type: "binary", value: code.slice(pos, end + 2)})
        pos = end + 2
        matched = true
      }
    }

    // 5. Operators (multi-char)
    else if (code.slice(pos, pos + 2).match(/^(\|>|<\||=>|<-|->|&&|\|\||==|!=|<=|>=)$/)) {
      tokens.push({type: "operator", value: code.slice(pos, pos + 2)})
      pos += 2
      matched = true
    }

    // 6. Atoms (:word)
    else if (code[pos] === ":" && /\w/.test(code[pos + 1])) {
      let end = pos + 1
      while (end < code.length && /[\w?!]/.test(code[end])) end++
      tokens.push({type: "atom", value: code.slice(pos, end)})
      pos = end
      matched = true
    }

    // 7. Words (identifiers, keywords, modules)
    else if (/[A-Za-z_]/.test(code[pos])) {
      let end = pos
      while (end < code.length && /[\w?!]/.test(code[end])) end++
      const word = code.slice(pos, end)

      if (ELIXIR_KEYWORDS.includes(word)) {
        tokens.push({type: "keyword", value: word})
      } else if (/^[A-Z]/.test(word)) {
        tokens.push({type: "module", value: word})
      } else if (code[end] === ":" && code[end + 1] !== ":") {
        // Map or keyword-list key (word followed by a colon)
        tokens.push({type: "map-key", value: word})
      } else {
        tokens.push({type: "text", value: word})
      }
      pos = end
      matched = true
    }

    // 8. Numbers
    else if (/\d/.test(code[pos])) {
      let end = pos
      while (end < code.length && /[\d_.]/.test(code[end])) end++
      tokens.push({type: "number", value: code.slice(pos, end)})
      pos = end
      matched = true
    }

    // Default: single character
    if (!matched) {
      tokens.push({type: "text", value: code[pos]})
      pos++
    }
  }

  return toHtml(tokens)
}

const highlightJSCode = code => {
  const tokens = []
  let pos = 0

  while (pos < code.length) {
    let matched = false

    // 1. Single-line comments
    if (code.slice(pos, pos + 2) === "//") {
      const end = code.indexOf("\n", pos)
      const comment = end === -1 ? code.slice(pos) : code.slice(pos, end)
      tokens.push({type: "comment", value: comment})
      pos += comment.length
      matched = true
    }

    // 2. Multi-line comments
    else if (code.slice(pos, pos + 2) === "/*") {
      const end = code.indexOf("*/", pos + 2)
      const comment = end === -1 ? code.slice(pos) : code.slice(pos, end + 2)
      tokens.push({type: "comment", value: comment})
      pos += comment.length
      matched = true
    }

    // 3. Template literals and quoted strings
    else if (code[pos] === "`" || code[pos] === '"' || code[pos] === "'") {
      const quote = code[pos]
      let end = pos + 1
      while (end < code.length && code[end] !== quote) {
        if (code[end] === "\\") end++
        end++
      }
      tokens.push({type: "string", value: code.slice(pos, end + 1)})
      pos = end + 1
      matched = true
    }

    // 4. Operators (multi-char)
    else if (code.slice(pos, pos + 3).match(/^(===|!==|>>>|\.\.\.|\*\*=)$/)) {
      tokens.push({type: "operator", value: code.slice(pos, pos + 3)})
      pos += 3
      matched = true
    } else if (
      code.slice(pos, pos + 2).match(/^(=>|==|!=|<=|>=|&&|\|\||\+\+|--|\+=|-=|\*=|\/=|\?\?|\?\.|<<|>>|\*\*)$/)
    ) {
      tokens.push({type: "operator", value: code.slice(pos, pos + 2)})
      pos += 2
      matched = true
    }

    // 5. Words (identifiers, keywords, builtins)
    else if (/[A-Za-z_$]/.test(code[pos])) {
      let end = pos
      while (end < code.length && /[\w$]/.test(code[end])) end++
      const word = code.slice(pos, end)

      if (JS_KEYWORDS.includes(word)) {
        tokens.push({type: "keyword", value: word})
      } else if (JS_BUILTINS.includes(word) || /^[A-Z]/.test(word)) {
        tokens.push({type: "module", value: word})
      } else {
        tokens.push({type: "text", value: word})
      }
      pos = end
      matched = true
    }

    // 6. Numbers
    else if (/\d/.test(code[pos]) || (code[pos] === "." && /\d/.test(code[pos + 1]))) {
      let end = pos
      if (code[pos] === "0" && /[xXbBoO]/.test(code[pos + 1])) {
        end += 2
        while (end < code.length && /[\da-fA-F_]/.test(code[end])) end++
      } else {
        while (end < code.length && /[\d_.]/.test(code[end])) end++
        if (code[end] === "e" || code[end] === "E") {
          end++
          if (code[end] === "+" || code[end] === "-") end++
          while (end < code.length && /\d/.test(code[end])) end++
        }
      }
      tokens.push({type: "number", value: code.slice(pos, end)})
      pos = end
      matched = true
    }

    // Default: single character
    if (!matched) {
      tokens.push({type: "text", value: code[pos]})
      pos++
    }
  }

  return toHtml(tokens)
}

const HIGHLIGHTERS = {
  elixir: highlightElixirCode,
  ex: highlightElixirCode,
  exs: highlightElixirCode,
  javascript: highlightJSCode,
  js: highlightJSCode
}

const languageOf = (pre, code) => {
  const declared = pre.dataset.language
  if (declared) return declared.toLowerCase()

  const match = /(?:^|\s)language-([\w+-]+)/.exec(code.className)
  return match ? match[1].toLowerCase() : null
}

/**
 * Highlights every supported, not yet highlighted code block under `root`.
 * Safe to call repeatedly: each block is marked once it has been processed.
 */
export const highlightCodeBlocks = (root = document) => {
  root.querySelectorAll("pre > code").forEach(code => {
    if (code.dataset.highlighted) return

    const pre = code.parentElement
    const language = languageOf(pre, code)
    const highlight = language && HIGHLIGHTERS[language]
    if (!highlight) return

    code.dataset.highlighted = "true"
    // Mirrored onto the `<pre>` so styling can key off the language too.
    pre.dataset.language = language
    code.innerHTML = highlight(code.textContent)
  })
}
