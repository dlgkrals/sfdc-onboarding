/**
 * 한결공조 ERP Mock — Cloudflare Workers + D1
 *
 * 재고의 원본(마스터)인 ERP를 흉내 냄. Salesforce(한결공조 AS)가 부품 사용·재고 이동을 알리면
 * 위치(창고 WAREHOUSE / 기사 차량 VAN)별 재고를 줄이고 늘리며 이력을 남김.
 *
 * API (모두 x-api-key 헤더 필요, /health와 화면 제외)
 *   GET  /health                      깨우기·상태 확인
 *   GET  /api/stock?location=CODE     재고 조회 (location 없으면 전체)        IF-04
 *   POST /api/stock/consume           사용 차감 (여러 건 한 번에)          IF-03
 *   POST /api/stock/transfer          재고 이동 (창고 → 차량 등, 여러 건)  IF-06
 *   GET  /api/movements?after=N       이력 번호 N 이후 변동 (최대 500건, latestId 포함)  IF-02
 *   POST /api/stock/receive           ERP 입고 (시연 화면에서 입력)                      IF-02
 *   POST /api/stock/adjust            ERP 재고 조정 (±, 시연 화면에서 입력)              IF-02
 *   POST /api/admin/seed              초기 재고 적재 (Salesforce 현재 재고)
 *   POST /api/admin/maintenance       시연용 장애 모드 켜기·끄기 (켜면 API가 503)
 *   GET  /                            위치별 재고·최근 이력 화면 + 입고·조정 입력
 *   POST /ui/stock/receive · adjust   화면 전용 입고·조정 (키 없음, 시연용·주소 비공개 전제. 로직은 /api/와 같음)
 *
 * 업무 결과(성공·거부)는 HTTP 200 + 건별 status. 인증 실패 401, 요청 형식 오류 400, 장애 모드 503
 * 같은 refId(Salesforce 레코드 Id)가 다시 오면 처음 결과를 그대로 돌려줌 (재전송해도 두 번 차감 안 됨)
 * IF-02 푸시(2026-10-15): ERP 입고·조정(origin = ERP)이 생기면 바로 Salesforce Apex REST(/services/apexrest/hg/erp/movements)로 1건 보냄
 *   - 인증: OAuth 2.0 Client Credentials(외부 클라이언트 앱, Run As = 연동 사용자). 비밀 값은 Cloudflare secret SF_CLIENT_ID · SF_CLIENT_SECRET
 *   - 실패해도 ERP 저장은 그대로, 재시도하지 않음 → Salesforce가 매시 가져오기(Pull)로 다시 가져감. Salesforce 출처 변동은 보내지 않음(재귀 방지)
 */

const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };
const MAX_ITEMS = 200;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (request.method === "GET" && url.pathname === "/health") {
        return json({ status: "ok", service: "hg-erp-mock", time: now() });
      }
      if (request.method === "GET" && url.pathname === "/") {
        return await renderPage(env);
      }
      // DESC: 화면 전용 주소 — 재고 화면의 입고·조정 입력이 키 없이 호출. 서버 안에서 /api/와 같은 로직 실행
      //       시연용이라 인증 생략(주소 비공개 전제). 키는 서버 환경 변수에만 있고 화면·브라우저로 나가지 않음
      //       운영이라면 사람은 로그인(SSO 등), 시스템(Salesforce)은 API 키로 분리
      if (request.method === "POST" && url.pathname === "/ui/stock/receive") {
        return await receive(request, env);
      }
      if (request.method === "POST" && url.pathname === "/ui/stock/adjust") {
        return await adjust(request, env);
      }
      if (!url.pathname.startsWith("/api/")) {
        return json({ error: "NOT_FOUND" }, 404);
      }
      if (!env.API_KEY || request.headers.get("x-api-key") !== env.API_KEY) {
        return json(
          {
            error: "UNAUTHORIZED",
            message: "x-api-key가 없거나 맞지 않습니다."
          },
          401
        );
      }
      // DESC: 시연용 장애 모드 해제 API는 장애 모드에서도 열어 둠
      if (
        url.pathname === "/api/admin/maintenance" &&
        request.method === "POST"
      ) {
        return await setMaintenance(request, env);
      }
      if ((await getSetting(env, "maintenance")) === "on") {
        return json(
          { error: "MAINTENANCE", message: "ERP 점검 중입니다." },
          503
        );
      }
      if (request.method === "GET" && url.pathname === "/api/stock") {
        return await getStock(url, env);
      }
      if (request.method === "POST" && url.pathname === "/api/stock/consume") {
        return await consume(request, env);
      }
      if (request.method === "POST" && url.pathname === "/api/stock/transfer") {
        return await transfer(request, env);
      }
      if (request.method === "GET" && url.pathname === "/api/movements") {
        return await getMovements(url, env);
      }
      if (request.method === "POST" && url.pathname === "/api/stock/receive") {
        return await receive(request, env);
      }
      if (request.method === "POST" && url.pathname === "/api/stock/adjust") {
        return await adjust(request, env);
      }
      if (request.method === "POST" && url.pathname === "/api/admin/seed") {
        return await seed(request, env);
      }
      return json({ error: "NOT_FOUND" }, 404);
    } catch (e) {
      if (e instanceof BadRequest) {
        return json({ error: "BAD_REQUEST", message: e.message }, 400);
      }
      return json(
        {
          error: "SERVER_ERROR",
          message: String(e && e.message ? e.message : e)
        },
        500
      );
    }
  }
};

