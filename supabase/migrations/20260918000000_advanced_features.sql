-- ==============================================================================
-- AGENLITS: FEATURES AVANÇADAS SAAS (20260918000000_advanced_features.sql)
-- ==============================================================================

BEGIN;

-- 1. SINAL / PRÉ-PAGAMENTO PIX (REDUÇÃO DE NO-SHOW)
ALTER TABLE public.barbershops
  ADD COLUMN IF NOT EXISTS requires_deposit BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS deposit_percentage INTEGER DEFAULT 30; -- Ex: 30% de sinal

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS deposit_cents INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS deposit_paid BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS deposit_pix_code TEXT,
  ADD COLUMN IF NOT EXISTS google_event_id TEXT;

-- 2. AVALIAÇÕES PÓS-ATENDIMENTO (REVIEWS)
CREATE TABLE IF NOT EXISTS public.reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barbershop_id UUID NOT NULL REFERENCES public.barbershops(id) ON DELETE CASCADE,
  appointment_id UUID UNIQUE REFERENCES public.appointments(id) ON DELETE SET NULL,
  barber_id UUID REFERENCES public.barbers(id) ON DELETE SET NULL,
  client_name TEXT NOT NULL,
  rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Leitura publica de avaliacoes" ON public.reviews;
CREATE POLICY "Leitura publica de avaliacoes" ON public.reviews FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "Insercao de avaliacao pelo cliente" ON public.reviews;
CREATE POLICY "Insercao de avaliacao pelo cliente" ON public.reviews FOR INSERT TO anon, authenticated WITH CHECK (true);

-- 3. PROGRAMA DE FIDELIDADE & CASHBACK
ALTER TABLE public.barbershops
  ADD COLUMN IF NOT EXISTS loyalty_enabled BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS loyalty_goal INTEGER DEFAULT 10; -- A cada 10 cortes, 1 grátis

CREATE TABLE IF NOT EXISTS public.loyalty_stamps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barbershop_id UUID NOT NULL REFERENCES public.barbershops(id) ON DELETE CASCADE,
  client_phone TEXT NOT NULL,
  appointment_id UUID REFERENCES public.appointments(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.loyalty_stamps ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Dono gere selos de fidelidade" ON public.loyalty_stamps;
CREATE POLICY "Dono gere selos de fidelidade" ON public.loyalty_stamps FOR ALL TO authenticated
USING (public.get_staff_role(barbershop_id) IN ('owner', 'admin', 'receptionist'))
WITH CHECK (public.get_staff_role(barbershop_id) IN ('owner', 'admin', 'receptionist'));

-- 4. CLUBES DE ASSINATURA / RECORRÊNCIA PARA CLIENTES FINAIS (Ex: R$ 99/mês)
CREATE TABLE IF NOT EXISTS public.client_membership_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barbershop_id UUID NOT NULL REFERENCES public.barbershops(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  price_cents INTEGER NOT NULL,
  billing_interval TEXT NOT NULL CHECK (billing_interval IN ('monthly', 'quarterly', 'yearly')) DEFAULT 'monthly',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.client_membership_plans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Leitura publica de planos de assinatura" ON public.client_membership_plans;
CREATE POLICY "Leitura publica de planos de assinatura" ON public.client_membership_plans FOR SELECT TO anon, authenticated USING (is_active = true);

DROP POLICY IF EXISTS "Dono gere planos de membros" ON public.client_membership_plans;
CREATE POLICY "Dono gere planos de membros" ON public.client_membership_plans FOR ALL TO authenticated
USING (public.get_staff_role(barbershop_id) IN ('owner', 'admin'))
WITH CHECK (public.get_staff_role(barbershop_id) IN ('owner', 'admin'));

-- 5. FILA DE LEMBRETES AUTOMÁTICOS (WHATSAPP CRON / PG_CRON)
CREATE TABLE IF NOT EXISTS public.notification_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id UUID NOT NULL REFERENCES public.appointments(id) ON DELETE CASCADE,
  barbershop_id UUID NOT NULL REFERENCES public.barbershops(id) ON DELETE CASCADE,
  phone TEXT NOT NULL,
  message TEXT NOT NULL,
  notification_type TEXT NOT NULL CHECK (notification_type IN ('instant_confirmation', 'reminder_24h', 'review_invite')),
  status TEXT NOT NULL CHECK (status IN ('pending', 'sent', 'failed')) DEFAULT 'pending',
  scheduled_for TIMESTAMPTZ NOT NULL,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.notification_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Sistema gere fila de notificacoes" ON public.notification_queue;
CREATE POLICY "Sistema gere fila de notificacoes" ON public.notification_queue FOR ALL TO authenticated
USING (public.get_staff_role(barbershop_id) IN ('owner', 'admin', 'receptionist'));

-- 6. TRIGGER QUE AGENDA LEMBRETE 24H E ENVIO AUTOMÁTICO DE NOTIFICAÇÃO
CREATE OR REPLACE FUNCTION public.queue_appointment_notifications()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_shop_name TEXT;
  v_service_name TEXT;
  v_date_str TEXT;
  v_time_str TEXT;
BEGIN
  -- Apenas quando for criado como 'confirmed'
  IF NEW.status = 'confirmed' AND NEW.client_phone IS NOT NULL AND LENGTH(NEW.client_phone) >= 10 THEN
    SELECT name INTO v_shop_name FROM public.barbershops WHERE id = NEW.barbershop_id;
    SELECT name INTO v_service_name FROM public.services WHERE id = NEW.service_id;
    
    v_date_str := to_char(NEW.starts_at AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY');
    v_time_str := to_char(NEW.starts_at AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI');

    -- Notificação imediata de confirmação
    INSERT INTO public.notification_queue (
      appointment_id, barbershop_id, phone, message, notification_type, scheduled_for
    ) VALUES (
      NEW.id,
      NEW.barbershop_id,
      NEW.client_phone,
      'Olá ' || COALESCE(NEW.client_name, 'Cliente') || '! O seu agendamento para ' || COALESCE(v_service_name, 'Serviço') || ' em ' || COALESCE(v_shop_name, 'nossa barbearia') || ' foi CONFIRMADO para ' || v_date_str || ' às ' || v_time_str || '.',
      'instant_confirmation',
      now()
    );

    -- Lembrete preventivo 24h antes do horário marcado
    IF NEW.starts_at > (now() + interval '24 hours') THEN
      INSERT INTO public.notification_queue (
        appointment_id, barbershop_id, phone, message, notification_type, scheduled_for
      ) VALUES (
        NEW.id,
        NEW.barbershop_id,
        NEW.client_phone,
        'Lembrete agenlits: Amanhã às ' || v_time_str || ' tem atendimento agendado (' || COALESCE(v_service_name, 'Serviço') || ') em ' || COALESCE(v_shop_name, 'nossa barbearia') || '. Te esperamos!',
        'reminder_24h',
        NEW.starts_at - interval '24 hours'
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_queue_appointment_notifications ON public.appointments;
CREATE TRIGGER trg_queue_appointment_notifications
  AFTER INSERT ON public.appointments
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_appointment_notifications();

COMMIT;
