---
# Export entry. The addon's code-server keeps a socket open and `slidev export`
# waits for networkidle, which then never arrives (14 s becomes 250 s or a
# timeout), so this entry deliberately omits the livecode addon. That means the
# <Editor /> slides cannot resolve here: their component comes from the addon.
# So this entry imports slides.md in three ranges, skipping the three Editor
# slides: 9 (From BCC C-String to Python-BPF), 10 (How we run one arm) and
# 25 (The enforcer, live — BCC).
#
# `src:` is read from SLIDE frontmatter (see @slidev/parser fs.mjs:81), and a
# `#N-M` suffix selects a slide range. Ranges are by slides.md slide NUMBER, so
# they must be updated whenever a slide is added or removed above an Editor.
theme: slidev-theme-nord
layout: center
class: text-center
title: 'Python eBPF: BCC C-String Runtime vs Python-BPF AST AOT'
colorSchema: dark
highlighter: shiki
shikiOptions:
  theme: nord
---

---
src: ./slides.md#1-8
---

---
src: ./slides.md#11-24
---

---
src: ./slides.md#26-34
---
