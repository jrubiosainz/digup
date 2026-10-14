import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// While developing, Vite serves the chat and passes /api on to uvicorn. In production FastAPI serves both.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: { "/api": "http://localhost:8000" },
  },
});
