// ==============================================================================
// AGENLITS - LAYOUT & THEME MANAGEMENT (js/layout.js)
// ==============================================================================
(function initLayout() {
  function applyTheme() {
    const saved = localStorage.getItem('agenlits_theme') || 'dark';
    if (saved === 'light') {
      document.documentElement.classList.add('light');
    } else {
      document.documentElement.classList.remove('light');
    }
    updateIcons();
  }

  function toggleTheme() {
    const isLight = document.documentElement.classList.toggle('light');
    localStorage.setItem('agenlits_theme', isLight ? 'light' : 'dark');
    updateIcons();
  }

  function updateIcons() {
    const isLight = document.documentElement.classList.contains('light');
    document.querySelectorAll('.theme-toggle-btn i').forEach(icon => {
      icon.className = isLight ? 'ph-bold ph-moon text-lg text-slate-800' : 'ph-bold ph-sun text-lg text-emerald-400';
    });
  }

  applyTheme();

  document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('.theme-toggle-btn').forEach(btn => {
      btn.addEventListener('click', toggleTheme);
      btn.setAttribute('aria-label', 'Alternar tema de cores');
    });
    updateIcons();
  });
})();
