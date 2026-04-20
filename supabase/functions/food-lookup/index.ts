import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

type FoodCandidate = {
  name: string
  brand: string | null
  serving_amount: number
  serving_unit: string
  grams: number | null
  calories: number
  protein_g: number
  carb_g: number
  fat_g: number
  fiber_g: number | null
  sodium_mg: number | null
  fdc_id: number | null
  external_product_id: string | null
  household_serving_text?: string | null
  nutrients_extra?: Record<string, number> | null
  image_url?: string | null
  source: "usda" | "off"
}

const NUTRIENT_IDS = {
  kcal: 1008,
  protein: 1003,
  fat: 1004,
  carb: 1005,
  fiber: 1079,
  sodium: 1093,
  /** FDC nutrient.id for "Total Sugars" (branded + SR Legacy search/detail). */
  sugarsTotal: 2000,
  /** Legacy / rare payloads that use NLEA code 269 as id. */
  sugarsLegacy: 269,
  satFat: 1258,
  cholesterol: 1253,
  potassium: 1092,
} as const

function num(v: unknown): number | null {
  if (v == null || v === "") return null
  const x = typeof v === "number" ? v : parseFloat(String(v))
  return Number.isFinite(x) ? x : null
}

/** Parse grams (or treat ml as g) from OFF serving_size like "41 g", "30g", "250 ml". */
function parseServingGramsFromString(servingSize: string): number | null {
  const t = servingSize.trim().toLowerCase()
  const m = t.match(/([\d.,]+)\s*(g|gram|grams|ml|milliliters?)\b/)
  if (!m) return null
  const v = parseFloat(m[1]!.replace(",", "."))
  if (!Number.isFinite(v) || v <= 0) return null
  return v
}

function offHouseholdText(product: Record<string, unknown>): string | null {
  const ss = product.serving_size
  if (typeof ss === "string" && ss.trim()) return ss.trim()
  const q = product.quantity
  const u = product.quantity_unit
  if (q != null && u) return `${q} ${u}`.trim()
  return null
}

/** Collect reference nutrients from OFF nutriments (same basis as main macros). */
function offNutrientsExtra(
  n: Record<string, unknown>,
  useServing: boolean,
): Record<string, number> | null {
  const suf = useServing ? "_serving" : "_100g"
  const pick = (base: string): number | null => {
    const a = num(n[`${base}${suf}`])
    if (a != null) return a
    if (!useServing) return num(n[base])
    return num(n[`${base}_serving`]) ?? num(n[base])
  }
  const out: Record<string, number> = {}
  const map: [string, string][] = [
    ["sugars_g", "sugars"],
    ["saturated_fat_g", "saturated-fat"],
    ["cholesterol_mg", "cholesterol"],
    ["potassium_mg", "potassium"],
  ]
  for (const [key, offBase] of map) {
    const v = pick(offBase)
    if (v != null && v > 0) out[key] = v
  }
  if (out["sugars_g"] == null) {
    const added = pick("added-sugars")
    if (added != null && added > 0) out["sugars_g"] = added
  }
  // Sodium in OFF often per 100g as salt or sodium — main flow uses sodium_100g; duplicate for extras as mg
  const na = useServing ? (num(n["sodium_serving"]) ?? num(n["sodium"])) : (num(n["sodium_100g"]) ?? num(n["sodium"]))
  if (na != null && na > 0) {
    const mg = na < 50 ? na * 1000 : na
    if (mg > 0) out["sodium_mg_extra"] = mg
  }
  return Object.keys(out).length ? out : null
}

