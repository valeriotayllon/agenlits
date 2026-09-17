-- ==============================================================================
-- SAAS EXPANSION: ORGANIZAÇÕES, PRODUTOS, COMANDAS E VIEW FINANCEIRA (20260917020000)
-- ==============================================================================

-- 1. Multi-unidade: Organizações e Membros
CREATE TABLE IF NOT EXISTS organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS organization_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT CHECK (role IN ('owner', 'admin', 'staff')) DEFAULT 'staff',
  UNIQUE(organization_id, user_id)
);

-- 2. Atualização de Barbershops com suporte a Planos e Organização
ALTER TABLE barbershops 
  ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS plan TEXT CHECK (plan IN ('trial', 'pro', 'enterprise', 'canceled')) DEFAULT 'trial',
  ADD COLUMN IF NOT EXISTS subscription_status TEXT CHECK (subscription_status IN ('active', 'past_due', 'canceled', 'trialing')) DEFAULT 'trialing',
  ADD COLUMN IF NOT EXISTS trial_ends_at TIMESTAMPTZ DEFAULT (now() + interval '14 days'),
  ADD COLUMN IF NOT EXISTS gateway_customer_id TEXT,
  ADD COLUMN IF NOT EXISTS gateway_subscription_id TEXT,
  ADD COLUMN IF NOT EXISTS cancel_lead_hours INT DEFAULT 2;

-- 3. Faturamento, Comandas e Produtos
CREATE TABLE IF NOT EXISTS products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barbershop_id UUID REFERENCES barbershops(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  price NUMERIC(10,2) NOT NULL,
  cost_price NUMERIC(10,2) DEFAULT 0,
  stock INT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS appointment_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id UUID REFERENCES appointments(id) ON DELETE CASCADE,
  product_id UUID REFERENCES products(id),
  service_id UUID REFERENCES services(id),
  price NUMERIC(10,2) NOT NULL,
  barber_id UUID REFERENCES barbers(id),
  commission_percentage NUMERIC(5,2) DEFAULT 0
);

-- 4. Fila de Espera
CREATE TABLE IF NOT EXISTS waitlists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barbershop_id UUID REFERENCES barbershops(id) ON DELETE CASCADE,
  client_name TEXT NOT NULL,
  client_phone TEXT NOT NULL,
  barber_id UUID REFERENCES barbers(id),
  preferred_date DATE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 5. View Analítica Financeira Oficial (Usando starts_at e status 'done')
CREATE OR REPLACE VIEW financial_dashboard AS
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
JOIN appointment_items ai ON ai.appointment_id = a.id
JOIN barbers b ON b.id = ai.barber_id
WHERE a.status = 'done'
GROUP BY a.barbershop_id, DATE(a.starts_at), b.id, b.name;
