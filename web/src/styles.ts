/**
 * Ship the plugin's own Tailwind utilities with the bundle.
 *
 * In the monorepo this was free: the plugin's sources lived in the host's git
 * tree, so the host's Tailwind build scanned them and its stylesheet already
 * contained every utility they used. Out of tree the sources ship compiled, the
 * host never sees them, and the board would render with correct markup and no
 * styling — the kind of breakage that only shows up in a real install.
 *
 * So the bundle carries its own utilities (see `styles.css`) and adds them to
 * the document the first time the section is registered. They resolve against
 * the host's theme variables, so the board stays themed with the app and
 * follows dark mode with it.
 */

import css from "./styles.css?inline";

const STYLE_ID = "precursor-kanban-styles";

/**
 * Idempotent: the id check makes a re-import (or a hot reload during host
 * development) a no-op rather than a second copy of every rule.
 */
export function installStyles(): void {
  if (typeof document === "undefined") return;
  if (document.getElementById(STYLE_ID)) return;
  const style = document.createElement("style");
  style.id = STYLE_ID;
  style.textContent = css;
  // Prepended, not appended: the host's stylesheet must still win where the two
  // define the same utility, otherwise a plugin could quietly restyle the app.
  document.head.prepend(style);
}
