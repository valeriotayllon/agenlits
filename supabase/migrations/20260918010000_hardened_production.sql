-- ==============================================================================
-- AGENLITS: PRODUÇÃO SEGURA & BLINDAGEM COMPLETA (20260918010000_hardened_production.sql)
-- ==============================================================================

BEGIN;

-- 1. CONSOLIDAÇÃO DE COLUNAS DE ANTECEDÊNCIA DE CANCELAMENTO
UPDATE public.barbershops
SET cancel_lead_hours = COALESCE(cancel_lead_hours, cancellation_window_hours, 2);

ALTER TABLE public.barbershops
  DROP COLUMN IF EXISTS cancellation_window_hours;

-- 2. REMOÇÃO DE SCHEMA MORTO: WAITLISTS (Zero UI)
DROP TABLE IF EXISTS public.waitlists CASCADE;

-- 3. VALIDAÇÃO DE ANTECEDÊNCIA DE CANCELAMENTO (cancel_lead_hours)
CREATE OR REPLACE FUNCTION public.change_appointment_status(
  p_appointment_id uuid,
  p_new_status text,
  p_reason text default null
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_shop_id uuid;
  v_client_id uuid;
  v_starts_at timestamptz;
  v_cancel_lead_hours int;
  v_min_cancel_time timestamptz;
  v_is_owner boolean := false;
BEGIN
  IF p_new_status NOT IN ('pending', 'confirmed', 'done', 'cancelled', 'no_show') THEN
    RAISE EXCEPTION 'Status inválido informado: %', p_new_status;
  END IF;

  SELECT a.barbershop_id, a.client_id, a.starts_at, COALESCE(b.cancel_lead_hours, 2)
    INTO v_shop_id, v_client_id, v_starts_at, v_cancel_lead_hours
  FROM public.appointments a
  JOIN public.barbershops b ON b.id = a.barbershop_id
  WHERE a.id = p_appointment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Agendamento não encontrado.';
  END IF;

  v_is_owner := EXISTS (
    SELECT 1 FROM public.barbershops b 
    WHERE b.id = v_shop_id AND b.owner_id = auth.uid()
  ) OR public.is_platform_admin();

  -- Se for cancelamento feito pelo próprio cliente
  IF p_new_status = 'cancelled' AND NOT v_is_owner THEN
    IF NOT EXISTS (SELECT 1 FROM public.clients c WHERE c.id = v_client_id AND c.auth_user_id = auth.uid()) THEN
      RAISE EXCEPTION 'Permissão negada para cancelar este agendamento.';
    END IF;

    v_min_cancel_time := v_starts_at - (v_cancel_lead_hours || ' hours')::interval;
    IF now() > v_min_cancel_time THEN
      RAISE EXCEPTION 'Cancelamento não permitido: o prazo limite de % horas de antecedência expirou.', v_cancel_lead_hours;
    END IF;
  END IF;

  IF NOT v_is_owner AND p_new_status <> 'cancelled' THEN
    RAISE EXCEPTION 'Permissão negada para alterar o status deste agendamento.';
  END IF;

  UPDATE public.appointments
  SET status = p_new_status,
      cancellation_reason = COALESCE(p_reason, cancellation_reason),
      updated_at = now()
  WHERE id = p_appointment_id;

  RETURN jsonb_build_object('success', true, 'status', p_new_status);
END;
$$;

GRANT EXECUTE ON FUNCTION public.change_appointment_status(uuid, text, text) TO authenticated;

-- 4. TRAVA REAL DE SAAS: BLOQUEIO DE AGENDAMENTOS EM LOJAS INADIMPLENTES OU TRIAL EXPIRADO
CREATE OR REPLACE FUNCTION public.book_appointment(
  p_barbershop_id uuid,
  p_barber_id uuid,
  p_service_id uuid,
  p_client_name text,
  p_client_phone text,
  p_starts_at timestamptz,
  p_client_id uuid default null,
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
  v_assigned_barber_id uuid := p_barber_id;
  v_appointment_id uuid;
  v_dow int;
  v_plan text;
  v_sub_status text;
  v_trial_ends_at timestamptz;
BEGIN
  IF p_client_name IS NULL OR trim(p_client_name) = '' THEN
    RAISE EXCEPTION 'O nome do cliente é obrigatório.';
  END IF;

  IF p_client_phone IS NULL OR trim(p_client_phone) = '' THEN
    RAISE EXCEPTION 'O WhatsApp do cliente é obrigatório.';
  END IF;

  -- Validação de assinatura / SaaS Gate
  SELECT plan, subscription_status, trial_ends_at
    INTO v_plan, v_sub_status, v_trial_ends_at
  FROM public.barbershops
  WHERE id = p_barbershop_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Estabelecimento não encontrado.';
  END IF;

  IF v_sub_status IN ('canceled', 'past_due') THEN
    RAISE EXCEPTION 'O sistema de agendamento deste estabelecimento está temporariamente indisponível devido a pendências na assinatura.';
  END IF;

  IF (v_plan = 'trial' OR v_sub_status = 'trialing') AND v_trial_ends_at IS NOT NULL AND now() > v_trial_ends_at THEN
    RAISE EXCEPTION 'O período de testes deste estabelecimento expirou. Por favor, solicite ao proprietário a ativação do plano.';
  END IF;

  SELECT COALESCE(duration_minutes, 30), price_cents
    INTO v_duration, v_price_cents
  FROM public.services
  WHERE id = p_service_id AND barbershop_id = p_barbershop_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Serviço não encontrado ou inativo no estabelecimento.';
  END IF;

  v_ends_at := p_starts_at + (v_duration || ' minutes')::interval;
  v_dow := extract(dow from p_starts_at);

  IF v_assigned_barber_id IS NULL THEN
    SELECT b.id INTO v_assigned_barber_id
    FROM public.barbers b
    WHERE b.barbershop_id = p_barbershop_id
      AND b.is_active = true
      AND (v_dow <> ALL(COALESCE(b.off_days, ARRAY[]::integer[])))
      AND (
        NOT EXISTS (SELECT 1 FROM public.barber_services bs WHERE bs.barber_id = b.id)
        OR EXISTS (SELECT 1 FROM public.barber_services bs WHERE bs.barber_id = b.id AND bs.service_id = p_service_id)
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.appointments a
        WHERE a.barber_id = b.id
          AND a.status IN ('confirmed', 'pending')
          AND tstzrange(a.starts_at, a.ends_at) && tstzrange(p_starts_at, v_ends_at)
      )
    LIMIT 1;

    IF v_assigned_barber_id IS NULL THEN
      RAISE EXCEPTION 'Nenhum profissional disponível para o horário e serviço selecionados.';
    END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM public.appointments a
      WHERE a.barber_id = v_assigned_barber_id
        AND a.status IN ('confirmed', 'pending')
        AND tstzrange(a.starts_at, a.ends_at) && tstzrange(p_starts_at, v_ends_at)
    ) THEN
      RAISE EXCEPTION 'O profissional selecionado já possui um agendamento conflitante neste horário.';
    END IF;
  END IF;

  INSERT INTO public.appointments (
    barbershop_id,
    barber_id,
    service_id,
    client_id,
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
    p_client_id,
    p_client_name,
    p_client_phone,
    p_starts_at,
    v_ends_at,
    COALESCE(v_price_cents, 0),
    p_notes,
    'confirmed'
  )
  RETURNING id INTO v_appointment_id;

  RETURN jsonb_build_object(
    'success', true,
    'appointment_id', v_appointment_id,
    'barber_id', v_assigned_barber_id,
    'starts_at', p_starts_at,
    'ends_at', v_ends_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.book_appointment TO anon, authenticated;

-- 5. VALIDAÇÃO SERVER-SIDE DO TOTAL NA COMANDA (appointments.price_cents = v_calculated_total)
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
  v_server_service_price integer;
  v_server_product_price integer;
  v_calculated_total integer := 0;
BEGIN
  IF NOT (
    EXISTS (SELECT 1 FROM public.barbershops b WHERE b.id = p_barbershop_id AND b.owner_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.barbers br WHERE br.barbershop_id = p_barbershop_id AND br.user_id = auth.uid())
    OR public.is_platform_admin()
  ) THEN
    RAISE EXCEPTION 'Permissão negada para movimentar o caixa desta loja.';
  END IF;

  IF p_barber_id IS NOT NULL THEN
    SELECT COALESCE(commission_percentage, 0) INTO v_barber_comm
    FROM public.barbers WHERE id = p_barber_id;
  END IF;

  -- Calcula o total real a partir do catálogo oficial
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_services)
  LOOP
    SELECT price_cents INTO v_server_service_price
    FROM public.services
    WHERE id = (v_item->>'service_id')::uuid AND barbershop_id = p_barbershop_id;

    IF v_server_service_price IS NULL THEN
      RAISE EXCEPTION 'Serviço % inválido ou não pertence a esta barbearia.', v_item->>'service_id';
    END IF;

    v_calculated_total := v_calculated_total + v_server_service_price;
  END LOOP;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_products)
  LOOP
    SELECT price_cents INTO v_server_product_price
    FROM public.products
    WHERE id = (v_item->>'product_id')::uuid AND barbershop_id = p_barbershop_id;

    IF v_server_product_price IS NULL THEN
      RAISE EXCEPTION 'Produto % inválido ou não pertence a esta barbearia.', v_item->>'product_id';
    END IF;

    v_calculated_total := v_calculated_total + (v_server_product_price * COALESCE((v_item->>'quantity')::integer, 1));
  END LOOP;

  -- Cria ou atualiza agendamento usando v_calculated_total como valor canônico de verdade
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
      v_calculated_total, -- VALOR VALIDADO SERVER-SIDE
      'done',
      'Venda via ' || UPPER(p_payment_method)
    )
    RETURNING id INTO v_apt_id;
  ELSE
    UPDATE public.appointments
    SET status = 'done',
        price_cents = v_calculated_total, -- VALOR VALIDADO SERVER-SIDE
        barber_id = COALESCE(p_barber_id, barber_id),
        notes = COALESCE(notes || ' | ', '') || 'Pago via ' || UPPER(p_payment_method),
        updated_at = now()
    WHERE id = v_apt_id;
  END IF;

  DELETE FROM public.appointment_items WHERE appointment_id = v_apt_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_services)
  LOOP
    SELECT price_cents INTO v_server_service_price
    FROM public.services
    WHERE id = (v_item->>'service_id')::uuid AND barbershop_id = p_barbershop_id;

    INSERT INTO public.appointment_items (
      appointment_id, service_id, price_cents, barber_id, commission_percentage
    ) VALUES (
      v_apt_id, (v_item->>'service_id')::uuid, v_server_service_price, p_barber_id, v_barber_comm
    );
  END LOOP;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_products)
  LOOP
    SELECT price_cents INTO v_server_product_price
    FROM public.products
    WHERE id = (v_item->>'product_id')::uuid AND barbershop_id = p_barbershop_id;

    INSERT INTO public.appointment_items (
      appointment_id, product_id, price_cents, barber_id, commission_percentage
    ) VALUES (
      v_apt_id, (v_item->>'product_id')::uuid, (v_server_product_price * COALESCE((v_item->>'quantity')::integer, 1)), p_barber_id, 0
    );

    UPDATE public.products
    SET stock_quantity = GREATEST(0, COALESCE(stock_quantity, 0) - (v_item->>'quantity')::integer)
    WHERE id = (v_item->>'product_id')::uuid;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'appointment_id', v_apt_id,
    'total_cents', v_calculated_total
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.checkout_comanda(uuid, uuid, uuid, text, text, text, integer, jsonb, jsonb) TO authenticated;

COMMIT;
