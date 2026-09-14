const SUPABASE_URL = 'https://fdoceyjcibzdfiqvdzkv.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZkb2NleWpjaWJ6ZGZpcXZkemt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzODkyOTEsImV4cCI6MjEwNDk2NTI5MX0.v6Jj0Fn7u1HEAHl-zq5SZTmGxCIeHXs2a-vTSgtFm-A';

const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

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

  const togglePassBtn = document.getElementById('toggle-password');
  const toggleConfirmBtn = document.getElementById('toggle-confirm-password');
  function toggleField(input, btn) {
    const isPass = input.type === 'password';
    input.type = isPass ? 'text' : 'password';
    btn.querySelector('i').className = isPass ? 'ph ph-eye-slash text-base' : 'ph ph-eye text-base';
  }
  if (togglePassBtn) togglePassBtn.addEventListener('click', () => toggleField(passInput, togglePassBtn));
  if (toggleConfirmBtn) toggleConfirmBtn.addEventListener('click', () => toggleField(confirmPassInput, toggleConfirmBtn));

  phoneInput.addEventListener('input', (e) => {
    let v = e.target.value.replace(/\D/g, '');
    if (v.length > 11) v = v.slice(0, 11);
    if (v.length > 10) e.target.value = `(${v.slice(0, 2)}) ${v.slice(2, 7)}-${v.slice(7)}`;
    else if (v.length > 6) e.target.value = `(${v.slice(0, 2)}) ${v.slice(2, 6)}-${v.slice(6)}`;
    else if (v.length > 2) e.target.value = `(${v.slice(0, 2)}) ${v.slice(2)}`;
    else e.target.value = v;
  });

  docTypeSelect.addEventListener('change', () => {
    docNumberInput.value = '';
    docNumberInput.placeholder = docTypeSelect.value === 'CPF' ? '000.000.000-00' : '00.000.000/0000-00';
    docNumberInput.maxLength = docTypeSelect.value === 'CPF' ? 14 : 18;
  });

  docNumberInput.addEventListener('input', (e) => {
    let v = e.target.value.replace(/\D/g, '');
    if (docTypeSelect.value === 'CPF') {
      if (v.length > 11) v = v.slice(0, 11);
      v = v.replace(/(\d{3})(\d)/, '$1.$2').replace(/(\d{3})(\d)/, '$1.$2').replace(/(\d{3})(\d{1,2})$/, '$1-$2');
    } else {
      if (v.length > 14) v = v.slice(0, 14);
      v = v.replace(/^(\d{2})(\d)/, '$1.$2').replace(/^(\d{2})\.(\d{3})(\d)/, '$1.$2.$3').replace(/\.(\d{3})(\d)/, '.$1/$2').replace(/(\d{4})(\d)/, '$1-$2');
    }
    e.target.value = v;
  });

  barbershopNameInput.addEventListener('input', (e) => {
    barbershopSlugInput.value = e.target.value.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  });

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

    if (!shopName || !phone || !docNumber || !ownerName || !email || !password || !slug) {
      return showError('Preencha todos os campos do formulário.');
    }
    if (password.length < 6) return showError('A senha deve ter no mínimo 6 caracteres.');
    if (password !== confirmPassword) return showError('As senhas digitadas não conferem.');

    btnSubmit.disabled = true;
    btnSubmit.innerHTML = '<i class="ph-bold ph-spinner animate-spin text-lg"></i> Cadastrando barbearia...';

    try {
      const { data: authData, error: authError } = await supabaseClient.auth.signUp({
        email: email,
        password: password,
        options: {
          data: { full_name: ownerName, phone: phone, document_type: docType, document_number: docNumber }
        }
      });

      if (authError) throw authError;

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
          throw new Error(`O link "${slug}" já existe. Escolha outro nome para a barbearia.`);
        }
        throw shopError;
      }

      document.getElementById('success-msg').textContent = `A barbearia "${shopName}" foi cadastrada com sucesso! Clique abaixo para entrar no seu painel.`;
      successModal.classList.remove('hidden');

    } catch (err) {
      showError(err.message || 'Erro ao realizar cadastro.');
      btnSubmit.disabled = false;
      btnSubmit.innerHTML = 'Cadastrar Barbearia <i class="ph-bold ph-check"></i>';
    }
  });
});
