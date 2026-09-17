-- ==============================================================================
-- AGENLITS: PADRONIZAÇÃO MONETÁRIA *_CENTS & SLUGS RESERVADOS (20260917050000_standardize_cents_and_slugs.sql)
-- ==============================================================================

BEGIN;

-- 1. DROP TEMPORÁRIO DA VIEW DEPENDENTE
DROP VIEW IF EXISTS public.financial_dashboard CASCADE;

-- 2. PADRONIZAÇÃO DA TABELA PRODUCTS PARA price_cents
ALTER TABLE public.products 
  ADD COLUMN IF NOT EXISTS price_cents INTEGER,
  ADD COLUMN IF NOT EXISTS cost_price_cents INTEGER DEFAULT 0;

-- Converte valores numéricos legados em centavos inteiros se necessário
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'price') THEN
    UPDATE public.products SET price_cents = ROUND(COALESCE(price, 0) * 100)::INTEGER WHERE price_cents IS NULL;
    ALTER TABLE public.products DROP COLUMN price;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'cost_price') THEN
    UPDATE public.products SET cost_price_cents = ROUND(COALESCE(cost_price, 0) * 100)::INTEGER WHERE cost_price_cents IS NULL OR cost_price_cents = 0;
    ALTER TABLE public.products DROP COLUMN cost_price;
  END IF;
END $$;

ALTER TABLE public.products ALTER COLUMN price_cents SET DEFAULT 0;

-- 3. PADRONIZAÇÃO DA TABELA APPOINTMENT_ITEMS PARA price_cents
ALTER TABLE public.appointment_items 
  ADD COLUMN IF NOT EXISTS price_cents INTEGER;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'appointment_items' AND column_name = 'price') THEN
    UPDATE public.appointment_items SET price_cents = ROUND(COALESCE(price, 0) * 100)::INTEGER WHERE price_cents IS NULL;
    ALTER TABLE public.appointment_items DROP COLUMN price;
  END IF;
END $$;

ALTER TABLE public.appointment_items ALTER COLUMN price_cents SET DEFAULT 0;

-- 4. PADRONIZAÇÃO DA TABELA SUBSCRIPTIONS PARA amount_cents
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'subscriptions' AND column_name = 'amount') THEN
    ALTER TABLE public.subscriptions ADD COLUMN IF NOT EXISTS amount_cents INTEGER DEFAULT 7900;
    UPDATE public.subscriptions SET amount_cents = ROUND(COALESCE(amount, 0) * 100)::INTEGER WHERE amount_cents IS NULL;
    ALTER TABLE public.subscriptions DROP COLUMN amount;
  END IF;
END $$;

-- 5. RECIAÇÃO DA VIEW ANALÍTICA FINANCIAL_DASHBOARD (100% EM CENTAVOS INTEIROS)
CREATE OR REPLACE VIEW public.financial_dashboard AS
SELECT 
  a.barbershop_id,
  DATE(a.starts_at) AS date,
  b.id AS barber_id,
  b.name AS barber_name,
  COUNT(a.id) AS total_appointments,
  COALESCE(SUM(ai.price_cents), 0) AS gross_revenue_cents,
  COALESCE(ROUND(SUM(ai.price_cents * (ai.commission_percentage / 100.0))), 0) AS barber_commission_cents,
  COALESCE(SUM(ai.price_cents), 0) - COALESCE(ROUND(SUM(ai.price_cents * (ai.commission_percentage / 100.0))), 0) AS shop_net_revenue_cents
FROM public.appointments a
LEFT JOIN public.appointment_items ai ON ai.appointment_id = a.id
LEFT JOIN public.barbers b ON b.id = COALESCE(ai.barber_id, a.barber_id)
WHERE a.status = 'done'
GROUP BY a.barbershop_id, DATE(a.starts_at), b.id, b.name;

-- 6. ATUALIZAÇÃO DA FUNÇÃO check_slug_available COM TODOS OS SLUGS RESERVADOS DO SAAS
CREATE OR REPLACE FUNCTION public.check_slug_available(
  p_slug text,
  p_current_shop_id uuid default null
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
  v_reserved text[] := ARRAY[
    -- Rotas do Sistema / Administrativas
    'admin', 'login', 'api', 'painel', 'explorar', 'agendar', 'cliente', 'servicos', 
    'fotos', 'horarios', 'barbeiros', 'cadastro', 'perfil',
    -- Páginas e Módulos do SaaS
    'planos', 'configuracoes', 'relatorios', 'equipe', 'caixacomanda', 'clientes-loja', 
    'termos', 'esqueci-senha', 'redefinir-senha', 'privacidade',
    -- Termos Técnicos e Reservados
    'app', 'auth', 'checkout', 'webhook', 'suporte', 'static', 'assets', 'public'
  ];
  v_clean_slug text;
  v_exists boolean;
BEGIN
  v_clean_slug := lower(trim(p_slug));

  IF v_clean_slug = ANY(v_reserved) THEN
    RETURN jsonb_build_object('available', false, 'reason', 'Este link é reservado pelo sistema.');
  END IF;

  IF length(v_clean_slug) < 3 THEN
    RETURN jsonb_build_object('available', false, 'reason', 'O link deve ter no mínimo 3 caracteres.');
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.barbershops
    WHERE slug = v_clean_slug
      AND (p_current_shop_id IS NULL OR id <> p_current_shop_id)
  ) INTO v_exists;

  IF v_exists THEN
    RETURN jsonb_build_object('available', false, 'reason', 'Este link já está em uso por outro estabelecimento.');
  END IF;

  RETURN jsonb_build_object('available', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_slug_available(text, uuid) TO anon, authenticated;

COMMIT;
