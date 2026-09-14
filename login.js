// agenlits - Login Real integrado com Supabase
const SUPABASE_URL = 'https://fdoceyjcibzdfiqvdzkv.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZkb2NleWpjaWJ6ZGZpcXZkemt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzODkyOTEsImV4cCI6MjEwNDk2NTI5MX0.v6Jj0Fn7u1HEAHl-zq5SZTmGxCIeHXs2a-vTSgtFm-A';

const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

document.addEventListener('DOMContentLoaded', () => {
  const loginForm = document.getElementById('login-form');
  const btnLogin = document.getElementById('btn-login');

  loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();
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

      alert('Login realizado com sucesso! Bem-vindo(a) ao agenlits.');
      // Na próxima etapa, aqui redirecionaremos para painel.html
      window.location.href = 'index.html';

    } catch (err) {
      alert('Erro ao entrar: ' + err.message);
      btnLogin.disabled = false;
      btnLogin.innerHTML = 'Entrar na Minha Barbearia <i class="ph-bold ph-sign-in"></i>';
    }
  });
});