class BadRequest extends Error {}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function now() {
  return new Date().toISOString();
}

// DESC: 수량은 소수 둘째 자리까지 (냉매 kg)
function round(n) {
  return Math.round(n * 100) / 100;
}

async function readItems(request) {
  let body;
  try {
    body = await request.json();
  } catch {
    throw new BadRequest("JSON 본문이 아닙니다.");
  }
  if (!body || !Array.isArray(body.items) || body.items.length === 0) {
    throw new BadRequest("items 배열이 필요합니다.");
  }
  if (body.items.length > MAX_ITEMS) {
    throw new BadRequest(`한 번에 ${MAX_ITEMS}건까지 보낼 수 있습니다.`);
  }
  return body.items;
}

async function getSetting(env, key) {
  const row = await env.DB.prepare("SELECT value FROM settings WHERE key = ?")
    .bind(key)
    .first();
  return row ? row.value : null;
}

async function setMaintenance(request, env) {
  const body = await request.json().catch(() => ({}));
  const value = body && body.on ? "on" : "off";
  await env.DB.prepare(
    "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)"
  )
    .bind("maintenance", value)
    .run();
  return json({ maintenance: value });
}

async function getStock(url, env) {
  const location = url.searchParams.get("location");
  const stmt = location
    ? env.DB.prepare(
        "SELECT location_code, part_code, quantity, unit, updated_at FROM stock WHERE location_code = ? ORDER BY part_code"
      ).bind(location)
    : env.DB.prepare(
        "SELECT location_code, part_code, quantity, unit, updated_at FROM stock ORDER BY location_code, part_code"
      );
  const { results } = await stmt.all();
  return json({
    items: results.map((r) => ({
      locationCode: r.location_code,
      partCode: r.part_code,
      quantity: r.quantity,
      unit: r.unit,
      updatedAt: r.updated_at
    }))
  });
}

async function findDuplicate(env, refId) {
  const row = await env.DB.prepare(
    "SELECT result_json FROM requests WHERE ref_id = ?"
  )
    .bind(refId)
    .first();
  return row ? { ...JSON.parse(row.result_json), duplicate: true } : null;
}

async function saveResult(env, refId, kind, result) {
  await env.DB.prepare(
    "INSERT OR IGNORE INTO requests (ref_id, kind, result_json, created_at) VALUES (?, ?, ?, ?)"
  )
    .bind(refId, kind, JSON.stringify(result), now())
    .run();
}

function rejected(refId, code, message, extra = {}) {
  return { refId, status: "REJECTED", code, message, ...extra };
}

async function locationExists(env, code) {
  return !!(await env.DB.prepare("SELECT code FROM locations WHERE code = ?")
    .bind(code)
    .first());
}

