import { loadFont as loadNunito } from "@remotion/google-fonts/Nunito";

const nunito = loadNunito("normal", {
  weights: ["700", "800", "900"],
  subsets: ["latin"],
});

/** Brand type (Shoo's rounded face). */
export const BRAND_FONT = `${nunito.fontFamily}, ui-rounded, system-ui, sans-serif`;

/** UI type: Apple's system face (rendered on macOS). */
export const UI_FONT =
  '-apple-system, "SF Pro Display", "Helvetica Neue", system-ui, sans-serif';
