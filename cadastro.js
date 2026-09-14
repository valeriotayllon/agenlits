// agenlits - Cadastro Completo com Validação de Documento e Senha
const SUPABASE_URL = 'https://fdoceyjcibzdfiqvdzkv.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZkb2NleWpjaWJ6ZGZpcXZkemt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzODkyOTEsImV4cCI6MjEwNDk2NTI5MX0.v6Jj0Fn7u1HEAHl-zq5SZTmGxCIeHXs2a-vTSgtFm-A';

const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

document.addEventListener('DOMContentLoaded', () => {
  const signupForm = document.getElementById('signup-form');
  const barbershopNameInput = document.getElementById('barbershop-name');
  const barbershopSlugInput = document.getElementById('barbershop-slug');
  const phoneInput = document.getElementById('owner-phone');
  const docTypeSelect = document.getElementById('doc-type');
  const docNumberInput = document.getElementById('doc-number');
  const passInput = document.getElementById('owner-password');
  const confirmPassInput = document.getElementById('owner-confirm-password');
  const submitBtn = document.getElementById('submit-btn');
  const successModal = document.getElementById('success-modal');

  // Alternar olho da senha
  const togglePassBtn = document.getElementById('toggle-password');
  const toggleConfirmBtn = document.getElementById('toggle-confirm-password');

  function toggleField(input, btn) {
    const isPass = input.type === 'password';
    input.type = isPass ? 'text' : 'password';
    btn.querySelector('i').className = isPass ? 'ph ph-eye-slash text-base' : 'ph ph-eye text-base';
  }

  if (togglePassBtn) togglePassBtn.addEventListener('click', () => toggleField(passInput, togglePassBtn));
  if (toggleConfirmBtn) toggleConfirmBtn.addEventListener('click', () => toggleField(confirmPassInput, toggleConfirmBtn));

  // Máscara dinâmica de telefone
  phoneInput.addEventListener('input', (e) => {
    let v = e.target.value.replace(/\D/g, '');
    if (v.length > 11) v = v.slice(0, 11);
    if (v.length > 10) {
      e.target.value = `(${v.slice(0, 2)}) ${v.slice(2, 7)}-${v.slice(7)}`;
    } else if (v.length > 6) {
      e.target.value = `(${v.slice(0, 2)}) ${v.slice(2, 6)}-${v.slice(6)}`;
    } else if (v.length > 2) {
      e.target.value = `(${v.slice(0, 2)}) ${v.slice(2)}`;
    } else {
      e.target.value = v;
    }
  });

  // Alterna placeholder e máscara para CPF / CNPJ
  docTypeSelect.addEventListener('change', () => {
    docNumberInput.value = '';
    if (docTypeSelect.value === 'CPF') {
      docNumberInput.placeholder = '000.000.000-00';
      docNumberInput.maxLength = 14;
    } else {
      docNumberInput.placeholder = '00.000.000/0000-00';
      docNumberInput.maxLength = 18;
    }
  });

  docNumberInput.addEventListener('input', (e) => {
    let v = e.target.value.replace(/\D/g, '');
    if (docTypeSelect.value === 'CPF') {
      if (v.length > 11) v = v.slice(0, 11);
      v = v.replace(/(\d{3})(\d)/, '$1.$2');
      v = v.replace(/(\d{3})(\d)/, '$1.$2');
      v = v.replace(/(\d{3})(\d{1,2})$/, '$1-$2');
    } else {
      if (v.length > 14) v = v.slice(0, 14);
      v = v.replace(/^(\d{2})(\d)/, '$1.$2');
      v = v.replace(/^(\d{2})\.(\d{3})(\d)/, '$1.$2.$3');
      v = v.replace(/\.(\d{3})(\d)/, '.$1/$2');
      v = v.replace(/(\d{4})(\d)/, '$1-$2');
    }
    e.target.value = v;
  });

  // Gerador dinâmico de slug
  function gerarSlug(texto) {
    return texto
      .toLowerCase()
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '');
  }

  barbershopNameInput.addEventListener('input', (e) => {
    barbershopSlugInput.value = gerarSlug(e.target.value);
  });

  // SUBMISSÃO REAL
  signupForm.addEventListener('submit', async (e) => {
    e.preventDefault();

    const shopName = barbershopNameInput.value.trim();
    const phone = phoneInput.value.trim();
    const docType = docTypeSelect.value;
    const docNumber = docNumberInput.value.trim();
    const ownerName = document.getElementById('owner-name').value.trim();
    const email = document.getElementById('owner-email').value.trim();
    const password = passInput.value;
    const confirmPassword = confirmPassInput.value;
    const slug = barbershopSlugInput.value.trim();

    // 1. Validar se senhas conferem
    if (password !== confirmPassword) {
      alert('As senhas não coincidem! Verifique e digite novamente.');
      confirmPassInput.focus();
      return;
    }

    if (password.length < 6) {
      alert('A senha precisa ter no mínimo 6 caracteres.');
      return;
    }

    submitBtn.disabled = true;
    submitBtn.innerHTML = '<i class="ph-bold ph-spinner animate-spin text-lg"></i> Criando barbearia...';

    try {
      // Criação de usuário seguro no Supabase Auth
      const { data: authData, error: authError } = await supabase.auth.signUp({
        email: email,
        password: password,
        options: {
          data: {
            full_name: ownerName,
            phone: phone,
            document_type: docType,
            document_number: docNumber
          }
        }
      });

      if (authError) throw authError;

      // Salva barbearia na tabela barbershops
      const { error: shopError } = await supabase.from('barbershops').insert([
        {
          owner_id: authData.user.id,
          name: shopName,
          slug: slug,
          phone: phone,
          document_type: docType,
          document_number: docNumber
        }
      ]);

      if (shopError) {
        if (shopError.message.includes('unique') || shopError.code === '23505') {
          throw new Error(`O link "${slug}" já está cadastrado por outra barbearia. Escolha um link diferente.`);
        }
        throw shopError;
      }

      // Exibe modal de confirmação
      const modalMsg = document.getElementById('success-msg');
      modalMsg.textContent = `A barbearia "${shopName}" foi criada com sucesso! Enviamos um link de confirmação para ${email}. Por favor, confirme o e-mail para fazer login.`;
      successModal.classList.remove('hidden');

    } catch (err) {
      alert('Atenção: ' + err.message);
      submitBtn.disabled = false;
      submitBtn.innerHTML = 'Cadastrar Barbearia <i class="ph-bold ph-check"></i>';
    }
  });
});