// DESC: 수량 검사 → 조건부 차감 → 이력. 재고가 부족하면 UPDATE가 0건이라 거부 (동시에 와도 음수가 되지 않음)
async function decrease(
  env,
  refId,
  type,
  locationCode,
  partCode,
  quantity,
  reference,
  origin = "SALESFORCE"
) {
  const stamp = now();
  const res = await env.DB.prepare(
    "UPDATE stock SET quantity = ROUND(quantity - ?, 2), updated_at = ? WHERE location_code = ? AND part_code = ? AND quantity >= ?"
  )
    .bind(quantity, stamp, locationCode, partCode, quantity)
    .run();
  if (!res.meta || res.meta.changes !== 1) {
    return null;
  }
  const row = await env.DB.prepare(
    "SELECT quantity, unit FROM stock WHERE location_code = ? AND part_code = ?"
  )
    .bind(locationCode, partCode)
    .first();
  const ins = await env.DB.prepare(
    "INSERT INTO movements (ref_id, type, location_code, part_code, quantity_change, quantity_after, unit, reference, created_at, origin) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  )
    .bind(
      refId,
      type,
      locationCode,
      partCode,
      -quantity,
      row.quantity,
      row.unit,
      reference || null,
      stamp,
      origin
    )
    .run();
  return {
    quantity: round(row.quantity),
    unit: row.unit,
    movementId: ins.meta ? ins.meta.last_row_id : null,
    createdAt: stamp
  };
}

async function increase(
  env,
  refId,
  type,
  locationCode,
  partCode,
  quantity,
  unit,
  reference,
  origin = "SALESFORCE"
) {
  const stamp = now();
  await env.DB.prepare(
    "INSERT INTO stock (location_code, part_code, quantity, unit, updated_at) VALUES (?, ?, ?, ?, ?) " +
      "ON CONFLICT(location_code, part_code) DO UPDATE SET quantity = ROUND(quantity + excluded.quantity, 2), updated_at = excluded.updated_at"
  )
    .bind(locationCode, partCode, quantity, unit, stamp)
    .run();
  const row = await env.DB.prepare(
    "SELECT quantity, unit FROM stock WHERE location_code = ? AND part_code = ?"
  )
    .bind(locationCode, partCode)
    .first();
  const ins = await env.DB.prepare(
    "INSERT INTO movements (ref_id, type, location_code, part_code, quantity_change, quantity_after, unit, reference, created_at, origin) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  )
    .bind(
      refId,
      type,
      locationCode,
      partCode,
      quantity,
      row.quantity,
      row.unit,
      reference || null,
      stamp,
      origin
    )
    .run();
  return {
    quantity: round(row.quantity),
    unit: row.unit,
    movementId: ins.meta ? ins.meta.last_row_id : null,
    createdAt: stamp
  };
}

function validQuantity(q) {
  return typeof q === "number" && isFinite(q) && q > 0;
}

// IF-03 사용 차감
async function consume(request, env) {
  const items = await readItems(request);
  const results = [];
  for (const item of items) {
    const { refId, locationCode, partCode, quantity, workOrderNumber } =
      item || {};
    if (!refId) {
      results.push(rejected(null, "INVALID_REQUEST", "refId가 필요합니다."));
      continue;
    }
    const dup = await findDuplicate(env, refId);
    if (dup) {
      results.push(dup);
      continue;
    }
    let result;
    if (!validQuantity(quantity)) {
      result = rejected(refId, "INVALID_QUANTITY", "수량은 0보다 커야 합니다.");
    } else if (!(await locationExists(env, locationCode))) {
      result = rejected(
        refId,
        "UNKNOWN_LOCATION",
        `ERP에 없는 위치 코드입니다: ${locationCode}`
      );
    } else {
      const stock = await env.DB.prepare(
        "SELECT quantity, unit FROM stock WHERE location_code = ? AND part_code = ?"
      )
        .bind(locationCode, partCode)
        .first();
      if (!stock) {
        result = rejected(
          refId,
          "UNKNOWN_PART",
          `이 위치에 없는 부품 코드입니다: ${partCode}`
        );
      } else {
        const remaining = await decrease(
          env,
          refId,
          "CONSUME",
          locationCode,
          partCode,
          quantity,
          workOrderNumber
        );
        result =
          remaining === null
            ? rejected(
                refId,
                "INSUFFICIENT_STOCK",
                `재고가 부족합니다. 현재 ${round(stock.quantity)}${unitLabel(stock.unit)}, 요청 ${quantity}${unitLabel(stock.unit)}`,
                { availableQty: round(stock.quantity), unit: stock.unit }
              )
            : {
                refId,
                status: "OK",
                remainingQty: remaining.quantity,
                unit: remaining.unit
              };
      }
    }
    await saveResult(env, refId, "CONSUME", result);
    results.push(result);
  }
  return json({ results });
}

// IF-06 재고 이동 (출발지 차감 → 도착지 증가)
async function transfer(request, env) {
  const items = await readItems(request);
  const results = [];
  for (const item of items) {
    const {
      refId,
      fromLocationCode,
      toLocationCode,
      partCode,
      quantity,
      reference
    } = item || {};
    if (!refId) {
      results.push(rejected(null, "INVALID_REQUEST", "refId가 필요합니다."));
      continue;
    }
    const dup = await findDuplicate(env, refId);
    if (dup) {
      results.push(dup);
      continue;
    }
    let result;
    if (!validQuantity(quantity)) {
      result = rejected(refId, "INVALID_QUANTITY", "수량은 0보다 커야 합니다.");
    } else if (!(await locationExists(env, fromLocationCode))) {
      result = rejected(
        refId,
        "UNKNOWN_LOCATION",
        `ERP에 없는 출발 위치 코드입니다: ${fromLocationCode}`
      );
    } else if (!(await locationExists(env, toLocationCode))) {
      result = rejected(
        refId,
        "UNKNOWN_LOCATION",
        `ERP에 없는 도착 위치 코드입니다: ${toLocationCode}`
      );
    } else {
      const stock = await env.DB.prepare(
        "SELECT quantity, unit FROM stock WHERE location_code = ? AND part_code = ?"
      )
        .bind(fromLocationCode, partCode)
        .first();
      if (!stock) {
        result = rejected(
          refId,
          "UNKNOWN_PART",
          `출발 위치에 없는 부품 코드입니다: ${partCode}`
        );
      } else {
        const source = await decrease(
          env,
          refId,
          "TRANSFER_OUT",
          fromLocationCode,
          partCode,
          quantity,
          reference
        );
        if (source === null) {
          result = rejected(
            refId,
            "INSUFFICIENT_STOCK",
            `출발 위치 재고가 부족합니다. 현재 ${round(stock.quantity)}${unitLabel(stock.unit)}, 요청 ${quantity}${unitLabel(stock.unit)}`,
            { availableQty: round(stock.quantity), unit: stock.unit }
          );
        } else {
          const destination = await increase(
            env,
            refId,
            "TRANSFER_IN",
            toLocationCode,
            partCode,
            quantity,
            source.unit,
            reference
          );
          result = {
            refId,
            status: "OK",
            sourceRemainingQty: source.quantity,
            destinationRemainingQty: destination.quantity,
            unit: source.unit
          };
        }
      }
    }
    await saveResult(env, refId, "TRANSFER", result);
    results.push(result);
  }
  return json({ results });
}

// IF-02 역방향: 이력 번호 after 이후 변동 (번호 오름차순, 최대 500건). Salesforce가 origin=ERP만 골라 반영
const MAX_MOVEMENTS = 500;
async function getMovements(url, env) {
  const after = Number(url.searchParams.get("after") || "0");
  const limit = Math.min(
    Number(url.searchParams.get("limit") || MAX_MOVEMENTS),
    MAX_MOVEMENTS
  );
  if (
    !Number.isInteger(after) ||
    after < 0 ||
    !Number.isInteger(limit) ||
    limit < 1
  ) {
    throw new BadRequest("after는 0 이상, limit은 1 이상 정수여야 합니다.");
  }
  // DESC: 한 건 더 읽어 다음 쪽이 있는지 판단
  const { results } = await env.DB.prepare(
    "SELECT id, ref_id, type, origin, location_code, part_code, quantity_change, quantity_after, unit, reference, created_at FROM movements WHERE id > ? ORDER BY id LIMIT ?"
  )
    .bind(after, limit + 1)
    .all();
  const hasMore = results.length > limit;
  const page = results.slice(0, limit);
  const latest = await env.DB.prepare(
    "SELECT MAX(id) AS id FROM movements"
  ).first();
  return json({
    items: page.map((m) => ({
      id: m.id,
      type: m.type,
      origin: m.origin,
      locationCode: m.location_code,
      partCode: m.part_code,
      quantityChange: round(m.quantity_change),
      quantityAfter: round(m.quantity_after),
      unit: m.unit,
      reference: m.reference,
      refId: m.ref_id,
      createdAt: m.created_at
    })),
    lastId: page.length ? page[page.length - 1].id : after,
    hasMore,
    latestId: latest && latest.id ? latest.id : 0
  });
}

async function readOne(request) {
  try {
    return (await request.json()) || {};
  } catch {
    throw new BadRequest("JSON 본문이 아닙니다.");
  }
}

// DESC: 입고·조정 공통 검사 — 위치는 ERP에 있어야 하고 부품 코드는 필수
async function checkTarget(env, body) {
  if (!body.locationCode || !body.partCode) {
    throw new BadRequest("locationCode와 partCode가 필요합니다.");
  }
  if (!(await locationExists(env, body.locationCode))) {
    return rejected(
      null,
      "UNKNOWN_LOCATION",
      `ERP에 없는 위치 코드입니다: ${body.locationCode}`
    );
  }
  return null;
}

// IF-02 ERP 입고 (구매 입고 등 ERP에서만 생기는 증가). 재고가 없던 위치+부품이면 새로 만듦
async function receive(request, env) {
  const body = await readOne(request);
  const bad = await checkTarget(env, body);
  if (bad) return json(bad);
  if (!validQuantity(body.quantity)) {
    return json(
      rejected(null, "INVALID_QUANTITY", "수량은 0보다 커야 합니다.")
    );
  }
  const existing = await env.DB.prepare(
    "SELECT unit FROM stock WHERE location_code = ? AND part_code = ?"
  )
    .bind(body.locationCode, body.partCode)
    .first();
  const unit = existing ? existing.unit : body.unit || "Each";
  const after = await increase(
    env,
    null,
    "RECEIPT",
    body.locationCode,
    body.partCode,
    body.quantity,
    unit,
    body.note || "ERP 입고",
    "ERP"
  );
  const push = await pushMovement(env, "RECEIPT", body, body.quantity, after);
  return json({
    status: "OK",
    remainingQty: after.quantity,
    unit: after.unit,
    movementId: after.movementId,
    push
  });
}

// IF-02 ERP 재고 조정 (실사 차이 등, ±). 줄이는 조정은 재고보다 많이 줄일 수 없음
async function adjust(request, env) {
  const body = await readOne(request);
  const bad = await checkTarget(env, body);
  if (bad) return json(bad);
  const change = body.quantityChange;
  if (typeof change !== "number" || !isFinite(change) || change === 0) {
    return json(
      rejected(
        null,
        "INVALID_QUANTITY",
        "조정 수량은 0이 아닌 숫자여야 합니다."
      )
    );
  }
  const note = body.note || "ERP 재고 조정";
  if (change > 0) {
    const existing = await env.DB.prepare(
      "SELECT unit FROM stock WHERE location_code = ? AND part_code = ?"
    )
      .bind(body.locationCode, body.partCode)
      .first();
    const after = await increase(
      env,
      null,
      "ADJUST",
      body.locationCode,
      body.partCode,
      change,
      existing ? existing.unit : body.unit || "Each",
      note,
      "ERP"
    );
    const push = await pushMovement(env, "ADJUST", body, change, after);
    return json({
      status: "OK",
      remainingQty: after.quantity,
      unit: after.unit,
      movementId: after.movementId,
      push
    });
  }
  const after = await decrease(
    env,
    null,
    "ADJUST",
    body.locationCode,
    body.partCode,
    -change,
    note,
    "ERP"
  );
  if (after === null) {
    return json(
      rejected(
        null,
        "INSUFFICIENT_STOCK",
        "현재 재고보다 많이 줄일 수 없습니다."
      )
    );
  }
  const push = await pushMovement(env, "ADJUST", body, change, after);
  return json({
    status: "OK",
    remainingQty: after.quantity,
    unit: after.unit,
    movementId: after.movementId,
    push
  });
}

// ── IF-02 푸시: ERP 입고·조정 → Salesforce ──────────────────────────────
// DESC: 토큰은 이 Worker 인스턴스 메모리에만 보관(만료 전 재사용). 비밀 값·토큰은 응답·로그에 내보내지 않음
const SF_PUSH_PATH = "/services/apexrest/hg/erp/movements";
const SF_TIMEOUT_MS = 8000;
const SF_TOKEN_REUSE_MS = 10 * 60 * 1000;
let sfToken = null;

function pushEnabled(env) {
  return !!(env.SF_CLIENT_ID && env.SF_CLIENT_SECRET && env.SF_INSTANCE_URL);
}

async function fetchWithTimeout(url, init) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), SF_TIMEOUT_MS);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

