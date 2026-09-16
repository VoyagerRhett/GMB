import { fileURLToPath, URL } from 'node:url'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// 本配置固定CitizenWeb产品根、前端插件、源码外构建输出和开发服务器读取边界。
const productRoot = fileURLToPath(new URL('..', import.meta.url))
const workspaceRoot = fileURLToPath(new URL('../..', import.meta.url))

export default defineConfig(() => {
  return {
    root: productRoot,
    plugins: [react(), tailwindcss()],
    build: {
      outDir: process.env.CITIZENWEB_DIST || join(tmpdir(), 'citizenweb', 'dist'),
    },
    server: {
      fs: {
        allow: [workspaceRoot],
      },
    },
  }
})
