// agenlits - Cadastro Real integrado com Supabase
const SUPABASE_URL = 'https://fdoceyjcibzdfiqvdzkv.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZkb2NleWpjaWJ6ZGZpcXZkemt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzODkyOTEsImV4cCI6MjEwNDk2NTI5MX0.v6Jj0Fn7u1HEAHl-zq5SZTmGxCIeHXs2a-vTSgtFm-A';

const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

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
  const submitBtn = document.getElementById('submit-btn');
  const successModal = document.getElementById('success-modal');

  // Alternar visualização da senha
  if (togglePassBtn && passInput) {
    togglePassBtn.addEventListener('click', () => {
      const type = passInput.getAttribute('type') === 'password' ? 'text' : 'password';
      passInput.setAttribute('type', type);
      togglePassBtn.querySelector('i').className = type === 'text' ? 'ph ph-eye-slash' : 'ph ph-eye';
    });
  }

  // Preenche plano da URL
  const urlParams = new URLSearchParams(window.location.search);
  const planParam = urlParams.get('plano');
  const planSelect = document.getElementById('selected-plan');
  if (planParam && planSelect && ['solo', 'pro', 'redes'].includes(planParam)) {
    planSelect.value = planParam;
  }

  // Gerador dinâmico de Slug (URL amigável)
  function gerarSlug(texto) {
    return texto
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '');
  }

  if (barbershopNameInput) {
    barbershopNameInput.addEventListener('input', (e) => {
      barbershopSlugInput.value = gerarSlug(e.target.value);
    });
  }

  // Passo 1 -> Passo 2
  btnNext.addEventListener('click', () => {
    const name = document.getElementById('owner-name').value.trim();
    const email = document.getElementById('owner-email').value.trim();
    const phone = document.getElementById('owner-phone').value.trim();
    const pass = passInput.value;

    if (!name || !email || !phone || !pass) {
      alert('Por favor, preencha todos os campos do Passo 1.');
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
      barbershopSlugInput.value = gerarSlug(barbershopNameInput.value);
    }
  });

  // Passo 2 -> Passo 1
  btnPrev.addEventListener('click', () => {
    step2.classList.add('hidden');
    step1.classList.remove('hidden');
    progressBar.style.width = '50%';
    stepLabel.innerHTML = '<i class="ph-bold ph-number-circle-one text-base"></i> Passo 1: Seus Dados e Acesso';
    stepIndicator.textContent = 'Etapa 1 de 2';
  });

  // SUBMISSÃO REAL NO BANCO DE DADOS (SUPABASE)
  signupForm.addEventListener('submit', async (e) => {
    e.preventDefault();

    const name = document.getElementById('owner-name').value.trim();
    const email = document.getElementById('owner-email').value.trim();
    const phone = document.getElementById('owner-phone').value.trim();
    const password = passInput.value;
    const shopName = barbershopNameInput.value.trim();
    const slug = barbershopSlugInput.value.trim();
    const address = document.getElementById('barbershop-address').value.trim();
    const plan = document.getElementById('selected-plan').value;

    if (!shopName || !slug) {
      alert('Por favor, defina o nome e o link da sua barbearia.');
      return;
    }

    submitBtn.disabled = true;
    submitBtn.innerHTML = '<i class="ph-bold ph-spinner animate-spin text-lg"></i> Salvando no banco...';

    try {
      // 1. Cria o usuário com criptografia profissional no Supabase Auth
      const { data: authData, error: authError } = await supabase.auth.signUp({
        email: email,
        password: password,
        options: {
          data: {
            full_name: name,
            phone: phone
          }
        }
      });

      if (authError) throw authError;

      // 2. Salva a Barbearia na tabela barbershops
      const { error: shopError } = await supabase.from('barbershops').insert([
        {
          owner_id: authData.user.id,
          name: shopName,
          slug: slug,
          phone: phone,
          address: address,
          plan: plan
        }
      ]);

      if (shopError) {
        if (shopError.message.includes('unique') || shopError.code === '23505') {
          throw new Error('O link ' + slug + ' já está em uso por outra barbearia. Escolha outro link.');
        }
        throw shopError;
      }

      // Sucesso!
      const modalMsg = document.getElementById('success-msg');
      modalMsg.textContent = `A barbearia "${shopName}" foi cadastrada com sucesso! Seu link será agenlits.com/${slug}`;
      successModal.classList.remove('hidden');

    } catch (err) {
      alert('Atenção: ' + err.message);
      submitBtn.disabled = false;
      submitBtn.innerHTML = 'Concluir e Salvar <i class="ph-bold ph-check"></i>';
    }
  });
});
