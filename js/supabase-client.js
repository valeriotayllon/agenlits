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

/**
 * Formata estritamente centavos inteiros para moeda Real brasileira (BRL).
 * Sem adivinhação: 100 -> R$ 1,00 | 15000 -> R$ 150,00 | 0 -> R$ 0,00
 * @param {number|string} cents - Valor expresso estritamente em centavos.
 * @returns {string} Valor formatado em BRL.
 */
function formatBRL(cents) {
  const c = typeof cents === 'number' ? Math.round(cents) : parseInt(cents || 0, 10);
  return ((isNaN(c) ? 0 : c) / 100).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  });
}

/**
 * Converte valor em reais (float ou string de input) para centavos inteiros.
 * @param {number|string} valInReais - Ex: 150.50 ou "150,50"
 * @returns {number} Centavos inteiros (ex: 15050)
 */
function toCents(valInReais) {
  if (typeof valInReais === 'string') {
    valInReais = parseFloat(valInReais.replace(/\./g, '').replace(',', '.'));
  }
  return Math.round((Number(valInReais) || 0) * 100);
}
