# D5 트리거 설계: 한결공조 AS 관리

- 일자: 2026-10-08 (D5) · 작성: Edwin
- 커리큘럼 실습: 핵심 업무 규칙 트리거 2개 이상(핸들러 패턴), Flow와 역할 재정리, 200건 벌크 검증
- 발표(연휴 후): 트리거 + 테스트 초안
- 기준: CLAUDE.md, docs/org_inventory.md, CaseStatsService 1.1
- 업무 판정 규칙(4-1)은 Edwin이 확정함: 보증 미확정 부품은 유상 자동 판정, 압축기는 압축기·연장 만료일 중 늦은 날 기준
- 벌크 스크립트 3개(5절)는 이 문서를 보고 D4 스크립트 구조대로 새로 작성

---

## 1. 만들 것

| #   | 구분        | 파일                                                                                                    | 업무 규칙                                   |
| --- | ----------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| 0   | 공통        | `TriggerHandler.cls` (virtual 부모), `TriggerSetting__mdt` (비활성화 스위치)                            | 1-트리거-1-핸들러, 비활성화, 재귀 방지      |
| 1   | 접수        | `CaseTrigger.trigger`, `CaseTriggerHandler.cls`                                                         | BR-14 반복 고장, 장비 누적 접수·최근 접수일 |
| 2   | 사용 부품   | `ProductConsumedTrigger.trigger`, `ProductConsumedTriggerHandler.cls`, `WarrantyService.cls`            | BR-06 유·무상 자동 판정                     |
| 3   | 검증        | `scripts/apex/d5_bulk_case.apex`, `scripts/apex/d5_bulk_parts.apex`, `scripts/apex/d5_cleanup.apex`     | 200건 벌크 검증                             |
| 4   | 테스트 초안 | `CaseTriggerHandlerTest.cls`, `WarrantyServiceTest.cls` (사내 Naming Convention v3.0: `<클래스명>Test`) | 발표용 초안 (커버리지 85%는 D6)             |
| 5   | 문서        | `docs/d5_flow_vs_trigger.md`, `docs/d5_bulk_verification.md`                                            | Flow와 역할 재정리, 검증 결과               |

선택(시간이 남으면): `WorkOrderTrigger` (첫 도착 → 접수의 첫 출동 도착 일시·처리 중 전환)

---

## 2. 공통 구조

### 2-1. 비활성화 스위치 `TriggerSetting__mdt`

| 필드          | 유형     | 설명                                                                      |
| ------------- | -------- | ------------------------------------------------------------------------- |
| DeveloperName | (표준)   | 오브젝트 API 이름과 같게: `Case`, `ProductConsumed`                       |
| `IsActive__c` | Checkbox | false면 그 오브젝트의 트리거 로직 전체를 건너뜀 (데이터 이관·장애 대응용) |

레코드 2개: `Case` (IsActive true), `ProductConsumed` (IsActive true)
레코드가 없으면 **활성으로 간주**(기본 동작이 꺼지지 않게).

### 2-2. `TriggerHandler` (virtual 부모)

- `run()`: 스위치 확인 → `Trigger.operationType`으로 분기 → 아래 가상 메서드 호출
  `beforeInsert / beforeUpdate / beforeDelete / afterInsert / afterUpdate / afterDelete / afterUndelete`
- 스위치 판단: `TriggerSetting__mdt.getInstance(오브젝트명)` (SOQL 한도 미사용)
- 테스트·스크립트용 정적 우회: `public static Set<String> bypassedHandlers` (핸들러 이름을 넣으면 건너뜀)
- 재귀 방지: 핸들러별 `static Set<Id> processedIds` 또는 처리 단계별 static Boolean. 같은 트랜잭션에서 같은 레코드를 같은 단계로 두 번 처리하지 않게.
- 주석: 사내 헤더 형식(@description, @layer : TriggerHandler, 변경 이력)

### 2-3. 트리거 파일 원칙

트리거 본문은 핸들러 호출 한 줄만. 로직 금지.

```apex
trigger CaseTrigger on Case(
  before insert,
  after insert,
  after update,
  after delete,
  after undelete
) {
  new CaseTriggerHandler().run();
}
```

---

## 3. 접수 트리거 (`CaseTriggerHandler`)

### 3-1. 이벤트별 처리

| 이벤트         | 처리                                           | 사용 메서드                                                             |
| -------------- | ---------------------------------------------- | ----------------------------------------------------------------------- |
| before insert  | 새 접수의 반복 고장 표시 (DML 없음, 값만 세팅) | `CaseStatsService.applyRepeatFailureFlagsForInsert(Trigger.new)` (신규) |
| after insert   | 새 접수의 장비 집계 재계산                     | `recalculateAssetCaseStats(장비 Id들)`                                  |
| after update   | 아래 조건에 해당하는 장비만 재계산             | 같음                                                                    |
| after delete   | 지워진 접수의 장비 재계산                      | 같음                                                                    |
| after undelete | 복원된 접수의 장비 재계산                      | 같음                                                                    |

after update 재계산 대상 (oldMap 비교):

