-- ==============================================================================
-- AGENLITS: CONTROLE DE ACESSO BASEADO EM FUNÇÕES (RBAC) - 20260917080000
-- ==============================================================================

BEGIN;

-- 1. TABELA DE MEMBROS E COLABORADORES DO ESTABELECIMENTO
CREATE TABLE IF NOT EXISTS public.barbershop_staff (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barbershop_id UUID NOT NULL REFERENCES public.barbershops(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'receptionist', 'barber')) DEFAULT 'receptionist',
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  UNIQUE(barbershop_id, user_id)
);

ALTER TABLE public.barbershop_staff ENABLE ROW LEVEL SECURITY;

-- 2. FUNÇÃO AUXILIAR PARA CONSULTAR PAPEL DO USUÁRIO
CREATE OR REPLACE FUNCTION public.get_staff_role(p_barbershop_id uuid)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT 
    CASE 
      WHEN EXISTS (SELECT 1 FROM public.barbershops WHERE id = p_barbershop_id AND owner_id = auth.uid()) THEN 'owner'
      WHEN public.is_platform_admin() THEN 'owner'
      ELSE (
        SELECT role FROM public.barbershop_staff 
        WHERE barbershop_id = p_barbershop_id AND user_id = auth.uid()
        LIMIT 1
      )
    END;
$$;

-- 3. POLICIES PARA BARBERSHOP_STAFF
DROP POLICY IF EXISTS "Membros leem a equipe da sua loja" ON public.barbershop_staff;
CREATE POLICY "Membros leem a equipe da sua loja"
ON public.barbershop_staff FOR SELECT
TO authenticated
USING (
  public.get_staff_role(barbershop_id) IN ('owner', 'admin', 'receptionist')
);

DROP POLICY IF EXISTS "Apenas dono ou admin gerenciam equipe" ON public.barbershop_staff;
CREATE POLICY "Apenas dono ou admin gerenciam equipe"
ON public.barbershop_staff FOR ALL
TO authenticated
USING (
  public.get_staff_role(barbershop_id) IN ('owner', 'admin')
)
WITH CHECK (
  public.get_staff_role(barbershop_id) IN ('owner', 'admin')
);

-- 4. ATUALIZAR RPC GET_FINANCIAL_REPORT (BLOQUEIA RECEPTIONIST E BARBER)
CREATE OR REPLACE FUNCTION public.get_financial_report(
  p_barbershop_id uuid,
  p_start_date timestamptz,
  p_end_date timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
  v_role text;
  v_gross_revenue_cents bigint := 0;
  v_total_completed integer := 0;
  v_total_cancelled integer := 0;
  v_total_no_show integer := 0;
  v_barbers_commissions jsonb;
  v_top_services jsonb;
BEGIN
  v_role := public.get_staff_role(p_barbershop_id);

  -- Apenas Proprietário ('owner') ou Gerente ('admin') têm acesso ao DRE e faturamento global
  IF v_role NOT IN ('owner', 'admin') THEN
    RAISE EXCEPTION 'Acesso negado: colaboradores com perfil de atendimento não possuem permissão para consultar relatórios financeiros.';
  END IF;

  SELECT COALESCE(SUM(price_cents), 0), COUNT(*)
    INTO v_gross_revenue_cents, v_total_completed
  FROM public.appointments
  WHERE barbershop_id = p_barbershop_id
    AND starts_at BETWEEN p_start_date AND p_end_date
    AND status = 'done';

  SELECT COUNT(*) INTO v_total_no_show
  FROM public.appointments
  WHERE barbershop_id = p_barbershop_id
    AND starts_at BETWEEN p_start_date AND p_end_date
    AND status = 'no_show';

  SELECT COUNT(*) INTO v_total_cancelled
  FROM public.appointments
  WHERE barbershop_id = p_barbershop_id
    AND starts_at BETWEEN p_start_date AND p_end_date
    AND status = 'cancelled';

  SELECT COALESCE(jsonb_agg(sub), '[]'::jsonb) INTO v_barbers_commissions
  FROM (
    SELECT
      b.id AS barber_id,
      b.name AS barber_name,
      b.commission_percentage,
      COUNT(a.id) AS appointments_count,
      COALESCE(SUM(a.price_cents), 0) AS total_produced_cents,
      COALESCE(ROUND(SUM(a.price_cents) * (b.commission_percentage / 100.0)), 0) AS commission_due_cents
    FROM public.barbers b
    LEFT JOIN public.appointments a ON a.barber_id = b.id 
      AND a.status = 'done'
      AND a.starts_at BETWEEN p_start_date AND p_end_date
    WHERE b.barbershop_id = p_barbershop_id
    GROUP BY b.id, b.name, b.commission_percentage
  ) sub;

  SELECT COALESCE(jsonb_agg(srv), '[]'::jsonb) INTO v_top_services
  FROM (
    SELECT
      s.name,
      COUNT(a.id) AS sales_count,
      SUM(a.price_cents) AS revenue_cents
    FROM public.appointments a
    JOIN public.services s ON s.id = a.service_id
    WHERE a.barbershop_id = p_barbershop_id
      AND a.status = 'done'
      AND a.starts_at BETWEEN p_start_date AND p_end_date
    GROUP BY s.name
    ORDER BY sales_count DESC
    LIMIT 5
  ) srv;

  RETURN jsonb_build_object(
    'gross_revenue_cents', v_gross_revenue_cents,
    'total_completed', v_total_completed,
    'total_no_show', v_total_no_show,
    'total_cancelled', v_total_cancelled,
    'barbers_commissions', v_barbers_commissions,
    'top_services', v_top_services
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_financial_report(uuid, timestamptz, timestamptz) TO authenticated;

-- 5. ATUALIZAR POLICIES DE AGENDAMENTOS PARA PERMITIR RECEPTIONIST
DROP POLICY IF EXISTS "Equipe gerencia agendamentos da loja" ON public.appointments;
CREATE POLICY "Equipe gerencia agendamentos da loja"
ON public.appointments FOR ALL
TO authenticated
USING (
  public.get_staff_role(barbershop_id) IN ('owner', 'admin', 'receptionist')
  OR EXISTS (SELECT 1 FROM public.barbers WHERE barbers.user_id = auth.uid() AND barbers.barbershop_id = appointments.barbershop_id)
)
WITH CHECK (
  public.get_staff_role(barbershop_id) IN ('owner', 'admin', 'receptionist')
  OR EXISTS (SELECT 1 FROM public.barbers WHERE barbers.user_id = auth.uid() AND barbers.barbershop_id = appointments.barbershop_id)
);

COMMIT;
