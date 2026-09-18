-- ==============================================================================
-- AGENLITS: ATUALIZAÇÃO OFICIAL v16 (20260917070000_staff_security_and_cleanup.sql)
-- ==============================================================================

BEGIN;

-- 1. POLICIES PARA BARBEIROS (COLUNA OFICIAL: barbershop_id)
DROP POLICY IF EXISTS "Barbeiros podem inserir agendamentos na loja" ON public.appointments;
CREATE POLICY "Barbeiros podem inserir agendamentos na loja"
ON public.appointments FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.barbers
    WHERE barbers.user_id = auth.uid()
      AND barbers.barbershop_id = appointments.barbershop_id
  )
);

DROP POLICY IF EXISTS "Barbeiros podem atualizar seus proprios agendamentos" ON public.appointments;
CREATE POLICY "Barbeiros podem atualizar seus proprios agendamentos"
ON public.appointments FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.barbers
    WHERE barbers.user_id = auth.uid()
      AND (barbers.id = appointments.barber_id OR barbers.barbershop_id = appointments.barbershop_id)
  )
);

DROP POLICY IF EXISTS "Barbeiro ve a si mesmo e loja gerencia equipe" ON public.barbers;
CREATE POLICY "Barbeiro ve a si mesmo e loja gerencia equipe"
ON public.barbers FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.barbershops b
    WHERE b.id = barbers.barbershop_id AND b.owner_id = auth.uid()
  )
);

-- 2. REMOÇÃO DE SCHEMA MORTO (ORGANIZATIONS / MULTI-UNIDADE)
DROP TABLE IF EXISTS public.organization_members CASCADE;
DROP TABLE IF EXISTS public.organizations CASCADE;

-- 3. REMOÇÃO DO TRIGGER MORTO HANDLE_NEW_SHOP_OWNER
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_shop_owner();

-- 4. RPC CHECKOUT_COMANDA COM VALIDAÇÃO SERVER-SIDE DE PREÇOS
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
      'Venda via ' || UPPER(p_payment_method)
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
    SELECT price_cents INTO v_server_service_price
    FROM public.services
    WHERE id = (v_item->>'service_id')::uuid AND barbershop_id = p_barbershop_id;

    IF v_server_service_price IS NULL THEN
      RAISE EXCEPTION 'Serviço % inválido ou não pertence a esta barbearia.', v_item->>'service_id';
    END IF;

    v_calculated_total := v_calculated_total + v_server_service_price;

    INSERT INTO public.appointment_items (
      appointment_id,
      service_id,
      price_cents,
      barber_id,
      commission_percentage
    ) VALUES (
      v_apt_id,
      (v_item->>'service_id')::uuid,
      v_server_service_price,
      p_barber_id,
      v_barber_comm
    );
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

    INSERT INTO public.appointment_items (
      appointment_id,
      product_id,
      price_cents,
      barber_id,
      commission_percentage
    ) VALUES (
      v_apt_id,
      (v_item->>'product_id')::uuid,
      (v_server_product_price * COALESCE((v_item->>'quantity')::integer, 1)),
      p_barber_id,
      0
    );

    UPDATE public.products
    SET stock_quantity = GREATEST(0, COALESCE(stock_quantity, 0) - (v_item->>'quantity')::integer)
    WHERE id = (v_item->>'product_id')::uuid;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'appointment_id', v_apt_id,
    'total_cents', p_total_cents,
    'verified_catalog_total_cents', v_calculated_total
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.checkout_comanda(uuid, uuid, uuid, text, text, text, integer, jsonb, jsonb) TO authenticated;

COMMIT;
