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

    const { action, ...payload } = await req.json();

    if (action === "delete_account") {
      await supabaseAdmin.from("barbershops").delete().eq("owner_id", user.id);
      await supabaseAdmin.from("clients").delete().eq("auth_user_id", user.id);
      const { error: deleteAuthError } = await supabaseAdmin.auth.admin.deleteUser(user.id);
      if (deleteAuthError) throw deleteAuthError;

      return new Response(JSON.stringify({ success: true, message: "Conta e dados excluídos definitivamente." }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200
      });
    }

    if (action === "link_barber_login") {
      const { barber_id, email, password } = payload;
      if (!barber_id || !email) {
        return new Response(JSON.stringify({ error: "barber_id e email são obrigatórios" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" }
        });
      }

      const { data: barber, error: bErr } = await supabaseAdmin
        .from("barbers")
        .select("id, barbershop_id, barbershops(owner_id)")
        .eq("id", barber_id)
        .single();

      if (bErr || !barber || barber.barbershops?.owner_id !== user.id) {
        return new Response(JSON.stringify({ error: "Sem permissão para gerir este profissional" }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" }
        });
      }

      let barberUserId = null;
      const pwd = password || "Mudar@123456";

      const { data: newUser, error: createErr } = await supabaseAdmin.auth.admin.createUser({
        email: email.trim().toLowerCase(),
        password: pwd,
        email_confirm: true,
        user_metadata: { user_type: "barber" }
      });

      if (createErr) {
        if (createErr.message.includes("already been registered") || createErr.message.includes("unique")) {
          const { data: listData } = await supabaseAdmin.auth.admin.listUsers();
          const found = listData?.users?.find((u: any) => u.email?.toLowerCase() === email.trim().toLowerCase());
          if (found) barberUserId = found.id;
        } else {
          throw createErr;
        }
      } else {
        barberUserId = newUser.user.id;
      }

      if (!barberUserId) {
        throw new Error("Não foi possível gerar conta de acesso para o e-mail informado.");
      }

      const { error: linkErr } = await supabaseAdmin
        .from("barbers")
        .update({ user_id: barberUserId })
        .eq("id", barber_id);

      if (linkErr) throw linkErr;

      return new Response(JSON.stringify({
        success: true,
        user_id: barberUserId,
        message: "Acesso do profissional configurado com sucesso!"
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200
      });
    }

    return new Response(JSON.stringify({ error: "Ação não reconhecida" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message || "Erro interno" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  }
});