function offProductToCandidate(
  p: Record<string, unknown>,
  externalId: string | null,
  fdcId: number | null,
): FoodCandidate {
  const name = String(p.product_name || p.generic_name || "Food")
  const brand = p.brands ? String(p.brands).split(",")[0].trim() : null
  const n = (p.nutriments || {}) as Record<string, unknown>
  const ndp = String(p.nutrition_data_per ?? "100g").toLowerCase()
  const household = offHouseholdText(p)
  const servingGrams = household ? parseServingGramsFromString(household) : null
  const imageUrl =
    (p.image_front_small_url as string | null) ??
    (p.image_front_url as string | null) ??
    (p.image_url as string | null) ??
    null

  const preferServing =
    ndp.includes("serving") ||
    (num(n["energy-kcal_serving"]) != null && num(n["energy-kcal_serving"])! > 0)

  if (preferServing && servingGrams != null && servingGrams > 0) {
    const kcal = num(n["energy-kcal_serving"]) ?? num(n["energy-kcal"]) ?? 0
    const protein = num(n["proteins_serving"]) ?? num(n["proteins"]) ?? 0
    const carb = num(n["carbohydrates_serving"]) ?? num(n["carbohydrates"]) ?? 0
    const fat = num(n["fat_serving"]) ?? num(n["fat"]) ?? 0
    const fiber = num(n["fiber_serving"]) ?? num(n["fiber"]) ?? null
    const sodiumG = num(n["sodium_serving"]) ?? num(n["sodium"]) ?? null
    const sodiumMg = sodiumG != null ? (sodiumG < 50 ? sodiumG * 1000 : sodiumG) : null
    return {
      name,
      brand,
      serving_amount: 1,
      serving_unit: household ?? "serving",
      grams: servingGrams,
      calories: kcal,
      protein_g: protein,
      carb_g: carb,
      fat_g: fat,
      fiber_g: fiber,
      sodium_mg: sodiumMg,
      fdc_id: fdcId,
      external_product_id: externalId,
      household_serving_text: household,
      nutrients_extra: offNutrientsExtra(n, true),
      image_url: imageUrl,
      source: "off",
    }
  }

  const kcal = num(n["energy-kcal_100g"]) ?? num(n["energy-kcal"]) ?? 0
  const protein = num(n["proteins_100g"]) ?? num(n["proteins"]) ?? 0
  const carb = num(n["carbohydrates_100g"]) ?? num(n["carbohydrates"]) ?? 0
  const fat = num(n["fat_100g"]) ?? num(n["fat"]) ?? 0
  const fiber = num(n["fiber_100g"]) ?? num(n["fiber"]) ?? null
  const sodiumG = num(n["sodium_100g"]) ?? num(n["sodium"]) ?? null
  const sodiumMg = sodiumG != null ? (sodiumG < 50 ? sodiumG * 1000 : sodiumG) : null

  if (servingGrams != null && servingGrams > 0 && servingGrams !== 100) {
    const f = servingGrams / 100
    const extra = offNutrientsExtra(n, false)
    const scaledExtra = extra
      ? Object.fromEntries(Object.entries(extra).map(([k, v]) => [k, v * f]))
      : null
    return {
      name,
      brand,
      serving_amount: 1,
      serving_unit: household ?? `${servingGrams} g`,
      grams: servingGrams,
      calories: kcal * f,
      protein_g: protein * f,
      carb_g: carb * f,
      fat_g: fat * f,
      fiber_g: fiber != null ? fiber * f : null,
      sodium_mg: sodiumMg != null ? sodiumMg * f : null,
      fdc_id: fdcId,
      external_product_id: externalId,
      household_serving_text: household,
      nutrients_extra: scaledExtra,
      image_url: imageUrl,
      source: "off",
    }
  }

  return {
    name,
    brand,
    serving_amount: 100,
    serving_unit: "per 100 g",
    grams: 100,
    calories: kcal,
    protein_g: protein,
    carb_g: carb,
    fat_g: fat,
    fiber_g: fiber,
    sodium_mg: sodiumMg,
    fdc_id: fdcId,
    external_product_id: externalId,
    household_serving_text: household,
    nutrients_extra: offNutrientsExtra(n, false),
    image_url: imageUrl,
    source: "off",
  }
}

