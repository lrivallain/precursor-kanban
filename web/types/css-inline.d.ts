/**
 * Vite's `?inline` CSS import — returns the compiled stylesheet as a string.
 *
 * Vite ships this in `vite/client`, but pulling those types in would also drag
 * along globals and `import.meta.env` typings this bundle has no use for
 * (`"types": []` in tsconfig.json is deliberate). One declaration is cheaper
 * than the whole surface.
 */
declare module "*.css?inline" {
  const css: string;
  export default css;
}
