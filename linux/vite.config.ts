import { defineConfig } from "vite";

const host = process.env.TAURI_DEV_HOST;

export default defineConfig({
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
    host: host || false,
    watch: { ignored: ["**/src-tauri/**", "**/store/**"] },
  },
  envPrefix: ["VITE_", "TAURI_ENV_*"],
  build: { target: "es2022", minify: !process.env.TAURI_ENV_DEBUG, sourcemap: !!process.env.TAURI_ENV_DEBUG },
  test: { environment: "node", include: ["src/__tests__/**/*.test.ts"] },
} as any);
