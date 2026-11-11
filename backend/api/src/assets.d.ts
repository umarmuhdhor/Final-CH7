// `rules` in wrangler.jsonc bundles these as Data modules.
declare module "*.jpg" {
  const data: ArrayBuffer;
  export default data;
}

declare module "*.png" {
  const data: ArrayBuffer;
  export default data;
}
