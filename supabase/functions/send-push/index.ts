// Supabase Edge Function — invia notifiche push FCM per like e richieste cerchia.
//
// Setup nel dashboard Supabase:
//   1. Secrets → aggiungi FIREBASE_PROJECT_ID e FIREBASE_SERVICE_ACCOUNT_KEY
//      (FIREBASE_SERVICE_ACCOUNT_KEY = contenuto JSON del Service Account di Firebase)
//   2. Database Webhooks → crea due webhook:
//        • tabella "likes"       INSERT → questa function
//        • tabella "connections" INSERT → questa function
//
// Nel progetto Firebase:
//   Project Settings → Service Accounts → Generate new private key → scarica il JSON
//   e incollane il contenuto (stringa JSON su una riga) come secret FIREBASE_SERVICE_ACCOUNT_KEY.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID")!;
const SERVICE_ACCOUNT_JSON = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_KEY")!;

// ─── FCM HTTP v1 ──────────────────────────────────────────────────────────────

async function getAccessToken(): Promise<string> {
  const sa = JSON.parse(SERVICE_ACCOUNT_JSON);
  const now = Math.floor(Date.now() / 1000);

  const header = btoa(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = btoa(
    JSON.stringify({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })
  );

  const signingInput = `${header}.${payload}`;

  // Import RSA private key
  const pemKey = sa.private_key.replace(/\\n/g, "\n");
  const keyData = pemKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binaryKey = Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput)
  );

  const jwt = `${signingInput}.${btoa(
    String.fromCharCode(...new Uint8Array(signature))
  )
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "")}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const { access_token } = await tokenRes.json();
  return access_token;
}

async function sendFcm(
  fcmToken: string,
  title: string,
  body: string,
  data: Record<string, string>
) {
  const accessToken = await getAccessToken();
  await fetch(
    `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: { title, body },
          data,
          android: { priority: "high" },
          apns: {
            payload: { aps: { "content-available": 1 } },
          },
        },
      }),
    }
  );
}

// ─── Handler principale ───────────────────────────────────────────────────────

serve(async (req) => {
  try {
    const payload = await req.json();
    const record = payload.record as Record<string, string>;
    const table = payload.table as string;

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    if (table === "likes") {
      const memoryId = record.memory_id;
      const likerId = record.user_id;

      // Trova proprietario del ricordo e il suo token FCM
      const { data: memory } = await supabase
        .from("memories")
        .select("user_id, description")
        .eq("id", memoryId)
        .single();
      if (!memory || memory.user_id === likerId) {
        return new Response("skip", { status: 200 });
      }

      const { data: owner } = await supabase
        .from("profiles")
        .select("fcm_token")
        .eq("id", memory.user_id)
        .single();
      if (!owner?.fcm_token) return new Response("no token", { status: 200 });

      const { data: liker } = await supabase
        .from("profiles")
        .select("display_name, username")
        .eq("id", likerId)
        .single();
      const likerName =
        liker?.display_name || liker?.username || "Qualcuno";

      const desc = (memory.description as string) ?? "";
      const short = desc.length > 30 ? desc.slice(0, 30) + "…" : desc;

      await sendFcm(
        owner.fcm_token,
        `${likerName} ha messo like`,
        `"${short}"`,
        { type: "like", memoryId, fromUsername: likerName }
      );
    } else if (table === "connections") {
      const requesterId = record.requester_id;
      const targetId = record.target_id;

      const { data: target } = await supabase
        .from("profiles")
        .select("fcm_token")
        .eq("id", targetId)
        .single();
      if (!target?.fcm_token) return new Response("no token", { status: 200 });

      const { data: requester } = await supabase
        .from("profiles")
        .select("display_name, username")
        .eq("id", requesterId)
        .single();
      const requesterName =
        requester?.display_name || requester?.username || "Qualcuno";

      await sendFcm(
        target.fcm_token,
        "Nuova richiesta di cerchia",
        `${requesterName} vuole aggiungerti alla sua cerchia`,
        { type: "connection_request", fromUsername: requesterName }
      );
    }

    return new Response("ok", { status: 200 });
  } catch (e) {
    return new Response(String(e), { status: 500 });
  }
});