/** GS1 check digit for GTIN-8 / 12 / 13 / 14 only; other lengths pass through (e.g. Code 128). */
function hasValidGtinCheckDigit(raw: string): boolean {
  const len = raw.length
  if (![8, 12, 13, 14].includes(len)) return true
  const body = raw.slice(0, -1)
  const check = parseInt(raw.slice(-1), 10)
  if (Number.isNaN(check)) return false
  const data = body.split("").reverse().map((c) => parseInt(c, 10))
  if (data.some((d) => Number.isNaN(d))) return false
  let sum = 0
  for (let i = 0; i < data.length; i++) {
    sum += data[i]! * (i % 2 === 0 ? 3 : 1)
  }
  const expected = (10 - (sum % 10)) % 10
  return expected === check
}

async function openFoodFactsBarcode(code: string): Promise<FoodCandidate[]> {
  const url = `https://world.openfoodfacts.org/api/v2/product/${encodeURIComponent(code)}.json`
  const res = await fetch(url)
  if (!res.ok) return []
  const data = await res.json()
  if (data.status !== 1 || !data.product) return []
  const p = data.product as Record<string, unknown>
  return [offProductToCandidate(p, String(code), null)]
}

async function openFoodFactsSearch(q: string): Promise<FoodCandidate[]> {
  const url =
    `https://world.openfoodfacts.org/cgi/search.pl?search_terms=${
      encodeURIComponent(q)
    }&search_simple=1&action=process&json=1&page_size=5`
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(8_000) })
    if (!res.ok) {
      console.error(`OFF search HTTP ${res.status} for query: ${q}`)
      return []
    }
    const data = await res.json()
    const products = data.products as Array<Record<string, unknown>> | undefined
    console.log(`OFF search returned ${products?.length ?? 0} results for: ${q}`)
    if (!products?.length) return []
    return products.map((p) => {
      const code = p.code != null ? String(p.code) : null
      return offProductToCandidate(p, code, null)
    })
  } catch (e) {
    console.error(`OFF search failed for query "${q}":`, e)
    return []
  }
}

function mapUsdaNutrients(nutrients: Array<{ nutrientId?: number; value?: number }>): {
  kcal: number
  protein: number
  carb: number
  fat: number
  fiber: number | null
  sodiumMg: number | null
} {
  let kcal = 0,
    protein = 0,
    carb = 0,
    fat = 0,
    fiber: number | null = null,
    sodiumMg: number | null = null
  for (const n of nutrients || []) {
    const id = n.nutrientId
    const v = n.value
    if (v == null || !Number.isFinite(v)) continue
    if (id === NUTRIENT_IDS.kcal) kcal = v
    else if (id === NUTRIENT_IDS.protein) protein = v
    else if (id === NUTRIENT_IDS.carb) carb = v
    else if (id === NUTRIENT_IDS.fat) fat = v
    else if (id === NUTRIENT_IDS.fiber) fiber = v
    else if (id === NUTRIENT_IDS.sodium) sodiumMg = v
  }
  return { kcal, protein, carb, fat, fiber, sodiumMg }
}

function usdaNutrientsExtraFromList(
  nutrients: Array<{ nutrientId?: number; value?: number; nutrientName?: string }>,
): Record<string, number> | null {
  const out: Record<string, number> = {}
  for (const n of nutrients || []) {
    const id = n.nutrientId
    const v = n.value
    const name = (n.nutrientName || "").toLowerCase()
    if (v == null || !Number.isFinite(v)) continue
    if (id === NUTRIENT_IDS.sugarsTotal || id === NUTRIENT_IDS.sugarsLegacy) {
      out["sugars_g"] = v
    } else if (
      out["sugars_g"] == null &&
      name &&
      (name === "total sugars" || name.includes("sugars, total") || (name.includes("total") && name.includes("sugar")))
    ) {
      out["sugars_g"] = v
    } else if (id === NUTRIENT_IDS.satFat) out["saturated_fat_g"] = v
    else if (id === NUTRIENT_IDS.cholesterol) out["cholesterol_mg"] = v
    else if (id === NUTRIENT_IDS.potassium) out["potassium_mg"] = v
  }
  return Object.keys(out).length ? out : null
}