// DESC: OAuth 2.0 Client Credentials → 액세스 토큰 (Run As = 연동 사용자)
async function getSalesforceToken(env, forceNew) {
  if (!forceNew && sfToken && sfToken.expiresAt > Date.now()) {
    return sfToken;
  }
  const res = await fetchWithTimeout(
    env.SF_INSTANCE_URL.replace(/\/$/, "") + "/services/oauth2/token",
    {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "client_credentials",
        client_id: env.SF_CLIENT_ID,
        client_secret: env.SF_CLIENT_SECRET
      })
    }
  );
  if (!res.ok) {
    let reason = "";
    try {
      const err = await res.json();
      reason = err.error || "";
    } catch {
      reason = "";
    }
    throw new Error("TOKEN_" + res.status + (reason ? " " + reason : ""));
  }
  const data = await res.json();
  sfToken = {
    accessToken: data.access_token,
    instanceUrl: data.instance_url || env.SF_INSTANCE_URL,
    expiresAt: Date.now() + SF_TOKEN_REUSE_MS
  };
  return sfToken;
}

async function postToSalesforce(env, payload, forceNewToken) {
  const token = await getSalesforceToken(env, forceNewToken);
  return fetchWithTimeout(token.instanceUrl.replace(/\/$/, "") + SF_PUSH_PATH, {
    method: "POST",
    headers: {
      authorization: "Bearer " + token.accessToken,
      "content-type": "application/json; charset=utf-8"
    },
    body: JSON.stringify(payload)
  });
}

