(() => {
  const SUPABASE_URL = 'https://fdoceyjcibzdfiqvdzkv.supabase.co';
  const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZkb2NleWpjaWJ6ZGZpcXZkemt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzODkyOTEsImV4cCI6MjEwNDk2NTI5MX0.v6Jj0Fn7u1HEAHl-zq5SZTmGxCIeHXs2a-vTSgtFm-A';
  const client = (window._agenlitsClient = window._agenlitsClient || window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY));

  const barbershopNameInput = document.getElementById('barbershop-name');
  const ownerNameInput = document.getElementById('owner-name');
  const ownerPhoneInput = document.getElementById('owner-phone');
  const docTypeInput = document.getElementById('doc-type');
  const docNumberInput = document.getElementById('doc-number');
  const ownerEmailInput = document.getElementById('owner-email');
  const ownerPasswordInput = document.getElementById('owner-password');
  const ownerConfirmPasswordInput = document.getElementById('owner-confirm-password');
  const barbershopSlugInput = document.getElementById('barbershop-slug');
  const btnSubmit = document.getElementById('btn-submit');
  const errorAlert = document.getElementById('error-alert');
  const errorMessage = document.getElementById('error-message');
  const successModal = document.getElementById('success-modal');
  const successMsg = document.getElementById('success-msg');
  const modalLoginBtn = document.getElementById('modal-login-btn');

  function showError(msg) {
    errorMessage.textContent = msg;
    errorAlert.classList.remove('hidden');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function hideError() {
    errorAlert.classList.add('hidden');
  }

  // Máscaras de telefone e slug
  ownerPhoneInput.addEventListener('input', (e) => {
    let v = e.target.value.replace(/\D/g, '');
    if (v.length > 11) v = v.slice(0, 11);
    if (v.length > 10) e.target.value = '(' + v.slice(0, 2) + ') ' + v.slice(2, 7) + '-' + v.slice(7);
    else if (v.length > 6) e.target.value = '(' + v.slice(0, 2) + ') ' + v.slice(2, 6) + '-' + v.slice(6);
    else if (v.length > 2) e.target.value = '(' + v.slice(0, 2) + ') ' + v.slice(2);
    else e.target.value = v;
  });

  barbershopNameInput.addEventListener('input', () => {
    if (window.getRegType && window.getRegType() === 'owner') {
      const slug = barbershopNameInput.value
        .toLowerCase()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .replace(/[^a-z0-9]/g, '-')
        .replace(/-+/g, '-')
        .replace(/^-|-$/g, '');
      barbershopSlugInput.value = slug;
    }
  });

  btnSubmit.addEventListener('click', async () => {
    hideError();
    const isClient = window.getRegType ? window.getRegType() === 'client' : false;

    const name = ownerNameInput.value.trim();
    const phone = ownerPhoneInput.value.trim();
    const email = ownerEmailInput.value.trim();
    const password = ownerPasswordInput.value;
    const confirmPassword = ownerConfirmPasswordInput.value;

    if (!name) return showError('Por favor, digite seu nome.');
    if (!phone) return showError('Por favor, informe seu WhatsApp.');
    if (!email) return showError('Por favor, informe seu e-mail.');
    if (!password || password.length < 6) return showError('A senha deve conter no mínimo 6 caracteres.');
    if (password !== confirmPassword) return showError('As senhas digitadas não coincidem.');

    let shopName = '';
    let docType = '';
    let docNumber = '';
    let slug = '';

    if (!isClient) {
      shopName = barbershopNameInput.value.trim();
      docType = docTypeInput.value;
      docNumber = docNumberInput.value.trim();
      slug = barbershopSlugInput.value.trim();

      if (!shopName) return showError('Por favor, informe o nome da sua barbearia.');
      if (!docNumber) return showError('Por favor, informe o CPF ou CNPJ da empresa.');
      if (!slug) return showError('Por favor, informe o link exclusivo da barbearia.');
    }

    btnSubmit.disabled = true;
    btnSubmit.innerHTML = '<i class="ph-bold ph-spinner animate-spin"></i> Criando conta...';

    try {
      // 1. Criar usuário no Supabase Auth
      const { data: authData, error: authError } = await client.auth.signUp({
        email: email,
        password: password,
        options: {
          data: {
            full_name: name,
            user_type: isClient ? 'client' : 'owner'
          }
        }
      });

      if (authError) throw authError;
      const user = authData.user;
      if (!user) throw new Error('Falha ao autenticar usuário criado.');

      if (isClient) {
        // 2. Salvar na TABELA EXCLUSIVA DE CLIENTES (public.clients)
        const { error: clientDbError } = await client.from('clients').insert([{
          auth_user_id: user.id,
          name: name,
          phone: phone,
          email: email
        }]);

        if (clientDbError) throw clientDbError;

        successMsg.textContent = 'Sua conta de cliente foi criada com sucesso! Agora você já pode agendar e acompanhar seus atendimentos.';
        modalLoginBtn.href = 'login.html?type=client';
      } else {
        // 2. Salvar na TABELA DE EMPRESAS (public.barbershops)
        const { error: shopDbError } = await client.from('barbershops').insert([{
          owner_id: user.id,
          name: shopName,
          slug: slug,
          document_type: docType,
          document_number: docNumber,
          phone: phone
        }]);

        if (shopDbError) throw shopDbError;

        successMsg.textContent = 'Barbearia cadastrada com sucesso! Acesse seu painel para gerenciar a agenda e sua equipe.';
        modalLoginBtn.href = 'login.html?type=owner';
      }

      successModal.classList.remove('hidden');

    } catch (err) {
      console.error(err);
      showError(err.message || 'Erro ao realizar cadastro.');
      btnSubmit.disabled = false;
      btnSubmit.innerHTML = (isClient ? 'Criar Conta de Cliente' : 'Cadastrar Barbearia') + ' <i class="ph-bold ph-check"></i>';
    }
  });
})();
