// Doc utilisateur P9 — seul moyen fourni par Apple de mettre à jour une Live Activity (écran
// verrouillé / Dynamic Island) pendant que l'app est suspendue en arrière-plan : un push APNs
// dédié (`apns-push-type: liveactivity`), envoyé ici depuis un serveur plutôt que depuis l'app
// elle-même (qui ne tourne justement plus). Appelée par l'hôte (le seul appareil qui fait foi sur
// le journal) juste après chaque `syncHostLog`, jamais par les pairs.
//
// Ne stocke jamais le score : uniquement les jetons de push (`live_activity_tokens`, RLS), lus ici
// avec la clé `service_role` (injectée automatiquement par le runtime Edge Functions, jamais commit
// dans le repo). Le score transite uniquement dans le corps de la requête reçue et celui envoyé à
// APNs, jamais persisté côté serveur.
import { createClient } from "jsr:@supabase/supabase-js@2";

interface Standing {
  id: string;
  name: string;
  score: number;
}

interface ContentState {
  roundNumber: number;
  standings: Standing[];
  isStale: boolean;
}

interface PushRequest {
  matchID: string;
  event: "update" | "end";
  contentState: ContentState;
}

const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID")!;
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID")!;
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY")!;
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "com.cacompte.app";
// Doc utilisateur — `CaCompte.entitlements` déclare `aps-environment: development` tant que l'app
// n'est distribuée qu'en debug/TestFlight interne ; il faudra basculer cette variable (et
// l'entitlement) sur "production" au passage App Store / TestFlight public.
const APNS_ENVIRONMENT = Deno.env.get("APNS_ENVIRONMENT") ?? "development";
const APNS_HOST = APNS_ENVIRONMENT === "production"
  ? "api.push.apple.com"
  : "api.sandbox.push.apple.com";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

let cachedKey: CryptoKey | null = null;
// Doc utilisateur — Apple recommande de réutiliser le même jeton fournisseur ~55 min plutôt que
// d'en resigner un par requête (limite de fréquence documentée par Apple sur ces jetons).
let cachedProviderToken: { token: string; issuedAt: number } | null = null;

function base64URLFromBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64URLFromString(value: string): string {
  return base64URLFromBytes(new TextEncoder().encode(value));
}

async function importApnsKey(): Promise<CryptoKey> {
  if (cachedKey) return cachedKey;
  const pemBody = APNS_PRIVATE_KEY
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(pemBody);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  cachedKey = await crypto.subtle.importKey(
    "pkcs8",
    bytes.buffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  return cachedKey;
}

/// Jeton fournisseur APNs (JWT ES256, doc Apple « Establishing a token-based connection ») —
/// distinct du jeton de push par appareil stocké dans `live_activity_tokens`.
async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedProviderToken && now - cachedProviderToken.issuedAt < 55 * 60) {
    return cachedProviderToken.token;
  }
  const key = await importApnsKey();
  const header = base64URLFromString(JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID }));
  const claims = base64URLFromString(JSON.stringify({ iss: APNS_TEAM_ID, iat: now }));
  const unsigned = `${header}.${claims}`;
  // Doc utilisateur — `crypto.subtle.sign` avec ECDSA/P-256 rend directement la signature au
  // format brut R||S (64 octets) qu'attend un JWT ES256 (RFC 7518), pas le DER que produit
  // OpenSSL par défaut : aucune conversion supplémentaire n'est nécessaire ici.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsigned),
  );
  const token = `${unsigned}.${base64URLFromBytes(new Uint8Array(signature))}`;
  cachedProviderToken = { token, issuedAt: now };
  return token;
}

async function sendToToken(pushToken: string, body: PushRequest): Promise<{ ok: boolean; shouldForget: boolean }> {
  const token = await providerToken();
  const payload: Record<string, unknown> = {
    aps: {
      timestamp: Math.floor(Date.now() / 1000),
      event: body.event,
      "content-state": body.contentState,
    },
  };
  const response = await fetch(`https://${APNS_HOST}/3/device/${pushToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${token}`,
      "apns-topic": `${APNS_BUNDLE_ID}.push-type.liveactivity`,
      "apns-push-type": "liveactivity",
      "apns-priority": "10",
    },
    body: JSON.stringify(payload),
  });
  if (response.ok) return { ok: true, shouldForget: false };
  // Doc utilisateur — un jeton révoqué/expiré ne redeviendra jamais valide : autant nettoyer
  // `live_activity_tokens` tout de suite plutôt que de le retenter indéfiniment à chaque manche.
  const shouldForget = response.status === 400 || response.status === 410;
  return { ok: false, shouldForget };
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  let body: PushRequest;
  try {
    body = await request.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }
  if (!body.matchID || !body.contentState || !body.event) {
    return new Response("Missing matchID, event or contentState", { status: 400 });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: tokens, error } = await supabase
    .from("live_activity_tokens")
    .select("device_id, push_token")
    .eq("match_id", body.matchID);

  if (error) {
    return new Response(`Failed to load tokens: ${error.message}`, { status: 500 });
  }
  if (!tokens || tokens.length === 0) {
    return Response.json({ sent: 0, failed: 0 });
  }

  const results = await Promise.allSettled(
    tokens.map(async (row) => {
      const result = await sendToToken(row.push_token, body);
      if (result.shouldForget) {
        await supabase
          .from("live_activity_tokens")
          .delete()
          .eq("match_id", body.matchID)
          .eq("device_id", row.device_id);
      }
      return result.ok;
    }),
  );

  const sent = results.filter((r) => r.status === "fulfilled" && r.value).length;
  const failed = results.length - sent;
  return Response.json({ sent, failed });
});
