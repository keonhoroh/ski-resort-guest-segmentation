import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    // Requests to /api/... are passed on to the Rails server.
    proxy: { '/api': 'http://localhost:3000' },
  },
})
