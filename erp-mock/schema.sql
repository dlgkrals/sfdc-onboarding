-- 한결공조 ERP Mock (Cloudflare D1 / SQLite) 스키마
-- 재고의 원본(마스터)은 ERP. Salesforce는 현장용 사본이고, 사용·이동이 생기면 이 API로 알림

DROP TABLE IF EXISTS requests;
DROP TABLE IF EXISTS movements;
DROP TABLE IF EXISTS stock;
DROP TABLE IF EXISTS locations;
DROP TABLE IF EXISTS settings;

-- 위치: 창고(WAREHOUSE) / 기사 차량(VAN). code = Salesforce Location.ErpLocationCode__c
CREATE TABLE locations (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('WAREHOUSE', 'VAN'))
);

-- 재고: 위치 × 부품. part_code = Salesforce Product2.ErpPartCode__c, 수량은 소수 허용(냉매 kg)
CREATE TABLE stock (
  location_code TEXT NOT NULL REFERENCES locations(code),
  part_code TEXT NOT NULL,
  quantity REAL NOT NULL CHECK (quantity >= 0),
  -- 수량 단위: Salesforce 제품 항목의 단위 그대로 (Each, kg). 화면 표기는 Each → 개
  unit TEXT NOT NULL DEFAULT 'Each',
  updated_at TEXT NOT NULL,
  PRIMARY KEY (location_code, part_code)
);

-- 이력: 모든 수량 변화 (사용 차감, 이동 출고·입고, 초기 적재)
CREATE TABLE movements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ref_id TEXT,
  type TEXT NOT NULL CHECK (type IN ('SEED', 'CONSUME', 'TRANSFER_OUT', 'TRANSFER_IN')),
  location_code TEXT NOT NULL,
  part_code TEXT NOT NULL,
  quantity_change REAL NOT NULL,
  quantity_after REAL NOT NULL,
  unit TEXT NOT NULL DEFAULT 'Each',
  reference TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_movements_created ON movements(created_at DESC);

-- 중복 처리 방지: Salesforce 레코드 Id(사용 부품·재고 이동)별 처리 결과. 같은 Id가 다시 오면 저장된 결과를 그대로 돌려줌
CREATE TABLE requests (
  ref_id TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('CONSUME', 'TRANSFER')),
  result_json TEXT NOT NULL,
  created_at TEXT NOT NULL
);

-- 시연용 설정 (maintenance = 'on'이면 API가 503 → "서버 장애" 재현)
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
INSERT INTO settings (key, value) VALUES ('maintenance', 'off');
