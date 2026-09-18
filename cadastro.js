// ==============================================================================
// CADASTRO OFICIAL (cadastro.js) - RESILIENTE & VALIDADO
// ==============================================================================

// Validação matemática de CPF (11 dígitos)
function validateCPF(cpf) {
  cpf = (cpf || '').replace(/\D/g, '');
  if (cpf.length !== 11 || /^(\d)\1{10}$/.test(cpf)) return false;
  let sum = 0, rest;
  for (let i = 1; i <= 9; i++) sum += parseInt(cpf.substring(i - 1, i)) * (11 - i);
  rest = (sum * 10) % 11;
  if (rest === 10 || rest === 11) rest = 0;
  if (rest !== parseInt(cpf.substring(9, 10))) return false;
  sum = 0;
  for (let i = 1; i <= 10; i++) sum += parseInt(cpf.substring(i - 1, i)) * (12 - i);
  rest = (sum * 10) % 11;
  if (rest === 10 || rest === 11) rest = 0;
  return rest === parseInt(cpf.substring(10, 11));
}

// Validação matemática de CNPJ (14 dígitos)
function validateCNPJ(cnpj) {
  cnpj = (cnpj || '').replace(/\D/g, '');
  if (cnpj.length !== 14 || /^(\d)\1{13}$/.test(cnpj)) return false;
  let size = cnpj.length - 2;
  let numbers = cnpj.substring(0, size);
  const digits = cnpj.substring(size);
  let sum = 0, pos = size - 7;
  for (let i = size; i >= 1; i--) {
    sum += parseInt(numbers.charAt(size - i)) * pos--;
    if (pos < 2) pos = 9;
  }
  let result = sum % 11 < 2 ? 0 : 11 - (sum % 11);
  if (result !== parseInt(digits.charAt(0))) return false;
  size = size + 1;
  numbers = cnpj.substring(0, size);
  sum = 0;
  pos = size - 7;
  for (let i = size; i >= 1; i--) {
    sum += parseInt(numbers.charAt(size - i)) * pos--;
    if (pos < 2) pos = 9;
  }
  result = sum % 11 < 2 ? 0 : 11 - (sum % 11);
  return result === parseInt(digits.charAt(1));
}

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
    if (errorMessage && errorAlert) {
      errorMessage.textContent = msg;
      errorAlert.classList.remove('hidden');
      window.scrollTo({ top: 0, behavior: 'smooth' });
    } else {
      alert(msg);
    }
  }

  function hideError() {
    if (errorAlert) {
      errorAlert.classList.add('hidden');
    }
  }

  if (ownerPhoneInput) {
    ownerPhoneInput.addEventListener('input', (e) => {
      let v = e.target.value.replace(/\D/g, '');
      if (v.length > 11) v = v.slice(0, 11);
      if (v.length > 10) e.target.value = '(' + v.slice(0, 2) + ') ' + v.slice(2, 7) + '-' + v.slice(7);
      else if (v.length > 6) e.target.value = '(' + v.slice(0, 2) + ') ' + v.slice(2, 6) + '-' + v.slice(6);
      else if (v.length > 2) e.target.value = '(' + v.slice(0, 2) + ') ' + v.slice(2);
      else e.target.value = v;
    });
  }

  if (barbershopNameInput && barbershopSlugInput) {
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
  }

  if (btnSubmit) {
    btnSubmit.addEventListener('click', async () => {
      hideError();
      const isClient = window.getRegType ? window.getRegType() === 'client' : false;

      const name = ownerNameInput ? ownerNameInput.value.trim() : '';
      const phone = ownerPhoneInput ? ownerPhoneInput.value.trim() : '';
      const cleanPhone = phone.replace(/\D/g, '');
      const email = ownerEmailInput ? ownerEmailInput.value.trim() : '';
      const password = ownerPasswordInput ? ownerPasswordInput.value : '';
      const confirmPassword = ownerConfirmPasswordInput ? ownerConfirmPasswordInput.value : '';

      if (!name) return showError('Por favor, digite seu nome.');
      if (!phone || cleanPhone.length < 10) return showError('Por favor, informe seu WhatsApp com DDD.');
      if (!email) return showError('Por favor, informe seu e-mail.');
      if (!password || password.length < 6) return showError('A senha deve conter no mínimo 6 caracteres.');
      if (password !== confirmPassword) return showError('As senhas digitadas não coincidem.');

      let shopName = '';
      let docType = 'cpf';
      let rawDoc = '';
      let cleanDoc = '';
      let slug = '';

      if (!isClient) {
        shopName = barbershopNameInput ? barbershopNameInput.value.trim() : '';
        docType = docTypeInput ? docTypeInput.value : 'cpf';
        rawDoc = docNumberInput ? docNumberInput.value.trim() : '';
        cleanDoc = rawDoc.replace(/\D/g, '');
        slug = barbershopSlugInput ? barbershopSlugInput.value.trim().toLowerCase() : '';

        if (!shopName) return showError('Por favor, informe o nome da sua barbearia.');
        if (!rawDoc) return showError('Por favor, informe o CPF ou CNPJ da empresa.');

        if (docType === 'cpf') {
          if (!validateCPF(cleanDoc)) return showError('O CPF informado é inválido. Verifique os números digitados.');
        } else {
          if (!validateCNPJ(cleanDoc)) return showError('O CNPJ informado é inválido. Verifique os números digitados.');
        }

        if (!slug || slug.length < 3) return showError('Por favor, informe um link exclusivo válido com no mínimo 3 caracteres.');

        try {
          const { data: slugCheck } = await client.rpc('check_slug_available', { p_slug: slug });
          if (slugCheck && !slugCheck.available) {
            return showError(slugCheck.reason || 'Este link exclusivo já está em uso por outra barbearia.');
          }
        } catch (err) {
          console.warn('Checagem de slug ignorada:', err);
        }
      }

      btnSubmit.disabled = true;
      btnSubmit.innerHTML = '<i class="ph-bold ph-spinner animate-spin"></i> Criando conta...';

      try {
        const { data: authData, error: authError } = await client.auth.signUp({
          email: email,
          password: password,
          options: {
            data: {
              full_name: name,
              phone: cleanPhone,
              user_type: isClient ? 'client' : 'owner',
              barbershop_name: shopName,
              barbershop_slug: slug,
              document_type: docType,
              document_number: cleanDoc
            }
          }
        });

        if (authError) throw authError;
        const user = authData.user;
        if (!user) throw new Error('Falha ao autenticar usuário criado.');

        if (isClient) {
          const { error: clientDbError } = await client.from('clients').insert([{
            auth_user_id: user.id,
            name: name,
            phone: cleanPhone,
            email: email
          }]);

          if (clientDbError) console.warn('Registro em clients:', clientDbError.message);

          if (successMsg) successMsg.textContent = 'Sua conta de cliente foi criada com sucesso! Agora você já pode agendar e acompanhar seus atendimentos.';
          if (modalLoginBtn) modalLoginBtn.href = 'login.html?type=client';
        } else {
          const { error: shopDbError } = await client.from('barbershops').insert([{
            owner_id: user.id,
            name: shopName,
            slug: slug,
            document_type: docType,
            document_number: cleanDoc,
            phone: cleanPhone,
            timezone: 'America/Sao_Paulo'
          }]);

          if (shopDbError && !shopDbError.message.includes('unique') && !shopDbError.message.includes('duplicate')) {
            throw shopDbError;
          }

          if (successMsg) successMsg.textContent = 'Barbearia cadastrada com sucesso! Acesse seu painel para gerenciar sua agenda e faturamento.';
          if (modalLoginBtn) modalLoginBtn.href = 'login.html?type=owner';
        }

        if (successModal) {
          successModal.classList.remove('hidden');
        } else {
          alert('Cadastro realizado com sucesso! Faça login para continuar.');
          window.location.href = isClient ? 'login.html?type=client' : 'login.html?type=owner';
        }

      } catch (err) {
        console.error('Erro no cadastro:', err);
        showError(err.message || 'Erro ao realizar cadastro.');
        btnSubmit.disabled = false;
        btnSubmit.innerHTML = (isClient ? 'Criar Conta de Cliente' : 'Cadastrar Barbearia') + ' <i class="ph-bold ph-check"></i>';
      }
    });
  }
})();
