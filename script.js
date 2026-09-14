// BarberFlow - Interatividade da Página Inicial

document.addEventListener('DOMContentLoaded', () => {
  // 1. Alternar menu mobile
  const menuBtn = document.getElementById('menu-btn');
  const mobileMenu = document.getElementById('mobile-menu');

  if (menuBtn && mobileMenu) {
    menuBtn.addEventListener('click', () => {
      mobileMenu.classList.toggle('hidden');
    });
  }

  // 2. Acordeão de Perguntas Frequentes (FAQ)
  const faqButtons = document.querySelectorAll('.faq-btn');

  faqButtons.forEach((button) => {
    button.addEventListener('click', () => {
      const content = button.nextElementSibling;
      const icon = button.querySelector('i');
      const isCurrentlyOpen = !content.classList.contains('hidden');

      // Fecha todos os itens abertos
      document.querySelectorAll('.faq-content').forEach((item) => {
        item.classList.add('hidden');
      });
      document.querySelectorAll('.faq-btn i').forEach((itemIcon) => {
        itemIcon.classList.remove('rotate-180');
      });

      // Se não estava aberto, abre o clicado
      if (!isCurrentlyOpen) {
        content.classList.remove('hidden');
        if (icon) {
          icon.classList.add('rotate-180');
        }
      }
    });
  });
});
