// agenlits - Login integrado ao Supabase com Redirecionamento para o Painel
const SUPABASE_URL = 'https://fdoceyjcibzdfiqvdzkv.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZkb2NleWpjaWJ6ZGZpcXZkemt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzODkyOTEsImV4cCI6MjEwNDk2NTI5MX0.v6Jj0Fn7u1HEAHl-zq5SZTmGxCIeHXs2a-vTSgtFm-A';

const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

document.addEventListener('DOMContentLoaded', () => {
  const loginForm = document.getElementById('login-form');
  const btnLogin = document.getElementById('btn-login');
  const loginError = document.getElementById('login-error');

  loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    loginError.classList.add('hidden');

    const email = document.getElementById('login-email').value.trim();
    const password = document.getElementById('login-password').value;

    btnLogin.disabled = true;
    btnLogin.innerHTML = '<i class="ph-bold ph-spinner animate-spin text-lg"></i> Entrando...';

    try {
      const { data, error } = await supabase.auth.signInWithPassword({
        email: email,
        password: password
      });

      if (error) throw error;

      // Redireciona imediatamente para a Página Inicial do Sistema (Painel)
      window.location.href = 'painel.html';

    } catch (err) {
      loginError.textContent = 'Erro ao entrar: ' + (err.message || 'Verifique suas credenciais.');
      loginError.classList.remove('hidden');
      btnLogin.disabled = false;
      btnLogin.innerHTML = 'Entrar na Minha Barbearia <i class="ph-bold ph-sign-in"></i>';
    }
  });
});