async function usdaFetchFoodDetail(fdcId: number, apiKey: string): Promise<Record<string, unknown> | null> {
  try {
    const url = new URL(`https://api.nal.usda.gov/fdc/v1/food/${fdcId}`)
    url.searchParams.set("api_key", apiKey)
    const res = await fetch(url.toString(), { signal: AbortSignal.timeout(12_000) })
    if (!res.ok) return null
    return await res.json() as Record<string, unknown>
  } catch {
    return null
  }
}

function usdaCandidateFromDetail(d: Record<string, unknown>, fdcId: number): FoodCandidate | null {
  const desc = String(d.description || "Food")
  const brand = (d.brandName as string) ?? (d.brandOwner as string) ?? null
  const household = (d.householdServingFullText as string) ?? null
  const ln = d.labelNutrients as Record<string, { value?: number }> | undefined
  const ss = num(d.servingSize)
  const ssu = String(d.servingSizeUnit || "g").toLowerCase()

  if (ln && ss != null && ss > 0 && (ssu === "g" || ssu === "gram" || ssu === "grams" || ssu === "ml")) {
    const cal = num(ln.calories?.value) ?? 0
    const protein = num(ln.protein?.value) ?? 0
    const carb = num(ln.carbohydrates?.value) ?? 0
    const fat = num(ln.fat?.value) ?? 0
    const fiber = num(ln.fiber?.value) ?? null
    const sodium = num(ln.sodium?.value) ?? null
    const extras: Record<string, number> = {}
    const sf = num(ln.saturatedFat?.value)
    const sg = num(ln.sugars?.value)
    const ch = num(ln.cholesterol?.value)
    const k = num(ln.potassium?.value)
    if (sf != null && sf > 0) extras["saturated_fat_g"] = sf
    if (sg != null && sg > 0) extras["sugars_g"] = sg
    if (ch != null && ch > 0) extras["cholesterol_mg"] = ch
    if (k != null && k > 0) extras["potassium_mg"] = k
    const unitLabel = household ?? `${ss} ${ssu}`
    return {
      name: desc,
      brand,
      serving_amount: 1,
      serving_unit: unitLabel,
      grams: ss,
      calories: cal,
      protein_g: protein,
      carb_g: carb,
      fat_g: fat,
      fiber_g: fiber,
      sodium_mg: sodium,
      fdc_id: fdcId,
      external_product_id: null,
      household_serving_text: household,
      nutrients_extra: Object.keys(extras).length ? extras : null,
      source: "usda",
    }
  }

  const fn = d.foodNutrients as
    | Array<{
      nutrient?: { id?: number; name?: string; number?: string }
      amount?: number
      value?: number
      nutrientId?: number
    }>
    | undefined
  if (!fn?.length) return null
  const flat: Array<{ nutrientId?: number; value?: number }> = fn.map((x) => {
    const id = x.nutrient?.id ?? x.nutrientId
    const val = x.amount ?? x.value
    return { nutrientId: id, value: val }
  })
  const mapped = mapUsdaNutrients(flat)
  const basis = ss != null && ss > 0 && (ssu === "g" || ssu === "gram" || ssu === "grams") ? ss : 100
  const factor = basis / 100
  const extras = usdaNutrientsExtraFromList(flat)
  const scaledExtras = extras
    ? Object.fromEntries(Object.entries(extras).map(([k, v]) => [k, v * factor]))
    : null
  return {
    name: desc,
    brand,
    serving_amount: basis === 100 ? 100 : 1,
    serving_unit: basis === 100 ? "per 100 g" : (household ?? `${basis} g`),
    grams: basis,
    calories: mapped.kcal * factor,
    protein_g: mapped.protein * factor,
    carb_g: mapped.carb * factor,
    fat_g: mapped.fat * factor,
    fiber_g: mapped.fiber != null ? mapped.fiber * factor : null,
    sodium_mg: mapped.sodiumMg != null ? mapped.sodiumMg * factor : null,
    fdc_id: fdcId,
    external_product_id: null,
    household_serving_text: household,
    nutrients_extra: scaledExtras,
    source: "usda",
  }
}