// DESC: ERP 출처 변동 1건을 Salesforce로. 결과만 돌려주고 ERP 저장에는 영향 없음(실패 시 매시 가져오기가 다시 가져감)
async function pushMovement(env, type, body, quantityChange, after) {
  if (!pushEnabled(env)) {
    return {
      status: "DISABLED",
      message: "Salesforce 푸시 설정 없음(가져오기만)"
    };
  }
  if (!after || !after.movementId) {
    return { status: "FAILED", message: "이력 번호를 알 수 없어 보내지 않음" };
  }
  const payload = {
    movements: [
      {
        id: after.movementId,
        type,
        origin: "ERP",
        locationCode: body.locationCode,
        partCode: body.partCode,
        quantityChange: round(quantityChange),
        unit: after.unit,
        reference: body.note || null,
        createdAt: after.createdAt
      }
    ]
  };
  try {
    let res = await postToSalesforce(env, payload, false);
    if (res.status === 401) {
      // DESC: 토큰 만료·폐기 → 한 번만 새로 받아 다시 보냄
      res = await postToSalesforce(env, payload, true);
    }
    let data = null;
    try {
      data = await res.json();
    } catch {
      data = null;
    }
    if (res.status !== 200 || !data || !Array.isArray(data.results)) {
      const message =
        data && data.error
          ? data.error.code + " " + (data.error.message || "")
          : "";
      return {
        status: "FAILED",
        message: ("HTTP " + res.status + " " + message).trim()
      };
    }
    const r = data.results[0] || {};
    return {
      status: "SENT",
      result: r.result,
      code: r.code,
      message: r.message
    };
  } catch (e) {
    const reason =
      e && e.name === "AbortError"
        ? "시간 초과"
        : String(e && e.message ? e.message : e);
    return { status: "FAILED", message: reason };
  }
}