- 장비가 바뀜 → **이전 장비와 새 장비 둘 다**
- 상태가 취소(Canceled)로 바뀌거나 취소에서 다른 값으로 바뀜 (누적 수에서 취소 제외 규칙)

그 외의 수정(제목, 우선순위, 반복 고장 표시 등)은 재계산하지 않음 → 불필요한 DML과 재귀 차단.

### 3-2. CaseStatsService 추가 메서드 (1.2 추가, 1.3 묶음 내 순서 판정)

`applyRepeatFailureFlagsForInsert(List<Case> newCases)`

- 기존 `applyRepeatFailureFlags`와 같은 기준(최근 N일, 취소 제외, 기준 횟수: Custom Metadata)
- 차이: before insert 시점엔 새 접수가 DB에 없으므로 **DB 집계 건수 + 이번 묶음에서 이 접수까지 같은 장비의 새 접수 수**로 판정
- **묶음 안에서는 `Trigger.new` 순서대로 세어 기준 횟수째 접수부터만 표시** (1.3, 2026-10-11 결정)
  - 예: DB 0건 + 같은 장비 3건을 한 번에 → 1·2번째 false, **3번째만 true**
  - 예: DB에 최근 90일 2건 + 이번 묶음에 같은 장비 1건 → 3건째 → 반복 고장
  - 이유: 1.2(묶음 전체 건수를 모든 접수에 적용)는 한 번에 들어온 같은 장비의 첫 접수까지 표시해, 차례로 접수했을 때와 결과가 달랐음
- 새 접수 중 상태가 취소인 것은 건수에 넣지 않음
- 쿼리 1회(집계), DML 없음
- 변경 이력: 1.2 "before insert용 반복 고장 판정(묶음 내 건수 포함)", 1.3 "묶음 안에서는 Trigger.new 순서대로 세어 기준 횟수째부터만 표시"

### 3-3. 실행 순서 메모 (발표용)

접수 저장 시: 저장 전 Flow(고객사·사업장·센터·긴급) → **before insert 트리거(반복 고장)** → Validation Rule → 저장 → **after insert 트리거(장비 집계 → 장비 update)** → 할당 규칙(Queue) → 저장 후 Flow(긴급 메일) → 커밋
→ 트리거는 Flow가 채운 AssetId를 그대로 사용, 할당 규칙과는 서로 영향 없음.

---

## 4. 사용 부품 트리거 (`ProductConsumedTriggerHandler` + `WarrantyService`)

### 4-1. 판정 규칙 (BR-06)

| 단계                     | 내용                                                                                                                                                        |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 판정 기준일              | 출동의 **접수 생성일**(WorkOrder.Case.CreatedDate의 날짜). 없으면 오늘                                                                                      |
| 부품 분류                | Product2.Family (ProductConsumed.Product2Id가 비어 있으면 ProductItem.Product2Id로 찾기)                                                                    |
| 적용 만료일              | `Compressor` → 장비의 압축기 만료일과 (연장보증이면) 연장 만료일 중 늦은 날 / `General` 및 그 외 → 연장보증이면 연장 만료일, 아니면 기본 만료일             |
| 자동 판정                | 기준일 ≤ 적용 만료일 → `Free`, 아니면 `Paid`                                                                                                                |
| 만료일 없음(보증 미확정) | **`Paid`로 판정** (가정: 근거 없는 무상을 막기 위해 보수적으로. 기사가 근거를 확인하면 최종 판정을 무상으로 바꾸고 사유 입력 → 예외 무상 승인 대상)         |
| 저장 값                  | `AutoChargeType__c`, `WarrantyEndDateAtJudgment__c`(적용 만료일), 필드가 있으면 `PartCategoryAtUse__c`(분류), `UnitPriceAtUse__c`(Product2.ErpUnitPrice__c) |
| 최종 판정                | `ChargeType__c`가 비어 있을 때만 자동 판정 값으로 채움. **사람이 정한 값은 절대 덮어쓰지 않음**                                                             |

### 4-2. 이벤트

| 이벤트        | 처리      |
| ------------- | --------- |
| before insert | 전부 판정 |

before update 재판정은 두지 않음 (2026-10-11 결정, 처음 설계에서 제거):

- 출동(`WorkOrderId`)·제품 항목(`ProductItemId`)·부품(`Product2Id`)은 **생성 후 수정 불가**(Org describe: updateable = false) → 판정 근거가 바뀌는 update가 생길 수 없음
- 따라서 판정은 **insert 시점 스냅샷**. 이후 장비 보증 정보가 바뀌어도 이미 저장된 판정은 그대로 둠(판정 당시 만료일은 `WarrantyEndDateAtJudgment__c`에 남음)
- 부품을 바꾸려면 **삭제 후 다시 입력** → 새 insert에서 다시 판정
- 트리거 이벤트도 `before insert`만 등록

### 4-3. 쿼리 설계 (벌크 안전)

