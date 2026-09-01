import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

/**
 * Build the kanban plugin's frontend.
 *
 * The output is one ES module, `../src/precursor_kanban/web/index.js`, which
 * ships inside the Python wheel. Precursor serves it at
 * `/api/plugins/kanban/assets/index.js` and imports it at runtime; the module
 * calls `registerSection` at import time and the section appears.
 *
 * Two things make that work, and both are contract, not preference:
 *
 * 1. **The externals below are not bundled.** There must be exactly one React on
 *    the page — a second copy means a second dispatcher and every hook this
 *    plugin calls throws. The host injects an import map into `index.html` that
 *    points `react`, `react-dom`, both JSX runtimes and `@precursor/host` at its
 *    own `host-runtime.js`, so we get the host's instances and its SDK without
 *    vendoring either.
 * 2. **The filename is fixed.** The backend advertises `<package>/web/index.js`
 *    and the host imports exactly that URL.
 *
 * Everything else — `lucide-react`, our own modules, our stylesheet — *is*
 * bundled, because the host makes no promise about it.
 */
export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: {
    outDir: "../src/precursor_kanban/web",
    emptyOutDir: true,
    // The host's own build targets modern browsers and this module is loaded by
    // it, so match rather than down-level into a larger bundle.
    target: "es2022",
    lib: {
      entry: "src/index.tsx",
      formats: ["es"],
      fileName: () => "index.js",
    },
    // The stylesheet is imported with `?inline` and injected by `styles.ts`, so
    // nothing should reach the CSS pipeline as a separate asset. Turning code
    // splitting off keeps Vite from emitting a stray `index.css` that no one
    // would ever load.
    cssCodeSplit: false,
    rollupOptions: {
      external: [
        "react",
        "react-dom",
        "react/jsx-runtime",
        "react/jsx-dev-runtime",
        "@precursor/host",
      ],
    },
  },
});
