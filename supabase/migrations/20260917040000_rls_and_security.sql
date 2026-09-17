-- ==============================================================================
-- AGENLITS: RLS & SECURITY DEFINITIVA (20260917040000_rls_and_security.sql)
-- ==============================================================================

-- 1. TABELA SUBSCRIPTIONS OFICIAL
CREATE TABLE IF NOT EXISTS public.subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barbershop_id UUID NOT NULL REFERENCES public.barbershops(id) ON DELETE CASCADE UNIQUE,
  provider TEXT NOT NULL DEFAULT 'asaas',
  external_id TEXT UNIQUE,
  status TEXT NOT NULL DEFAULT 'trialing' CHECK (status IN ('trialing', 'active', 'past_due', 'cancelled', 'pending')),
  amount_cents INTEGER NOT NULL DEFAULT 7900,
  payment_method TEXT DEFAULT 'pix' CHECK (payment_method IN ('pix', 'credit_card', 'boleto')),
  current_period_start TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  current_period_end TIMESTAMPTZ DEFAULT (timezone('utc'::text, now()) + interval '30 days') NOT NULL,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. HABILITAR ROW LEVEL SECURITY (RLS) EM TODAS AS TABELAS
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointment_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.waitlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

-- 3. POLICIES: ORGANIZATIONS & MEMBERS
DROP POLICY IF EXISTS "Membros leem sua organizacao" ON public.organizations;
CREATE POLICY "Membros leem sua organizacao" ON public.organizations FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.organization_members om WHERE om.organization_id = organizations.id AND om.user_id = auth.uid()));

DROP POLICY IF EXISTS "Membros leem outros membros da organizacao" ON public.organization_members;
CREATE POLICY "Membros leem outros membros da organizacao" ON public.organization_members FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.organization_members om WHERE om.organization_id = organization_members.organization_id AND om.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins gerenciam membros da organizacao" ON public.organization_members;
CREATE POLICY "Admins gerenciam membros da organizacao" ON public.organization_members FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.organization_members om WHERE om.organization_id = organization_members.organization_id AND om.user_id = auth.uid() AND om.role IN ('owner', 'admin')));

-- 4. POLICIES: PRODUCTS (ISOLAMENTO MULTI-TENANT E PROTEÇÃO DE CUSTO)
DROP POLICY IF EXISTS "Dono gerencia produtos de sua loja" ON public.products;
CREATE POLICY "Dono gerencia produtos de sua loja" ON public.products FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.barbershops b WHERE b.id = products.barbershop_id AND b.owner_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.barbershops b WHERE b.id = products.barbershop_id AND b.owner_id = auth.uid()));

-- 5. POLICIES: WAITLISTS (PROTEÇÃO DE PRIVACIDADE E DADOS LGPD)
DROP POLICY IF EXISTS "Dono gerencia fila de espera" ON public.waitlists;
CREATE POLICY "Dono gerencia fila de espera" ON public.waitlists FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.barbershops b WHERE b.id = waitlists.barbershop_id AND b.owner_id = auth.uid()));

DROP POLICY IF EXISTS "Cliente insere na fila publica" ON public.waitlists;
CREATE POLICY "Cliente insere na fila publica" ON public.waitlists FOR INSERT TO anon, authenticated
  WITH CHECK (true);

-- 6. POLICIES: APPOINTMENT_ITEMS
DROP POLICY IF EXISTS "Dono gerencia itens de agendamentos" ON public.appointment_items;
CREATE POLICY "Dono gerencia itens de agendamentos" ON public.appointment_items FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.appointments a 
    JOIN public.barbershops b ON b.id = a.barbershop_id 
    WHERE a.id = appointment_items.appointment_id AND b.owner_id = auth.uid()
  ));

-- 7. POLICIES: SUBSCRIPTIONS
DROP POLICY IF EXISTS "Dono visualiza sua propria assinatura" ON public.subscriptions;
CREATE POLICY "Dono visualiza sua propria assinatura" ON public.subscriptions FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.barbershops b WHERE b.id = subscriptions.barbershop_id AND b.owner_id = auth.uid()));

-- 8. TRIGGER DE SEGURANÇA: BLOQUEIA AUTOPROMOÇÃO DE PLANOS NO CLIENTE
CREATE OR REPLACE FUNCTION public.protect_barbershop_subscription_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Se houver tentativa de alterar plano ou status da assinatura
  IF (NEW.plan IS DISTINCT FROM OLD.plan OR NEW.subscription_status IS DISTINCT FROM OLD.subscription_status) THEN
    -- Permite alteração APENAS se executada via service_role ou por super admin da plataforma
    IF (current_setting('request.jwt.claims', true)::jsonb->>'role' != 'service_role') 
       AND NOT public.is_platform_admin() 
       AND current_user NOT IN ('postgres', 'service_role') THEN
      RAISE EXCEPTION 'Acesso negado: o plano só pode ser alterado via confirmação de pagamento do gateway.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_barbershop_subscription ON public.barbershops;
CREATE TRIGGER trg_protect_barbershop_subscription
  BEFORE UPDATE ON public.barbershops
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_barbershop_subscription_columns();
