-- ==============================================================================
-- AGENLITS: LEITURA PÚBLICA PARA CATÁLOGO DE SERVIÇOS (20260918020000)
-- ==============================================================================

BEGIN;

-- Permite que clientes e visitantes anónimos façam JOIN com barbershops para ler nome, slug e avatar
DROP POLICY IF EXISTS "Leitura publica vitrine barbershops" ON public.barbershops;
CREATE POLICY "Leitura publica vitrine barbershops"
ON public.barbershops FOR SELECT
TO anon, authenticated
USING (true);

COMMIT;
