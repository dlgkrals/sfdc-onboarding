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
 *   POST /api/admin/seed              초기 재고 적재 (Salesforce 현재 재고)
 *   POST /api/admin/maintenance       시연용 장애 모드 켜기·끄기 (켜면 API가 503)
 *   GET  /                            위치별 재고·최근 이력 화면 (읽기 전용)
 *
 * 업무 결과(성공·거부)는 HTTP 200 + 건별 status. 인증 실패 401, 요청 형식 오류 400, 장애 모드 503
 * 같은 refId(Salesforce 레코드 Id)가 다시 오면 처음 결과를 그대로 돌려줌 (재전송해도 두 번 차감 안 됨)
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
        "SELECT location_code, part_code, quantity, updated_at FROM stock WHERE location_code = ? ORDER BY part_code"
      ).bind(location)
    : env.DB.prepare(
        "SELECT location_code, part_code, quantity, updated_at FROM stock ORDER BY location_code, part_code"
      );
  const { results } = await stmt.all();
  return json({
    items: results.map((r) => ({
      locationCode: r.location_code,
      partCode: r.part_code,
      quantity: r.quantity,
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
  reference
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
    "SELECT quantity FROM stock WHERE location_code = ? AND part_code = ?"
  )
    .bind(locationCode, partCode)
    .first();
  await env.DB.prepare(
    "INSERT INTO movements (ref_id, type, location_code, part_code, quantity_change, quantity_after, reference, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
  )
    .bind(
      refId,
      type,
      locationCode,
      partCode,
      -quantity,
      row.quantity,
      reference || null,
      stamp
    )
    .run();
  return round(row.quantity);
}

async function increase(
  env,
  refId,
  type,
  locationCode,
  partCode,
  quantity,
  reference
) {
  const stamp = now();
  await env.DB.prepare(
    "INSERT INTO stock (location_code, part_code, quantity, updated_at) VALUES (?, ?, ?, ?) " +
      "ON CONFLICT(location_code, part_code) DO UPDATE SET quantity = ROUND(quantity + excluded.quantity, 2), updated_at = excluded.updated_at"
  )
    .bind(locationCode, partCode, quantity, stamp)
    .run();
  const row = await env.DB.prepare(
    "SELECT quantity FROM stock WHERE location_code = ? AND part_code = ?"
  )
    .bind(locationCode, partCode)
    .first();
  await env.DB.prepare(
    "INSERT INTO movements (ref_id, type, location_code, part_code, quantity_change, quantity_after, reference, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
  )
    .bind(
      refId,
      type,
      locationCode,
      partCode,
      quantity,
      row.quantity,
      reference || null,
      stamp
    )
    .run();
  return round(row.quantity);
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
        "SELECT quantity FROM stock WHERE location_code = ? AND part_code = ?"
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
                `재고가 부족합니다. 현재 ${round(stock.quantity)}, 요청 ${quantity}`,
                { availableQty: round(stock.quantity) }
              )
            : { refId, status: "OK", remainingQty: remaining };
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
        "SELECT quantity FROM stock WHERE location_code = ? AND part_code = ?"
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
            `출발 위치 재고가 부족합니다. 현재 ${round(stock.quantity)}, 요청 ${quantity}`,
            { availableQty: round(stock.quantity) }
          );
        } else {
          const destination = await increase(
            env,
            refId,
            "TRANSFER_IN",
            toLocationCode,
            partCode,
            quantity,
            reference
          );
          result = {
            refId,
            status: "OK",
            sourceRemainingQty: source,
            destinationRemainingQty: destination
          };
        }
      }
    }
    await saveResult(env, refId, "TRANSFER", result);
    results.push(result);
  }
  return json({ results });
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
      "INSERT OR REPLACE INTO stock (location_code, part_code, quantity, updated_at) VALUES (?, ?, ?, ?)"
    )
      .bind(s.locationCode, s.partCode, s.quantity, stamp)
      .run();
    await env.DB.prepare(
      "INSERT INTO movements (ref_id, type, location_code, part_code, quantity_change, quantity_after, reference, created_at) VALUES (NULL, ?, ?, ?, ?, ?, ?, ?)"
    )
      .bind(
        "SEED",
        s.locationCode,
        s.partCode,
        s.quantity,
        s.quantity,
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
const MOVE_LABEL = {
  SEED: "초기 적재",
  CONSUME: "사용 차감",
  TRANSFER_OUT: "이동 출고",
  TRANSFER_IN: "이동 입고"
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
      "SELECT location_code, part_code, quantity, updated_at FROM stock ORDER BY location_code, part_code"
    ).all(),
    env.DB.prepare(
      "SELECT ref_id, type, location_code, part_code, quantity_change, quantity_after, reference, created_at FROM movements ORDER BY id DESC LIMIT 50"
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
      ${(byLoc[l.code] || []).map((s) => `<tr><td>${esc(s.part_code)}</td><td class="num">${esc(s.quantity)}</td><td>${esc(fmt(s.updated_at))}</td></tr>`).join("") || '<tr><td colspan="3" class="muted">재고 없음</td></tr>'}
      </tbody></table></section>`
    )
    .join("");
  const moveHtml = moves
    .map(
      (
        m
      ) => `<tr><td>${esc(fmt(m.created_at))}</td><td>${esc(MOVE_LABEL[m.type])}</td><td>${esc(m.location_code)}</td><td>${esc(m.part_code)}</td>
      <td class="num ${m.quantity_change < 0 ? "minus" : "plus"}">${m.quantity_change > 0 ? "+" : ""}${esc(m.quantity_change)}</td><td class="num">${esc(m.quantity_after)}</td>
      <td>${esc(m.reference)}</td><td class="mono">${esc(m.ref_id)}</td></tr>`
    )
    .join("");
  const html = `<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>한결공조 ERP (Mock) — 재고</title><meta http-equiv="refresh" content="30">
<style>
body{margin:0;font-family:'Malgun Gothic',system-ui,sans-serif;background:#f3f4f6;color:#1f2937}
header{background:#1e3a5f;color:#fff;padding:14px 24px;display:flex;justify-content:space-between;align-items:center}
header h1{margin:0;font-size:20px} header .badge{background:#f59e0b;color:#1f2937;border-radius:4px;padding:2px 8px;font-size:12px;margin-left:8px}
main{padding:20px 24px;max-width:1200px;margin:0 auto} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:16px}
.card{background:#fff;border:1px solid #d1d5db;border-radius:6px;padding:12px 16px} h2{font-size:16px;margin:4px 0 10px} h2 small{color:#6b7280;font-weight:normal}
.tag{font-size:11px;border-radius:3px;padding:2px 6px;margin-right:6px;color:#fff} .tag.WAREHOUSE{background:#2563eb} .tag.VAN{background:#059669}
table{width:100%;border-collapse:collapse;font-size:13px} th,td{border-bottom:1px solid #e5e7eb;padding:6px 8px;text-align:left} th{background:#f9fafb}
.num{text-align:right} .minus{color:#dc2626} .plus{color:#059669} .muted{color:#9ca3af} .mono{font-family:Consolas,monospace;font-size:11px;color:#6b7280}
.warn{background:#fee2e2;border:1px solid #fca5a5;color:#991b1b;padding:8px 12px;border-radius:4px;margin-bottom:12px}
</style></head><body>
<header><h1>한결공조 ERP <span class="badge">Mock</span></h1><span>재고 현황 · 30초마다 새로 고침 · ${esc(fmt(now()))}</span></header>
<main>${maintenance === "on" ? '<div class="warn">점검(장애) 모드: API가 503으로 응답합니다.</div>' : ""}
<div class="grid">${locHtml || '<p class="muted">위치가 없습니다. 초기 재고를 적재하세요.</p>'}</div>
<section class="card" style="margin-top:16px"><h2>최근 재고 이동 이력 (50건)</h2>
<table><thead><tr><th>일시</th><th>구분</th><th>위치</th><th>부품</th><th class="num">변화</th><th class="num">변경 후</th><th>참조(출동·이동)</th><th>Salesforce Id</th></tr></thead>
<tbody>${moveHtml || '<tr><td colspan="8" class="muted">이력 없음</td></tr>'}</tbody></table></section></main></body></html>`;
  return new Response(html, {
    headers: { "content-type": "text/html; charset=utf-8" }
  });
}
