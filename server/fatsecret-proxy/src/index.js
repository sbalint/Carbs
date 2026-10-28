// Carbs ⇄ FatSecret proxy. Keeps the FatSecret secret off the phone and signs requests
// with OAuth 1.0 (no IP allow-list needed). Returns foods in the shape Carbs already uses.
//
// GET /search?q=greek+yogurt   → { foods: [Food] }  (top results with servings)
// GET /food/72532              → { food: Food }
// Every request needs the header  X-Carbs-Token: <APP_TOKEN>.

const API = "https://platform.fatsecret.com/rest/server.api";
const SEARCH_RESULTS = 12;
const FOOD_CACHE_SECONDS = 7 * 24 * 3600;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method !== "GET") return json({ error: "method not allowed" }, 405);
    if (!env.APP_TOKEN || request.headers.get("X-Carbs-Token") !== env.APP_TOKEN) {
      return json({ error: "unauthorized" }, 401);
    }
    try {
      if (url.pathname === "/search") {
        const q = (url.searchParams.get("q") || "").trim();
        if (q.length < 2) return json({ foods: [] });
        return json({ foods: await search(q, env, ctx) });
      }
      const match = url.pathname.match(/^\/food\/(\d+)$/);
      if (match) {
        const food = await getFood(match[1], env, ctx);
        return food ? json({ food }) : json({ error: "not found" }, 404);
      }
      return json({ error: "not found" }, 404);
    } catch (err) {
      return json({ error: String(err.message || err) }, 502);
    }
  },
};

async function search(q, env, ctx) {
  const data = await call(env, { method: "foods.search", search_expression: q, max_results: SEARCH_RESULTS });
  const list = asArray(data?.foods?.food);
  const foods = await Promise.all(list.map((f) => getFood(f.food_id, env, ctx).catch(() => null)));
  return foods.filter(Boolean);
}

/** food.get.v2, normalised and cached at the edge for a week. */
async function getFood(id, env, ctx) {
  const cacheKey = new Request(`https://carbs-cache/food/${id}`);
  const cache = caches.default;
  const hit = await cache.match(cacheKey);
  if (hit) return hit.json();

  const data = await call(env, { method: "food.get.v2", food_id: id });
  const food = normalise(data?.food);
  if (food) {
    const response = new Response(JSON.stringify(food), {
      headers: { "Content-Type": "application/json", "Cache-Control": `max-age=${FOOD_CACHE_SECONDS}` },
    });
    ctx.waitUntil(cache.put(cacheKey, response));
  }
  return food;
}

/** FatSecret food → { id, name, brand, per100g, servings: [{name, grams}] }. */
export function normalise(f) {
  if (!f) return null;
  const servings = asArray(f.servings?.serving)
    .map((s) => ({ s, grams: gramsOf(s) }))
    .filter((x) => x.grams > 0);
  if (servings.length === 0) return null;

  // Nutrition per 100 g from the first serving with a weight (FatSecret lists the default first).
  const { s: base, grams } = servings[0];
  const per = (key) => (num(base[key]) * 100) / grams;
  return {
    id: String(f.food_id),
    name: f.food_name,
    brand: f.brand_name || null,
    url: f.food_url || null,
    per100g: {
      calories: per("calories"),
      protein: per("protein"),
      carbs: per("carbohydrate"),
      fat: per("fat"),
      fiber: per("fiber"),
      sugar: per("sugar"),
    },
    servings: servings.map(({ s, grams }) => ({ name: servingName(s, grams), grams: round(grams, 2) })),
  };
}

function gramsOf(s) {
  const amount = num(s.metric_serving_amount);
  const unit = (s.metric_serving_unit || "").toLowerCase();
  if (!amount) return 0;
  if (unit === "g" || unit === "ml") return amount; // ml treated as grams, close enough for food
  if (unit === "oz") return amount * 28.3495;
  return 0;
}

function servingName(s, grams) {
  let desc = (s.serving_description || "serving").trim();
  const unit = (s.metric_serving_unit || "g").toLowerCase() === "ml" ? "ml" : "g";
  if (/^\d+(\.\d+)?\s*(g|ml)$/i.test(desc)) return desc; // already "100 g"
  if (desc.startsWith("1 ")) desc = desc.slice(2);
  if (/\(\s*\d+(\.\d+)?\s*(g|ml)\s*\)/i.test(desc)) return desc; // already "serving (105 g)"
  return `${desc} (${round(grams, 0)}${unit})`;
}

// ---- OAuth 1.0 (two-legged, HMAC-SHA1) ----

async function call(env, params) {
  const all = {
    ...params,
    format: "json",
    oauth_consumer_key: env.FATSECRET_KEY,
    oauth_nonce: crypto.randomUUID().replace(/-/g, ""),
    oauth_signature_method: "HMAC-SHA1",
    oauth_timestamp: String(Math.floor(Date.now() / 1000)),
    oauth_version: "1.0",
  };
  const normalised = Object.keys(all).sort().map((k) => `${enc(k)}=${enc(all[k])}`).join("&");
  const baseString = ["GET", enc(API), enc(normalised)].join("&");
  all.oauth_signature = await hmacSha1(`${enc(env.FATSECRET_SECRET)}&`, baseString);

  const query = Object.keys(all).map((k) => `${enc(k)}=${enc(all[k])}`).join("&");
  const res = await fetch(`${API}?${query}`);
  if (!res.ok) throw new Error(`FatSecret HTTP ${res.status}`);
  const data = await res.json();
  if (data.error) throw new Error(`FatSecret ${data.error.code}: ${data.error.message}`);
  return data;
}

async function hmacSha1(key, message) {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(key), { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(message));
  return btoa(String.fromCharCode(...new Uint8Array(sig)));
}

// RFC 3986 encoding, as OAuth 1.0 requires.
function enc(value) {
  return encodeURIComponent(String(value)).replace(/[!'()*]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase());
}

// ---- helpers ----

const asArray = (x) => (Array.isArray(x) ? x : x ? [x] : []);
const num = (x) => {
  const n = parseFloat(x);
  return Number.isFinite(n) ? n : 0;
};
const round = (x, places) => Math.round(x * 10 ** places) / 10 ** places;

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
