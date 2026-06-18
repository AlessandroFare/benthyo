import path from "path";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  envDir: path.resolve(__dirname, "../.."),
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  build: {
    outDir: "dist",
    // I-8: source maps in production decompile the dashboard and reveal
    // the API contract. `hidden` still emits the .map files for error
    // reporting tools but does not add the //# sourceMappingURL comment,
    // so end users cannot trivially download the maps.
    sourcemap: "hidden",
    chunkSizeWarningLimit: 600,
    rollupOptions: {
      output: {
        manualChunks: {
          "vendor-react": ["react", "react-dom", "react-router-dom"],
          "vendor-charts": ["recharts"],
          "vendor-query": ["@tanstack/react-query"],
          "vendor-supabase": ["@supabase/supabase-js"],
        },
      },
    },
  },
  server: {
    port: 5173,
    proxy: {
      "/api/v1": {
        target: process.env.API_URL || "http://localhost:3000",
        changeOrigin: true,
        secure: false,
      },
    },
  },
});
