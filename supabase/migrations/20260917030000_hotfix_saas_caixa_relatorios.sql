-- ==============================================================================
-- AGENLITS: HOTFIX SAAS DEFINITIVO v12 (20260917030000_hotfix_saas_caixa_relatorios.sql)
-- ==============================================================================

-- 1. CORREÇÃO DA TABELA PRODUCTS
ALTER TABLE public.products 
  ADD COLUMN IF NOT EXISTS price_cents INTEGER,
  ADD COLUMN IF NOT EXISTS stock_quantity INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS cost_price NUMERIC(10,2) DEFAULT 0;

UPDATE public.products 
SET price_cents = COALESCE(price_cents, ROUND(COALESCE(price, 0) * 100)::integer)
WHERE price_cents IS NULL;

UPDATE public.products
SET stock_quantity = COALESCE(stock_quantity, stock, 0)
WHERE stock_quantity IS NULL;

-- 2. RPC: AGENDAMENTO MANUAL DE BALCÃO PELO PAINEL (create_walkin_appointment)
CREATE OR REPLACE FUNCTION public.create_walkin_appointment(
  p_barbershop_id uuid,
  p_barber_id uuid,
  p_service_id uuid,
  p_client_name text,
  p_client_phone text,
  p_starts_at timestamptz,
  p_notes text default null
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_duration int;
  v_price_cents int;
  v_ends_at timestamptz;
  v_appointment_id uuid;
  v_assigned_barber_id uuid := p_barber_id;
BEGIN
  IF NOT (
    EXISTS (SELECT 1 FROM public.barbershops b WHERE b.id = p_barbershop_id AND b.owner_id = auth.uid())
    OR public.is_platform_admin()
  ) THEN
    RAISE EXCEPTION 'Permissão negada. Apenas o estabelecimento pode criar agendamentos de balcão.';
  END IF;

  SELECT COALESCE(duration_minutes, 30), price_cents
    INTO v_duration, v_price_cents
  FROM public.services
  WHERE id = p_service_id AND barbershop_id = p_barbershop_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Serviço não encontrado.';
  END IF;

  v_ends_at := p_starts_at + (v_duration || ' minutes')::interval;

  IF v_assigned_barber_id IS NULL THEN
    SELECT id INTO v_assigned_barber_id
    FROM public.barbers
    WHERE barbershop_id = p_barbershop_id AND is_active = true
    LIMIT 1;
  END IF;

  INSERT INTO public.appointments (
    barbershop_id,
    barber_id,
    service_id,
    client_name,
    client_phone,
    starts_at,
    ends_at,
    price_cents,
    notes,
    status
  ) VALUES (
    p_barbershop_id,
    v_assigned_barber_id,
    p_service_id,
    p_client_name,
    p_client_phone,
    p_starts_at,
    v_ends_at,
    COALESCE(v_price_cents, 0),
    p_notes,
    'confirmed'
  )
  RETURNING id INTO v_appointment_id;

  RETURN jsonb_build_object('success', true, 'appointment_id', v_appointment_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_walkin_appointment(uuid, uuid, uuid, text, text, timestamptz, text) TO authenticated;

-- 3. RPC ATÔMICA: FECHAMENTO DE COMANDA & CAIXA (checkout_comanda)
CREATE OR REPLACE FUNCTION public.checkout_comanda(
  p_barbershop_id uuid,
  p_appointment_id uuid,
  p_barber_id uuid,
  p_client_name text,
  p_client_phone text,
  p_payment_method text,
  p_total_cents integer,
  p_services jsonb,
  p_products jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_apt_id uuid := p_appointment_id;
  v_first_service_id uuid;
  v_item jsonb;
  v_barber_comm numeric(5,2) := 0;
BEGIN
  IF NOT (
    EXISTS (SELECT 1 FROM public.barbershops b WHERE b.id = p_barbershop_id AND b.owner_id = auth.uid())
    OR public.is_platform_admin()
  ) THEN
    RAISE EXCEPTION 'Permissão negada para movimentar o caixa desta loja.';
  END IF;

  IF p_barber_id IS NOT NULL THEN
    SELECT COALESCE(commission_percentage, 0) INTO v_barber_comm
    FROM public.barbers WHERE id = p_barber_id;
  END IF;

  IF v_apt_id IS NULL THEN
    IF jsonb_array_length(p_services) > 0 THEN
      v_first_service_id := (p_services->0->>'service_id')::uuid;
    ELSE
      SELECT id INTO v_first_service_id FROM public.services WHERE barbershop_id = p_barbershop_id LIMIT 1;
    END IF;

    INSERT INTO public.appointments (
      barbershop_id,
      barber_id,
      service_id,
      client_name,
      client_phone,
      starts_at,
      ends_at,
      price_cents,
      status,
      notes
    ) VALUES (
      p_barbershop_id,
      p_barber_id,
      v_first_service_id,
      COALESCE(p_client_name, 'Cliente Balcão'),
      COALESCE(p_client_phone, ''),
      now(),
      now(),
      p_total_cents,
      'done',
      'Venda avulsa via ' || UPPER(p_payment_method)
    )
    RETURNING id INTO v_apt_id;
  ELSE
    UPDATE public.appointments
    SET status = 'done',
        price_cents = p_total_cents,
        barber_id = COALESCE(p_barber_id, barber_id),
        notes = COALESCE(notes || ' | ', '') || 'Pago via ' || UPPER(p_payment_method)
    WHERE id = v_apt_id;
  END IF;

  DELETE FROM public.appointment_items WHERE appointment_id = v_apt_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_services)
  LOOP
    INSERT INTO public.appointment_items (
      appointment_id,
      service_id,
      price,
      barber_id,
      commission_percentage
    ) VALUES (
      v_apt_id,
      (v_item->>'service_id')::uuid,
      ((v_item->>'price_cents')::numeric / 100.0),
      p_barber_id,
      v_barber_comm
    );
  END LOOP;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_products)
  LOOP
    INSERT INTO public.appointment_items (
      appointment_id,
      product_id,
      price,
      barber_id,
      commission_percentage
    ) VALUES (
      v_apt_id,
      (v_item->>'product_id')::uuid,
      (((v_item->>'price_cents')::numeric * (v_item->>'quantity')::numeric) / 100.0),
      p_barber_id,
      0
    );

    UPDATE public.products
    SET stock_quantity = GREATEST(0, COALESCE(stock_quantity, 0) - (v_item->>'quantity')::integer),
        stock = GREATEST(0, COALESCE(stock, 0) - (v_item->>'quantity')::integer)
    WHERE id = (v_item->>'product_id')::uuid;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'appointment_id', v_apt_id,
    'total_cents', p_total_cents
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.checkout_comanda(uuid, uuid, uuid, text, text, text, integer, jsonb, jsonb) TO authenticated;

-- 4. RPC: RELATÓRIOS FINANCEIROS ROBUSTOS (get_financial_report)
DROP FUNCTION IF EXISTS public.get_financial_report(uuid, timestamptz, timestamptz);
DROP FUNCTION IF EXISTS public.get_financial_report(uuid, date, date);

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
  v_gross_revenue_cents bigint := 0;
  v_total_completed integer := 0;
  v_total_cancelled integer := 0;
  v_total_no_show integer := 0;
  v_barbers_commissions jsonb;
  v_top_services jsonb;
BEGIN
  IF NOT (
    EXISTS (SELECT 1 FROM public.barbershops b WHERE b.id = p_barbershop_id AND b.owner_id = auth.uid())
    OR public.is_platform_admin()
  ) THEN
    RAISE EXCEPTION 'Permissão negada para consultar o financeiro deste estabelecimento.';
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

-- 5. VIEW ANALÍTICA OFICIAL ATUALIZADA
CREATE OR REPLACE VIEW public.financial_dashboard AS
SELECT 
  a.barbershop_id,
  DATE(a.starts_at) AS date,
  b.id AS barber_id,
  b.name AS barber_name,
  COUNT(a.id) AS total_appointments,
  COALESCE(SUM(ai.price), 0) AS gross_revenue,
  COALESCE(SUM(ai.price * (ai.commission_percentage / 100)), 0) AS barber_commission,
  COALESCE(SUM(ai.price - (ai.price * (ai.commission_percentage / 100))), 0) AS shop_net_revenue
FROM appointments a
LEFT JOIN appointment_items ai ON ai.appointment_id = a.id
LEFT JOIN barbers b ON b.id = COALESCE(ai.barber_id, a.barber_id)
WHERE a.status = 'done'
GROUP BY a.barbershop_id, DATE(a.starts_at), b.id, b.name;
