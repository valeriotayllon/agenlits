/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./*.html", "./js/**/*.js"],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        brand: {
          main: 'var(--bg-main)',
          card: 'var(--bg-card)',
          darker: 'var(--bg-darker)',
          border: 'var(--border-color)',
          emerald: 'var(--emerald-primary)',
          muted: 'var(--text-muted)'
        }
      }
    },
  },
  plugins: [],
}
