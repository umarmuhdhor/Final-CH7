// `rules` in wrangler.jsonc bundles these as Data modules.
declare module "*.jpg" {
  const data: ArrayBuffer;
  export default data;
}
