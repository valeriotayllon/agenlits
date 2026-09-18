// ==============================================================================
// SUPABASE EDGE FUNCTION: CRIAR COBRANÇA ASAAS (supabase/functions/create-checkout/index.ts)
// ==============================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

    // 1. Validação estrita do token JWT do usuário chamador
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Token de autorização ausente" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token);
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Sessão inválida ou expirada" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    const { barbershop_id, plan, amount_cents, payment_method } = await req.json();

    if (!barbershop_id) {
      return new Response(JSON.stringify({ error: "barbershop_id é obrigatório" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    // 2. Valida se o usuário autenticado é o proprietário da barbearia
    const { data: shop, error: shopErr } = await supabaseAdmin
      .from("barbershops")
      .select("id, name, document_number, phone, owner_id")
      .eq("id", barbershop_id)
      .single();

    if (shopErr || !shop) {
      return new Response(JSON.stringify({ error: "Barbearia não encontrada" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 404,
      });
    }

    if (shop.owner_id !== user.id) {
      return new Response(JSON.stringify({ error: "Acesso negado: apenas o dono pode gerar assinaturas para esta barbearia" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 403,
      });
    }

    // 3. Validação do Gateway (Fail-Closed: bloqueia checkout se gateway não estiver configurado)
    const asaasApiKey = Deno.env.get("ASAAS_API_KEY");
    if (!asaasApiKey) {
      return new Response(JSON.stringify({ 
        error: "Gateway de pagamento não configurado no ambiente. Entre em contato com o suporte da plataforma." 
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 503,
      });
    }

    const asaasEnv = Deno.env.get("ASAAS_ENVIRONMENT") || "sandbox";
    const asaasBaseUrl = asaasEnv === "production" 
      ? "https://api.asaas.com/v3" 
      : "https://sandbox.asaas.com/api/v3";

    // Criar ou buscar cliente no Asaas
    const customerRes = await fetch(`${asaasBaseUrl}/customers`, {
      method: "POST",
      headers: {
        "access_token": asaasApiKey,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        name: shop.name,
        cpfCnpj: shop.document_number,
        mobilePhone: shop.phone
      })
    });
    const customerData = await customerRes.json();
    const customerId = customerData.id;

    const validatedAmount = plan === 'pro_annual' ? 79000 : 7900; // Validação server-side do valor

    // Criar cobrança oficial no Asaas
    const paymentRes = await fetch(`${asaasBaseUrl}/payments`, {
      method: "POST",
      headers: {
        "access_token": asaasApiKey,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        customer: customerId,
        billingType: payment_method === "card" ? "CREDIT_CARD" : "PIX",
        value: validatedAmount / 100,
        dueDate: new Date(Date.now() + 2 * 86400000).toISOString().split("T")[0],
        description: `Assinatura Agenlits Pro - ${shop.name}`,
        externalReference: barbershop_id
      })
    });
    const paymentData = await paymentRes.json();
    const externalId = paymentData.id;

    let pixQrCode = null;
    let pixPayload = null;

    if (payment_method === "pix" && externalId) {
      const qrRes = await fetch(`${asaasBaseUrl}/payments/${externalId}/pixQrCode`, {
        headers: { "access_token": asaasApiKey }
      });
      const qrData = await qrRes.json();
      pixQrCode = qrData.encodedImage;
      pixPayload = qrData.payload;
    }

    await supabaseAdmin.from("subscriptions").upsert({
      barbershop_id: barbershop_id,
      provider: "asaas",
      external_id: externalId,
      status: "pending",
      amount_cents: validatedAmount,
      payment_method: payment_method || "pix"
    }, { onConflict: "barbershop_id" });

    return new Response(JSON.stringify({
      success: true,
      subscription_id: externalId,
      pix_qrcode: pixQrCode,
      pix_payload: pixPayload
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
