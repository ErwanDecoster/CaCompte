// Doc 09 « Fin de partie » — termine une Live Activity restée inactive plus de 30 minutes (aucune
// manche, aucun changement de partie) : remontée utilisateur, l'écran verrouillé restait affiché
// des heures après l'arrêt réel du jeu (`markStale` grise le contenu mais ne le retire jamais).
// Rien côté app ne peut le faire de façon fiable pendant que le processus est suspendu
// (`Task.sleep` ne survit pas à la mise en veille) — seul un push déclenché depuis l'extérieur le
// peut, exactement comme les mises à jour de score (`cacompte-live-activity-push`).
//
// Appelée uniquement par un déclencheur planifié (Cron Trigger Supabase, toutes les 5-10 min),
// jamais par l'app.
//
// Doc utilisateur — le code de signature APNs est dupliqué avec `cacompte-live-activity-push`
// plutôt que factorisé dans un dossier `_shared` : un import relatif hors du dossier de la
// fonction n'est pas fiable selon la méthode de déploiement (constaté en recette — le bundler
// distant échoue à résoudre `../_shared/apns.ts`), alors que chaque fonction reste déployable
// isolément une fois autonome.
import { createClient } from "jsr:@supabase/supabase-js@2";

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
const INACTIVITY_THRESHOLD_MINUTES = 30;

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
/// distinct du jeton de push par appareil stocké dans `cacompte_live_activity_tokens`.
async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedProviderToken && now - cachedProviderToken.issuedAt < 55 * 60) {
    return cachedProviderToken.token;
  }
  const key = await importApnsKey();
  const header = base64URLFromString(JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID }));
  const claims = base64URLFromString(JSON.stringify({ iss: APNS_TEAM_ID, iat: now }));
  const unsigned = `${header}.${claims}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsigned),
  );
  const token = `${unsigned}.${base64URLFromBytes(new Uint8Array(signature))}`;
  cachedProviderToken = { token, issuedAt: now };
  return token;
}

async function sendToToken(pushToken: string, body: { event: "update" | "end"; contentState: unknown }): Promise<{ ok: boolean; shouldForget: boolean }> {
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
  const shouldForget = response.status === 400 || response.status === 410;
  return { ok: false, shouldForget };
}

interface TokenRow {
  activity_key: string;
  device_id: string;
  push_token: string;
  last_content_state: unknown;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const threshold = new Date(Date.now() - INACTIVITY_THRESHOLD_MINUTES * 60 * 1000).toISOString();

  const { data: rows, error } = await supabase
    .from("cacompte_live_activity_tokens")
    .select("activity_key, device_id, push_token, last_content_state")
    .lt("updated_at", threshold);

  if (error) {
    return new Response(`Failed to load stale tokens: ${error.message}`, { status: 500 });
  }
  if (!rows || rows.length === 0) {
    return Response.json({ ended: 0 });
  }

  const results = await Promise.allSettled(
    (rows as TokenRow[]).map(async (row) => {
      // Best-effort : que le push APNs réussisse ou non, ce jeton n'a plus de raison de rester en
      // base une fois jugé inactif — un jeton révoqué serait de toute façon nettoyé par
      // `cacompte-live-activity-push` au prochain essai, autant le faire tout de suite ici.
      await sendToToken(row.push_token, { event: "end", contentState: row.last_content_state ?? {} });
      await supabase
        .from("cacompte_live_activity_tokens")
        .delete()
        .eq("activity_key", row.activity_key)
        .eq("device_id", row.device_id);
    }),
  );

  const ended = results.filter((r) => r.status === "fulfilled").length;
  return Response.json({ ended, total: rows.length });
});