async function usdaSearchToCandidates(query: string, apiKey: string): Promise<FoodCandidate[]> {
  const url = new URL("https://api.nal.usda.gov/fdc/v1/foods/search")
  url.searchParams.set("api_key", apiKey)
  url.searchParams.set("query", query)
  url.searchParams.set("pageSize", "5")
  const res = await fetch(url.toString(), { signal: AbortSignal.timeout(15_000) })
  if (!res.ok) return []
  const data = await res.json()
  const foods = data.foods as Array<{
    fdcId: number
    description: string
    brandName?: string
    foodNutrients?: Array<{ nutrientId?: number; value?: number }>
  }> | undefined
  if (!foods?.length) return []

  const out: FoodCandidate[] = []
  for (const f of foods) {
    const detail = await usdaFetchFoodDetail(f.fdcId, apiKey)
    if (detail) {
      const c = usdaCandidateFromDetail(detail, f.fdcId)
      if (c) {
        out.push(c)
        continue
      }
    }
    const mapped = mapUsdaNutrients(f.foodNutrients || [])
    out.push({
      name: f.description,
      brand: f.brandName ?? null,
      serving_amount: 100,
      serving_unit: "per 100 g",
      grams: 100,
      calories: mapped.kcal,
      protein_g: mapped.protein,
      carb_g: mapped.carb,
      fat_g: mapped.fat,
      fiber_g: mapped.fiber,
      sodium_mg: mapped.sodiumMg,
      fdc_id: f.fdcId,
      external_product_id: null,
      household_serving_text: null,
      nutrients_extra: usdaNutrientsExtraFromList(f.foodNutrients || []),
      source: "usda",
    })
  }
  return out
}


/** Fetch a thumbnail from Wikipedia for a food name. Returns null if no article/image found. */
async function wikipediaImageUrl(foodName: string): Promise<string | null> {
  const primary = foodName.split(",")[0].trim()
  const title = encodeURIComponent(primary.replace(/\s+/g, "_"))
  try {
    const res = await fetch(
      `https://en.wikipedia.org/api/rest_v1/page/summary/${title}`,
      { signal: AbortSignal.timeout(5_000) },
    )
    if (!res.ok) return null
    const data = await res.json() as { thumbnail?: { source?: string } }
    return data.thumbnail?.source ?? null
  } catch {
    return null
  }
}

/** Fill missing images on USDA candidates using Wikipedia thumbnails (parallel). */
async function fillMissingImages(candidates: FoodCandidate[]): Promise<void> {
  const missing = candidates.filter((c) => !c.image_url && c.source === "usda")
  if (!missing.length) return
  await Promise.all(
    missing.map(async (c) => {
      c.image_url = await wikipediaImageUrl(c.name)
    }),
  )
}

