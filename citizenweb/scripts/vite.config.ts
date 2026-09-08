import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

const productRoot = fileURLToPath(new URL('..', import.meta.url))
const workspaceRoot = fileURLToPath(new URL('../..', import.meta.url))

export default defineConfig(({ command }) => {
  if (command === 'build' && !process.env.CITIZENWEB_DIST && process.env.CI !== 'true') {
    throw new Error('本机编译必须由TataConsole提供CITIZENWEB_DIST，禁止恢复产品目录dist')
  }
  return {
    root: productRoot,
    plugins: [react(), tailwindcss()],
    build: {
      outDir: process.env.CITIZENWEB_DIST || fileURLToPath(new URL('../dist', import.meta.url)),
    },
    server: {
      fs: {
        allow: [workspaceRoot],
      },
    },
  }
})
