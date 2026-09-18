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
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const { barbershop_id, plan, amount_cents, payment_method } = await req.json();

    if (!barbershop_id) {
      return new Response(JSON.stringify({ error: "barbershop_id é obrigatório" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    const { data: shop, error: shopErr } = await supabaseAdmin
      .from("barbershops")
      .select("id, name, document_number, phone")
      .eq("id", barbershop_id)
      .single();

    if (shopErr || !shop) {
      return new Response(JSON.stringify({ error: "Barbearia não encontrada" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 404,
      });
    }

    const asaasApiKey = Deno.env.get("ASAAS_API_KEY");
    const asaasEnv = Deno.env.get("ASAAS_ENVIRONMENT") || "sandbox";
    const asaasBaseUrl = asaasEnv === "production" 
      ? "https://api.asaas.com/v3" 
      : "https://sandbox.asaas.com/api/v3";

    let externalId = `sub_${Date.now()}`;
    let pixQrCode = null;
    let pixPayload = null;

    if (asaasApiKey) {
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

      const paymentRes = await fetch(`${asaasBaseUrl}/payments`, {
        method: "POST",
        headers: {
          "access_token": asaasApiKey,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          customer: customerId,
          billingType: payment_method === "card" ? "CREDIT_CARD" : "PIX",
          value: (amount_cents || 7900) / 100,
          dueDate: new Date(Date.now() + 2 * 86400000).toISOString().split("T")[0],
          description: `Assinatura Agenlits Pro - ${shop.name}`,
          externalReference: barbershop_id
        })
      });
      const paymentData = await paymentRes.json();
      externalId = paymentData.id || externalId;

      if (payment_method === "pix" && paymentData.id) {
        const qrRes = await fetch(`${asaasBaseUrl}/payments/${paymentData.id}/pixQrCode`, {
          headers: { "access_token": asaasApiKey }
        });
        const qrData = await qrRes.json();
        pixQrCode = qrData.encodedImage;
        pixPayload = qrData.payload;
      }
    } else {
      pixPayload = `00020126580014br.gov.bcb.pix0136${barbershop_id}5204000053039865405${((amount_cents||7900)/100).toFixed(2)}5802BR5913AGENLITS6009FORTALEZA62070503***6304E2CA`;
    }

    await supabaseAdmin.from("subscriptions").upsert({
      barbershop_id: barbershop_id,
      provider: "asaas",
      external_id: externalId,
      status: "pending",
      amount_cents: amount_cents || 7900,
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