// 초기 재고 적재: reset=true면 재고·이력·처리 기록을 비우고 다시 채움
async function seed(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    throw new BadRequest("JSON 본문이 아닙니다.");
  }
  const locations = Array.isArray(body.locations) ? body.locations : [];
  const stock = Array.isArray(body.stock) ? body.stock : [];
  if (body.reset) {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM requests"),
      env.DB.prepare("DELETE FROM movements"),
      env.DB.prepare("DELETE FROM stock"),
      env.DB.prepare("DELETE FROM locations")
    ]);
  }
  for (const l of locations) {
    if (!l.code || !l.name || !["WAREHOUSE", "VAN"].includes(l.type)) {
      throw new BadRequest(`위치 형식 오류: ${JSON.stringify(l)}`);
    }
    await env.DB.prepare(
      "INSERT OR REPLACE INTO locations (code, name, type) VALUES (?, ?, ?)"
    )
      .bind(l.code, l.name, l.type)
      .run();
  }
  const stamp = now();
  for (const s of stock) {
    if (
      !s.locationCode ||
      !s.partCode ||
      typeof s.quantity !== "number" ||
      s.quantity < 0
    ) {
      throw new BadRequest(`재고 형식 오류: ${JSON.stringify(s)}`);
    }
    await env.DB.prepare(
      "INSERT OR REPLACE INTO stock (location_code, part_code, quantity, unit, updated_at) VALUES (?, ?, ?, ?, ?)"
    )
      .bind(s.locationCode, s.partCode, s.quantity, s.unit || "Each", stamp)
      .run();
    await env.DB.prepare(
      "INSERT INTO movements (ref_id, type, location_code, part_code, quantity_change, quantity_after, unit, reference, created_at, origin) VALUES (NULL, ?, ?, ?, ?, ?, ?, ?, ?, 'SEED')"
    )
      .bind(
        "SEED",
        s.locationCode,
        s.partCode,
        s.quantity,
        s.quantity,
        s.unit || "Each",
        "Salesforce 초기 적재",
        stamp
      )
      .run();
  }
  return json({ locations: locations.length, stock: stock.length });
}

