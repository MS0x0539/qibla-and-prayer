import { defineConfig } from "cf/config";

// The app's website: static pages only (public/, built by build.mjs), at https://qibla.dev.
export default defineConfig({
  worker: {
    name: "wajh",
    compatibilityDate: "2026-09-21",
    // www.qibla.dev answers too: a zone redirect rule sends it to qibla.dev.
    domains: ["qibla.dev", "www.qibla.dev"],
    workersDev: false,
    previewUrls: false,
    observability: {
      enabled: false
    }
  }
});
