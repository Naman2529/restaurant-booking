import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// The Go API runs on :8080. Proxying its routes keeps the browser on one
// origin, so the HttpOnly + SameSite=Strict auth cookie just works (no CORS).
// Front-end pages use different paths (/r, /booking, /my-bookings, /business)
// so they never collide with these.
const api = 'http://localhost:8080'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/auth': api,
      '/restaurants': api,
      '/reservations': api,
      '/staff': api,
      '/health': api,
    },
  },
})
