import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export default defineConfig(() => {
  return {
  // OnChina 后端同源托管 dist,base 用相对路径以适配任意内网挂载路径。
  base: './',
  plugins: [react()],
  build: {
    outDir: process.env.ONCHINA_FRONTEND_DIST || join(tmpdir(), 'citizenchain', 'onchina-frontend')
  },
  server: {
    port: 5179,
    host: 'localhost',
    strictPort: true,
    proxy: {
      '/api': {
        target: 'https://onchina.local:8964',
        changeOrigin: true,
        secure: false
      }
    }
  },
  preview: {
    port: 5179,
    host: 'localhost',
    strictPort: true,
    proxy: {
      '/api': {
        target: 'https://onchina.local:8964',
        changeOrigin: true,
        secure: false
      }
    }
  }
  };
});
