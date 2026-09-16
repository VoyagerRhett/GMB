import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const host = process.env.TAURI_DEV_HOST;

export default defineConfig(() => {
  return {
  plugins: [react()],
  build: {
    outDir: process.env.CITIZENCHAIN_FRONTEND_DIST || join(tmpdir(), 'citizenchain', 'node-frontend')
  },
  // 白皮书由 citizenchain/scripts/generate-local-docs.mjs 内置进 bundle;
  // 公民宪法改由链上 runtime API 返回，不再维护静态目录副本。
  publicDir: false,
  clearScreen: false,
  server: {
    host: host ?? '127.0.0.1',
    port: 5173,
    strictPort: true,
    hmr: host
      ? {
          protocol: 'ws',
          host,
          port: 5174
        }
      : undefined
  }
  };
});
