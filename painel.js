// agenlits - Script do Painel Administrativo com Proteção de Sessão
const SUPABASE_URL = 'https://fdoceyjcibzdfiqvdzkv.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZkb2NleWpjaWJ6ZGZpcXZkemt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzODkyOTEsImV4cCI6MjEwNDk2NTI5MX0.v6Jj0Fn7u1HEAHl-zq5SZTmGxCIeHXs2a-vTSgtFm-A';

const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

document.addEventListener('DOMContentLoaded', async () => {
  const userNameEl = document.getElementById('user-display-name');
  const userEmailEl = document.getElementById('user-display-email');
  const shopNameTitle = document.getElementById('shop-name-title');
  const publicLinkText = document.getElementById('public-link-text');
  const btnCopyLink = document.getElementById('btn-copy-link');
  const btnLogout = document.getElementById('btn-logout');

  // 1. VERIFICAR SE O USUÁRIO ESTÁ LOGADO
  const { data: { session }, error: sessionError } = await supabase.auth.getSession();

  if (sessionError || !session) {
    // Não está logado: redireciona imediatamente para o login
    alert('Você precisa estar logado para acessar o painel.');
    window.location.href = 'login.html';
    return;
  }

  const user = session.user;
  userEmailEl.textContent = user.email;
  userNameEl.textContent = user.user_metadata?.full_name || 'Administrador';

  // 2. BUSCAR DADOS DA BARBEARIA DO USUÁRIO LOGADO
  try {
    const { data: barbershop, error: shopError } = await supabase
      .from('barbershops')
      .select('*')
      .eq('owner_id', user.id)
      .single();

    if (barbershop) {
      shopNameTitle.textContent = barbershop.name;
      const fullUrl = `agenlits.com/${barbershop.slug}`;
      publicLinkText.textContent = fullUrl;

      // Botão Copiar Link
      btnCopyLink.addEventListener('click', () => {
        navigator.clipboard.writeText(`https://${fullUrl}`);
        btnCopyLink.innerHTML = '<i class="ph-bold ph-check"></i> Copiado!';
        setTimeout(() => {
          btnCopyLink.innerHTML = '<i class="ph-bold ph-copy"></i> Copiar Link';
        }, 2500);
      });
    } else {
      shopNameTitle.textContent = 'Minha Barbearia';
      publicLinkText.textContent = 'Configure seu link nas configurações';
    }
  } catch (err) {
    console.error('Erro ao carregar barbearia:', err);
  }

  // 3. BOTÃO DE SAÍDA (LOGOUT)
  btnLogout.addEventListener('click', async () => {
    if (confirm('Deseja realmente sair da sua conta?')) {
      btnLogout.disabled = true;
      btnLogout.innerHTML = '<i class="ph-bold ph-spinner animate-spin"></i> Saindo...';
      
      await supabase.auth.signOut();
      window.location.href = 'login.html';
    }
  });
});
