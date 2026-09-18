// ==============================================================================
// SUPABASE EDGE FUNCTION: WEBHOOK ASAAS (supabase/functions/asaas-webhook/index.ts)
// ==============================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
);

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // 1. Validação Fail-Closed: se ASAAS_WEBHOOK_SECRET não estiver configurado, REJEITA
  const expectedSecret = Deno.env.get("ASAAS_WEBHOOK_SECRET");
  if (!expectedSecret) {
    console.error("ERRO CRÍTICO: ASAAS_WEBHOOK_SECRET não configurado no ambiente.");
    return new Response(JSON.stringify({ error: "Webhook secret não configurado no servidor" }), { status: 500 });
  }

  const webhookToken = req.headers.get("asaas-access-token");
  if (!webhookToken || webhookToken !== expectedSecret) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
  }

  try {
    const payload = await req.json();
    const event = payload.event;
    const payment = payload.payment;

    if (!payment) {
      return new Response(JSON.stringify({ ignored: true }), { status: 200 });
    }

    const barbershopId = payment.externalReference;
    if (!barbershopId) {
      return new Response(JSON.stringify({ error: "Missing externalReference" }), { status: 400 });
    }

    // Pagamento confirmado ou recebido via Pix/Cartão
    if (event === "PAYMENT_RECEIVED" || event === "PAYMENT_CONFIRMED") {
      const { error: shopErr } = await supabaseAdmin
        .from("barbershops")
        .update({
          plan: "pro",
          subscription_status: "active"
        })
        .eq("id", barbershopId);

      if (shopErr) throw shopErr;

      await supabaseAdmin.from("subscriptions").upsert({
        barbershop_id: barbershopId,
        provider: "asaas",
        external_id: payment.subscription || payment.id,
        status: "active",
        amount_cents: Math.round((payment.value || 79) * 100),
        payment_method: payment.billingType ? payment.billingType.toLowerCase() : "pix",
        current_period_end: new Date(Date.now() + 30 * 86400000).toISOString()
      }, { onConflict: "barbershop_id" });
    }

    // Assinatura cancelada ou vencida
    if (event === "PAYMENT_OVERDUE" || event === "SUBSCRIPTION_CANCELLED") {
      await supabaseAdmin
        .from("barbershops")
        .update({
          subscription_status: event === "PAYMENT_OVERDUE" ? "past_due" : "cancelled"
        })
        .eq("id", barbershopId);
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      headers: { "Content-Type": "application/json" },
      status: 500,
    });
  }
});
