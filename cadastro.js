// agenlits - Script Robusto com Depuração e Proteção contra Recarregamento
const SUPABASE_URL = 'https://fdoceyjcibzdfiqvdzkv.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZkb2NleWpjaWJ6ZGZpcXZkemt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzODkyOTEsImV4cCI6MjEwNDk2NTI5MX0.v6Jj0Fn7u1HEAHl-zq5SZTmGxCIeHXs2a-vTSgtFm-A';

let supabaseClient;
try {
  supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
} catch (e) {
  console.error("Falha ao inicializar Supabase:", e);
}

document.addEventListener('DOMContentLoaded', () => {
  const barbershopNameInput = document.getElementById('barbershop-name');
  const barbershopSlugInput = document.getElementById('barbershop-slug');
  const phoneInput = document.getElementById('owner-phone');
  const docTypeSelect = document.getElementById('doc-type');
  const docNumberInput = document.getElementById('doc-number');
  const ownerNameInput = document.getElementById('owner-name');
  const emailInput = document.getElementById('owner-email');
  const passInput = document.getElementById('owner-password');
  const confirmPassInput = document.getElementById('owner-confirm-password');
  const btnSubmit = document.getElementById('btn-submit');
  const successModal = document.getElementById('success-modal');
  const errorAlert = document.getElementById('error-alert');
  const errorMessage = document.getElementById('error-message');

  function showError(msg) {
    errorMessage.textContent = msg;
    errorAlert.classList.remove('hidden');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function hideError() {
    errorAlert.classList.add('hidden');
  }

  // Olho da senha
  const togglePassBtn = document.getElementById('toggle-password');
  const toggleConfirmBtn = document.getElementById('toggle-confirm-password');

  function toggleField(input, btn) {
    const isPass = input.type === 'password';
    input.type = isPass ? 'text' : 'password';
    btn.querySelector('i').className = isPass ? 'ph ph-eye-slash text-base' : 'ph ph-eye text-base';
  }

  if (togglePassBtn) togglePassBtn.addEventListener('click', () => toggleField(passInput, togglePassBtn));
  if (toggleConfirmBtn) toggleConfirmBtn.addEventListener('click', () => toggleField(confirmPassInput, toggleConfirmBtn));

  // Máscara WhatsApp
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

  // Alterna Tipo de Documento (CPF / CNPJ)
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
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '');
  }

  barbershopNameInput.addEventListener('input', (e) => {
    barbershopSlugInput.value = gerarSlug(e.target.value);
  });

  // AÇÃO DE CADASTRO
  btnSubmit.addEventListener('click', async (e) => {
    e.preventDefault();
    hideError();

    const shopName = barbershopNameInput.value.trim();
    const phone = phoneInput.value.trim();
    const docType = docTypeSelect.value;
    const docNumber = docNumberInput.value.trim();
    const ownerName = ownerNameInput.value.trim();
    const email = emailInput.value.trim();
    const password = passInput.value;
    const confirmPassword = confirmPassInput.value;
    const slug = barbershopSlugInput.value.trim();

    // Validações locais claras
    if (!shopName) return showError('Por favor, digite o nome da sua barbearia.');
    if (!phone) return showError('Por favor, informe seu número de WhatsApp.');
    if (!docNumber) return showError('Por favor, informe o número do documento (CPF ou CNPJ).');
    if (!ownerName) return showError('Por favor, informe o nome do responsável.');
    if (!email) return showError('Por favor, informe um endereço de e-mail válido.');
    if (!password) return showError('Por favor, crie uma senha.');
    if (password.length < 6) return showError('A senha deve ter no mínimo 6 caracteres.');
    if (password !== confirmPassword) return showError('A confirmação da senha não confere. Digite a mesma senha nos dois campos.');
    if (!slug) return showError('Por favor, defina o link exclusivo da barbearia.');

    if (!supabaseClient) {
      return showError('Erro de conexão: a biblioteca do banco não foi carregada. Verifique se está conectado à internet.');
    }

    btnSubmit.disabled = true;
    btnSubmit.innerHTML = '<i class="ph-bold ph-spinner animate-spin text-lg"></i> Salvando dados...';

    try {
      // 1. Cadastra no Supabase Auth
      const { data: authData, error: authError } = await supabaseClient.auth.signUp({
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

      if (!authData || !authData.user) {
        throw new Error('Não foi possível gerar a conta de usuário. Verifique se o e-mail já existe.');
      }

      // 2. Insere a barbearia
      const { error: shopError } = await supabaseClient.from('barbershops').insert([
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
          throw new Error(`O link "${slug}" já está registrado por outra barbearia. Altere o link e tente novamente.`);
        }
        throw shopError;
      }

      // Sucesso
      const modalMsg = document.getElementById('success-msg');
      modalMsg.textContent = `A barbearia "${shopName}" foi cadastrada com sucesso! Enviamos uma confirmação para o e-mail ${email}. (Caso não encontre na caixa principal, olhe também na pasta de Spam ou Lixo Eletrônico).`;
      successModal.classList.remove('hidden');

    } catch (err) {
      console.error('Erro ao cadastrar:', err);
      showError(err.message || 'Ocorreu um erro ao conectar com o servidor.');
      btnSubmit.disabled = false;
      btnSubmit.innerHTML = 'Cadastrar Barbearia <i class="ph-bold ph-check"></i>';
    }
  });
});
