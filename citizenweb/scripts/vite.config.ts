import { fileURLToPath, URL } from 'node:url'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

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