1. WorkOrderId 모으기 → `SELECT Id, CaseId, Case.CreatedDate, AssetId, Asset.HasExtendedWarranty__c, Asset.fmBasicWarrantyEndDate__c, Asset.fmCompressorWarrantyEndDate__c, Asset.fmExtendedWarrantyEndDate__c FROM WorkOrder WHERE Id IN :ids` (1회)
2. Product2Id / ProductItemId 모으기 → Product2(Family, ErpUnitPrice__c), 필요 시 ProductItem(Product2Id) 조회 (1~2회)
3. 반복문에서 Map으로 계산, DML 없음 (before 트리거라 값만 세팅)

`WarrantyService`는 `public with sharing`이 아닌 `inherited sharing` 권장: 판정은 기사(사용자) 컨텍스트에서 돌지만 장비 보증 정보는 기사가 직접 볼 권한이 없을 수 있으므로, 접근 문제가 생기면 `without sharing`으로 바꾸고 이유를 주석에 남김(Org에서 확인).

---

## 5. 200건 벌크 검증

### 5-1. 접수 (`d5_bulk_case.apex`)

- 대상 장비: 설치 완료 + 사업장 있음 + 냉동창고·서버실 제외(긴급 메일 방지)
- 접수 N건 insert만 실행 (서비스를 직접 부르지 않음 → 트리거가 처리하는지 확인)
- 출력: insert 직후 Limits, 반복 고장 표시 건수, 장비 TotalCaseCount__c 합계 변화
- N = 20, 200으로 각각 실행 → SOQL·DML 횟수 비교

### 5-2. 사용 부품 (`d5_bulk_parts.apex`)

- 생성 방식: **ProductItemId 방식**(표준 가격표가 비활성이라 PricebookEntryId 방식 불가). 필수 값은 WorkOrderId, QuantityConsumed, ProductItemId
- 준비: **벌크 전용 위치 `BULK5 차량`** 1개 + 부품 12종의 제품 항목(각 재고 10,000). 최민호 차량 등 기존 재고는 건드리지 않음
- 수량은 1로 넣어 재고가 음수가 되지 않게
- 진행 중 접수 몇 건에 출동 10건 생성 → 사용 부품 N건(출동·부품을 돌아가며) insert
- 출력: insert 직후 Limits, 자동 판정 분포(무상/유상), 판정 만료일이 채워졌는지
- ProductConsumed 필수 필드(ProductItemId 또는 PricebookEntryId 등)는 Org에서 확인해 맞출 것

### 5-3. 정리 (`d5_cleanup.apex`)

- 테스트 사용 부품 → 출동 → 접수 순으로 삭제, `BULK5 차량` 위치와 그 제품 항목 삭제, 장비 재계산은 접수 트리거(after delete)가 자동 수행되는지 확인
- 표시: 제목 `[BULK5]` 접두사, 위치 이름 `BULK5 차량`

### 5-4. 판정 기준

단계별 SOQL·DML **횟수**가 20건과 200건에서 같고 행 수만 늘면 통과. 결과는 `docs/d5_bulk_verification.md`.

---

## 6. 테스트 초안 (D5 발표용, D6에서 확장)

| 클래스                   | 케이스                                                                                                                                                                     |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CaseTriggerHandlerTest` | ① 같은 장비 접수 3건 → 3번째 반복 고장 (차례로 insert / 한 번에 insert 모두) ② 200건 insert 후 장비 누적 수 정확 ③ 접수 삭제 시 누적 수 감소 ④ 스위치 끄면 아무 처리 안 함 |
| `WarrantyServiceTest`    | ① 설치 2년 차 장비: 압축기 무상·일반 부품 유상 ② 보증 미확정 → 유상 ③ 최종 판정을 사람이 정하면 덮어쓰지 않음 ④ 200건 벌크                                                 |

`@TestSetup`으로 고객사·사업장·장비·제품 생성, `Assert` 클래스 사용, 테스트 데이터는 Custom Metadata 기본값(90일·3건, 12/36/24개월)에 의존.

---

## 7. Flow와 역할 재정리 (`docs/d5_flow_vs_trigger.md`에 표로)

| 일                                      | 맡는 쪽                 | 이유                                            |
| --------------------------------------- | ----------------------- | ----------------------------------------------- |
| 접수의 고객사·사업장·센터·긴급도 채우기 | 저장 전 Flow (유지)     | 같은 레코드 필드 채우기                         |
| 긴급 알림 메일                          | 저장 후 Flow (유지)     | 메일은 저장 후, 선언적으로 충분                 |
| 센터 Queue 배정                         | 할당 규칙 (유지)        | 표준 라우팅                                     |
| 반복 고장 표시                          | **트리거**              | 다른 접수를 세야 함 (벌크 집계)                 |
| 장비 누적 접수·최근 접수일              | **트리거**              | Lookup이라 Roll-Up 불가, 삭제·복원까지 정확히   |
| 사용 부품 유·무상 판정                  | **트리거**              | 부품·장비·접수·Custom Metadata를 함께 보는 판정 |
| 출동 부품비·예외 무상 합계              | Roll-Up (유지)          | Master-Detail, 선언적으로 충분                  |
| 예외 무상·고액 승인                     | 승인 프로세스 (D5 이후) | 사람의 승인·잠금·이력                           |