async function openaiDescribeFoods(
  imageBase64: string,
  mimeType: string,
  apiKey: string,
): Promise<string[]> {
  const body = {
    model: "gpt-4o-mini",
    messages: [
      {
        role: "user",
        content: [
          {
            type: "text",
            text:
              "List the distinct food items visible in this meal as a JSON array of strings only, no other text, max 6 items, use common English food names (e.g. [\"grilled chicken breast\",\"white rice\"]).",
          },
          {
            type: "image_url",
            image_url: {
              url: `data:${mimeType};base64,${imageBase64}`,
            },
          },
        ],
      },
    ],
    max_tokens: 300,
  }
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  })
  if (!res.ok) {
    const t = await res.text()
    console.error("OpenAI error:", t)
    return []
  }
  const data = await res.json()
  const text = data.choices?.[0]?.message?.content as string | undefined
  if (!text) return []
  const trimmed = text.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "")
  try {
    const arr = JSON.parse(trimmed)
    if (Array.isArray(arr)) return arr.map((x) => String(x)).filter(Boolean)
  } catch {
    /* fall through */
  }
  return trimmed.split(",").map((s) => s.replace(/^\[|\]|"/g, "").trim()).filter(Boolean)
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get("Authorization")
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    )

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser()
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized", details: userError?.message }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const json = await req.json().catch(() => ({})) as {
      mode?: string
      barcode?: string
      image_base64?: string
      mime_type?: string
      query?: string
    }

    const mode = json.mode
    const usdaKey = Deno.env.get("USDA_API_KEY") ?? ""
    const openaiKey = Deno.env.get("OPENAI_API_KEY") ?? ""

    let candidates: FoodCandidate[] = []
    let notice: string | undefined

    if (mode === "barcode") {
      const raw = json.barcode?.replace(/\D/g, "") ?? ""
      if (raw.length < 8) {
        return new Response(JSON.stringify({ error: "Invalid barcode" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        })
      }
      if (!hasValidGtinCheckDigit(raw)) {
        return new Response(
          JSON.stringify({ error: "Invalid barcode (check digit). Try scanning again." }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        )
      }
      candidates = await openFoodFactsBarcode(raw)
      if (!candidates.length) {
        notice = "No product found in Open Food Facts for this barcode."
      }
    } else if (mode === "search") {
      const q = (json.query || "").trim()
      if (q.length < 2) {
        return new Response(JSON.stringify({ error: "Query too short" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        })
      }
      const [usdaResults, offResults] = await Promise.all([
        usdaKey ? usdaSearchToCandidates(q, usdaKey) : Promise.resolve([] as FoodCandidate[]),
        openFoodFactsSearch(q),
      ])
      const seen = new Set<string>()
      for (const c of [...usdaResults, ...offResults]) {
        const key = `${c.name.toLowerCase().trim()}|${(c.brand ?? "").toLowerCase().trim()}`
        if (!seen.has(key)) {
          seen.add(key)
          candidates.push(c)
        }
      }
      if (!candidates.length) {
        notice = "No foods matched your search."
      } else {
        await fillMissingImages(candidates)
      }
    } else if (mode === "photo") {
      const b64 = json.image_base64
      const mime = json.mime_type || "image/jpeg"
      if (!b64) {
        return new Response(JSON.stringify({ error: "Missing image_base64" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        })
      }
      if (b64.length > 10_000_000) {
        return new Response(
          JSON.stringify({
            error: "Image too large. Use a smaller photo or lower resolution.",
          }),
          {
            status: 413,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        )
      }
      if (!openaiKey) {
        return new Response(
          JSON.stringify({
            candidates: [],
            notice:
              "Photo recognition requires OPENAI_API_KEY on the food-lookup function. Use Search or Barcode, or add the secret in Supabase.",
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        )
      }
      const items = await openaiDescribeFoods(b64, mime, openaiKey)
      if (!items.length) {
        notice = "Could not identify foods in the image. Try manual search."
      }
      const seen = new Set<string>()
      for (const term of items) {
        const key = term.toLowerCase()
        if (seen.has(key)) continue
        seen.add(key)
        let batch: FoodCandidate[] = []
        if (usdaKey) {
          batch = await usdaSearchToCandidates(term, usdaKey)
        }
        if (!batch.length) {
          batch = await openFoodFactsSearch(term)
        }
        candidates.push(...batch.slice(0, 2))
      }
      candidates = candidates.slice(0, 12)
    } else {
      return new Response(JSON.stringify({ error: "Invalid mode; use barcode | photo | search" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    return new Response(JSON.stringify({ candidates, notice }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error"
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  }
})