function esc(s) {
  return String(s == null ? "" : s).replace(
    /[&<>"]/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]
  );
}

const TYPE_LABEL = { WAREHOUSE: "창고", VAN: "기사 차량" };
// DESC: 수량 단위 화면 표기 (Salesforce 재고 단위 값 → 표시)
const UNIT_LABEL = { Each: "개", kg: "kg" };
function unitLabel(unit) {
  return UNIT_LABEL[unit] || unit || "";
}
const MOVE_LABEL = {
  SEED: "초기 적재",
  CONSUME: "사용 차감",
  TRANSFER_OUT: "이동 출고",
  TRANSFER_IN: "이동 입고",
  RECEIPT: "ERP 입고",
  ADJUST: "ERP 조정"
};
const ORIGIN_LABEL = {
  SALESFORCE: "Salesforce",
  ERP: "ERP",
  SEED: "초기 적재"
};

// 위치별 재고·최근 이력 화면 (읽기 전용, 고객 정보 없음)
async function renderPage(env) {
  const [
    { results: locs },
    { results: stock },
    { results: moves },
    maintenance
  ] = await Promise.all([
    env.DB.prepare(
      "SELECT code, name, type FROM locations ORDER BY type DESC, code"
    ).all(),
    env.DB.prepare(
      "SELECT location_code, part_code, quantity, unit, updated_at FROM stock ORDER BY location_code, part_code"
    ).all(),
    env.DB.prepare(
      "SELECT id, ref_id, type, origin, location_code, part_code, quantity_change, quantity_after, unit, reference, created_at FROM movements ORDER BY id DESC LIMIT 50"
    ).all(),
    getSetting(env, "maintenance")
  ]);
  const byLoc = {};
  for (const s of stock)
    (byLoc[s.location_code] = byLoc[s.location_code] || []).push(s);
  const fmt = (iso) =>
    iso
      ? new Date(iso).toLocaleString("ko-KR", { timeZone: "Asia/Seoul" })
      : "";
  const locHtml = locs
    .map(
      (
        l
      ) => `<section class="card"><h2><span class="tag ${l.type}">${TYPE_LABEL[l.type]}</span>${esc(l.name)} <small>${esc(l.code)}</small></h2>
      <table><thead><tr><th>부품 코드</th><th class="num">수량</th><th>최종 변경</th></tr></thead><tbody>
      ${(byLoc[l.code] || []).map((s) => `<tr><td>${esc(s.part_code)}</td><td class="num">${esc(s.quantity)} ${esc(unitLabel(s.unit))}</td><td>${esc(fmt(s.updated_at))}</td></tr>`).join("") || '<tr><td colspan="3" class="muted">재고 없음</td></tr>'}
      </tbody></table></section>`
    )
    .join("");
  const moveHtml = moves
    .map(
      (
        m
      ) => `<tr><td class="num">${esc(m.id)}</td><td>${esc(fmt(m.created_at))}</td><td>${esc(MOVE_LABEL[m.type])}</td><td><span class="origin ${esc(m.origin)}">${esc(ORIGIN_LABEL[m.origin] || m.origin)}</span></td><td>${esc(m.location_code)}</td><td>${esc(m.part_code)}</td>
      <td class="num ${m.quantity_change < 0 ? "minus" : "plus"}">${m.quantity_change > 0 ? "+" : ""}${esc(m.quantity_change)} ${esc(unitLabel(m.unit))}</td><td class="num">${esc(m.quantity_after)} ${esc(unitLabel(m.unit))}</td>
      <td>${esc(m.reference)}</td><td class="mono">${esc(m.ref_id)}</td></tr>`
    )
    .join("");
  const html = `<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>한결공조 ERP (Mock) — 재고</title>
<style>
body{margin:0;font-family:'Malgun Gothic',system-ui,sans-serif;background:#f3f4f6;color:#1f2937}
header{background:#1e3a5f;color:#fff;padding:14px 24px;display:flex;justify-content:space-between;align-items:center}
header h1{margin:0;font-size:20px} header .badge{background:#f59e0b;color:#1f2937;border-radius:4px;padding:2px 8px;font-size:12px;margin-left:8px}
main{padding:20px 24px;max-width:1200px;margin:0 auto} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:16px}
.card{background:#fff;border:1px solid #d1d5db;border-radius:6px;padding:12px 16px} h2{font-size:16px;margin:4px 0 10px} h2 small{color:#6b7280;font-weight:normal}
.tag{font-size:11px;border-radius:3px;padding:2px 6px;margin-right:6px;color:#fff} .tag.WAREHOUSE{background:#2563eb} .tag.VAN{background:#059669}
table{width:100%;border-collapse:collapse;font-size:13px} th,td{border-bottom:1px solid #e5e7eb;padding:6px 8px;text-align:left} th{background:#f9fafb}
.num{text-align:right} .minus{color:#dc2626} .plus{color:#059669} .muted{color:#9ca3af} .mono{font-family:Consolas,monospace;font-size:11px;color:#6b7280}
.origin{font-size:11px;border-radius:3px;padding:1px 6px;background:#e5e7eb} .origin.ERP{background:#fde68a} .origin.SALESFORCE{background:#dbeafe}
form.op{display:flex;flex-wrap:wrap;gap:8px;align-items:end} form.op label{display:flex;flex-direction:column;font-size:12px;color:#4b5563;gap:2px} form.op input,form.op select{padding:5px 6px;border:1px solid #d1d5db;border-radius:4px;font:inherit} form.op button{padding:6px 14px;border:0;border-radius:4px;background:#1e3a5f;color:#fff;cursor:pointer} #opResult{margin-top:8px;font-size:13px}
.warn{background:#fee2e2;border:1px solid #fca5a5;color:#991b1b;padding:8px 12px;border-radius:4px;margin-bottom:12px}
</style></head><body>
<header><h1>한결공조 ERP <span class="badge">Mock</span></h1><span>재고 현황 · ${esc(fmt(now()))}</span></header>
<main>${maintenance === "on" ? '<div class="warn">점검(장애) 모드: API가 503으로 응답합니다.</div>' : ""}
<div class="grid">${locHtml || '<p class="muted">위치가 없습니다. 초기 재고를 적재하세요.</p>'}</div>
<section class="card" style="margin-top:16px"><h2>ERP 입고 · 재고 조정 (시연용)</h2>
<p class="muted" style="margin:0 0 8px;font-size:12px">ERP에서만 생기는 변동입니다. Salesforce가 15분마다 이력을 가져가 변동량만큼 재고를 조정합니다(IF-02). 시연용 화면이라 로그인 없이 입력합니다.</p>
<form class="op" id="opForm"><label>작업<select id="opKind"><option value="receive">입고 (+)</option><option value="adjust">조정 (±)</option></select></label>
<label>위치<select id="opLoc">${locs.map((l) => `<option value="${esc(l.code)}">${esc(l.name)} (${esc(l.code)})</option>`).join("")}</select></label>
<label>부품 코드<input id="opPart" required placeholder="예: RFG-404A" size="12"></label>
<label>수량<input id="opQty" type="number" step="0.01" required size="6"></label>
<label>메모<input id="opNote" placeholder="예: 구매 입고 PO-123" size="18"></label>
<button type="submit">반영</button></form>
<div id="opResult"></div></section>
<script>
document.getElementById("opForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  const kind = document.getElementById("opKind").value;
  const qty = Number(document.getElementById("opQty").value);
  const body = { locationCode: document.getElementById("opLoc").value, partCode: document.getElementById("opPart").value.trim(), note: document.getElementById("opNote").value.trim() || undefined };
  if (kind === "receive") body.quantity = qty; else body.quantityChange = qty;
  const out = document.getElementById("opResult");
  try {
    const res = await fetch("/ui/stock/" + kind, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
    const data = await res.json();
    if (res.ok && data.status === "OK") { const p = data.push || {}; const sf = p.status === "SENT" ? (p.result === "APPLIED" ? "즉시 반영됨" : p.result + " " + (p.message || "")) : p.status === "DISABLED" ? "푸시 꺼짐(1시간 안에 가져오기)" : "실패(1시간 안에 가져오기) " + (p.message || ""); out.textContent = "반영됨: 남은 수량 " + data.remainingQty + " · 이력 #" + data.movementId + " · Salesforce: " + sf; setTimeout(() => location.reload(), 4000); }
    else { out.textContent = "거부: " + (data.message || data.error || res.status); }
  } catch (err) { out.textContent = "오류: " + err.message; }
});
</script>
<section class="card" style="margin-top:16px"><h2>최근 재고 이동 이력 (50건)</h2>
<table><thead><tr><th class="num">번호</th><th>일시</th><th>구분</th><th>출처</th><th>위치</th><th>부품</th><th class="num">변화</th><th class="num">변경 후</th><th>참조(출동·이동)</th><th>Salesforce Id</th></tr></thead>
<tbody>${moveHtml || '<tr><td colspan="10" class="muted">이력 없음</td></tr>'}</tbody></table></section></main></body></html>`;
  return new Response(html, {
    headers: { "content-type": "text/html; charset=utf-8" }
  });
}
