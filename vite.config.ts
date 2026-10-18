import { defineConfig } from 'vite'

// Vite 8 defaults build.cssMinify to lightningcss, which chokes on UnoCSS output
// ("Invalid token in pseudo element" on --un-* utilities emitted by @slidev/client).
// Inlined here rather than re-exported from a parent, so this repo stands alone.
export default defineConfig({
  build: { cssMinify: false },
})
