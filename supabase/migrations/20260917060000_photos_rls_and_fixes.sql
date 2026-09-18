-- ==============================================================================
-- AGENLITS: RLS DE FOTOS, POLÍTICAS PÚBLICAS & SINCRONIZAÇÃO (20260917060000_photos_rls_and_fixes.sql)
-- ==============================================================================

BEGIN;

-- 1. HABILITAR RLS NA TABELA BARBERSHOP_PHOTOS
ALTER TABLE public.barbershop_photos ENABLE ROW LEVEL SECURITY;

-- 2. POLICIES PARA BARBERSHOP_PHOTOS
DROP POLICY IF EXISTS "Leitura publica de fotos da barbearia" ON public.barbershop_photos;
CREATE POLICY "Leitura publica de fotos da barbearia"
  ON public.barbershop_photos
  FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "Dono gerencia fotos da sua barbearia" ON public.barbershop_photos;
CREATE POLICY "Dono gerencia fotos da sua barbearia"
  ON public.barbershop_photos
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.barbershops b
      WHERE b.id = barbershop_photos.barbershop_id
        AND b.owner_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.barbershops b
      WHERE b.id = barbershop_photos.barbershop_id
        AND b.owner_id = auth.uid()
    )
  );

-- 3. GARANTIR COLUNAS DE ANTECEDÊNCIA DE CANCELAMENTO NA TABELA BARBERSHOPS
ALTER TABLE public.barbershops
  ADD COLUMN IF NOT EXISTS cancel_lead_hours INTEGER DEFAULT 2,
  ADD COLUMN IF NOT EXISTS cancellation_window_hours INTEGER DEFAULT 2;

UPDATE public.barbershops
SET cancellation_window_hours = COALESCE(cancellation_window_hours, cancel_lead_hours, 2),
    cancel_lead_hours = COALESCE(cancel_lead_hours, cancellation_window_hours, 2);

COMMIT;
