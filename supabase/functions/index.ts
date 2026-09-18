// ==============================================================================
// SUPABASE EDGE FUNCTION: CRON DE DISPARO DE LEMBRETES (send-reminders)
// ==============================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // 1. Busca mensagens pendentes que já atingiram o horário de envio
    const nowIso = new Date().toISOString();
    const { data: notifications, error } = await supabaseAdmin
      .from("notification_queue")
      .select("*")
      .eq("status", "pending")
      .lte("scheduled_for", nowIso)
      .limit(50);

    if (error) throw error;

    if (!notifications || notifications.length === 0) {
      return new Response(JSON.stringify({ message: "Nenhum lembrete pendente para processar." }), { status: 200 });
    }

    const evolutionApiUrl = Deno.env.get("WHATSAPP_API_URL"); // Ex: https://api.z-api.io ou Evolution API
    const evolutionApiKey = Deno.env.get("WHATSAPP_API_KEY");

    let sentCount = 0;

    for (const notif of notifications) {
      let success = false;
      const cleanPhone = notif.phone.replace(/\D/g, "");

      if (evolutionApiUrl && evolutionApiKey) {
        try {
          const res = await fetch(`${evolutionApiUrl}/message/sendText`, {
            method: "POST",
            headers: {
              "apikey": evolutionApiKey,
              "Content-Type": "application/json"
            },
            body: JSON.stringify({
              number: `55${cleanPhone}`,
              text: notif.message
            })
          });
          if (res.ok) success = true;
        } catch (e) {
          console.error("Erro no envio do WhatsApp:", e);
        }
      } else {
        // Modo sandbox/simulação caso não haja chave configurada
        console.log(`[DISPARO SIMULADO] Para: ${cleanPhone} | Mensagem: ${notif.message}`);
        success = true;
      }

      await supabaseAdmin
        .from("notification_queue")
        .update({
          status: success ? "sent" : "failed",
          sent_at: success ? new Date().toISOString() : null
        })
        .eq("id", notif.id);

      if (success) sentCount++;
    }

    return new Response(JSON.stringify({
      success: true,
      processed: notifications.length,
      sent: sentCount
    }), {
      headers: { "Content-Type": "application/json" },
      status: 200
    });

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      headers: { "Content-Type": "application/json" },
      status: 500
    });
  }
});
