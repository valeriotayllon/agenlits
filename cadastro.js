document.addEventListener('DOMContentLoaded', () => {
  const step1 = document.getElementById('step-1');
  const step2 = document.getElementById('step-2');
  const btnNext = document.getElementById('btn-next-step');
  const btnPrev = document.getElementById('btn-prev-step');
  const progressBar = document.getElementById('progress-bar');
  const stepLabel = document.getElementById('step-label');
  const stepIndicator = document.getElementById('step-indicator');
  const togglePassBtn = document.getElementById('toggle-password');
  const passInput = document.getElementById('owner-password');
  const barbershopNameInput = document.getElementById('barbershop-name');
  const barbershopSlugInput = document.getElementById('barbershop-slug');
  const signupForm = document.getElementById('signup-form');
  const successModal = document.getElementById('success-modal');

  if (togglePassBtn && passInput) {
    togglePassBtn.addEventListener('click', () => {
      const type = passInput.getAttribute('type') === 'password' ? 'text' : 'password';
      passInput.setAttribute('type', type);
    });
  }

  const urlParams = new URLSearchParams(window.location.search);
  const planParam = urlParams.get('plano');
  const planSelect = document.getElementById('selected-plan');
  if (planParam && planSelect && ['solo', 'pro', 'redes'].includes(planParam)) {
    planSelect.value = planParam;
  }

  btnNext.addEventListener('click', () => {
    const name = document.getElementById('owner-name').value.trim();
    const email = document.getElementById('owner-email').value.trim();
    const phone = document.getElementById('owner-phone').value.trim();
    const pass = passInput.value;

    if (!name || !email || !phone || !pass) {
      alert('Por favor, preencha todos os campos do Passo 1 antes de continuar.');
      return;
    }
    if (pass.length < 6) {
      alert('A senha precisa ter no mínimo 6 caracteres.');
      return;
    }

    step1.classList.add('hidden');
    step2.classList.remove('hidden');
    progressBar.style.width = '100%';
    stepLabel.innerHTML = '<i class="ph-bold ph-number-circle-two text-base"></i> Passo 2: Dados da Barbearia';
    stepIndicator.textContent = 'Etapa 2 de 2';

    if (!barbershopNameInput.value) {
      barbershopNameInput.value = `Barbearia do ${name.split(' ')[0]}`;
      gerarSlug(barbershopNameInput.value);
    }
  });

  btnPrev.addEventListener('click', () => {
    step2.classList.add('hidden');
    step1.classList.remove('hidden');
    progressBar.style.width = '50%';
    stepLabel.innerHTML = '<i class="ph-bold ph-number-circle-one text-base"></i> Passo 1: Seus Dados e Acesso';
    stepIndicator.textContent = 'Etapa 1 de 2';
  });

  function gerarSlug(texto) {
    const slug = texto
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '');
    barbershopSlugInput.value = slug;
  }

  if (barbershopNameInput) {
    barbershopNameInput.addEventListener('input', (e) => {
      gerarSlug(e.target.value);
    });
  }

  signupForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const shopName = barbershopNameInput.value.trim();
    const slug = barbershopSlugInput.value.trim();
    if (!shopName || !slug) {
      alert('Por favor, informe o nome e o link da sua barbearia.');
      return;
    }
    const modalMsg = document.getElementById('success-msg');
    modalMsg.textContent = `A barbearia "${shopName}" foi criada com sucesso! O seu link público será: agenlits.com/${slug}`;
    successModal.classList.remove('hidden');
  });
});
