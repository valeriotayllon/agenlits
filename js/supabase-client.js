// ==============================================================================
// AGENLITS - SUPABASE CLIENT SINGLETON & UTILITIES (js/supabase-client.js)
// ==============================================================================
const SUPABASE_URL = 'https://fdoceyjcibzdfiqvdzkv.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZkb2NleWpjaWJ6ZGZpcXZkemt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzODkyOTEsImV4cCI6MjEwNDk2NTI5MX0.v6Jj0Fn7u1HEAHl-zq5SZTmGxCIeHXs2a-vTSgtFm-A';

window._agenlitsClient = window._agenlitsClient || (window.supabase ? window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY) : null);
const client = window._agenlitsClient;

function escapeHtml(str) {
  return String(str || '').replace(/[&<>'"]/g, t => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
  }[t]));
}

function formatBRL(centsOrVal) {
  const val = typeof centsOrVal === 'number' && centsOrVal > 100 && Number.isInteger(centsOrVal) 
    ? centsOrVal / 100 
    : Number(centsOrVal || 0);
  return val.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
}
