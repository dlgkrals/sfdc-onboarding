# 인터페이스 정의서 — 한결공조 AS 관리

| 문서번호  | 버전 | 작성일자   | 프로젝트                             | 작성자               | 검토자 | 승인자 |
| --------- | ---- | ---------- | ------------------------------------ | -------------------- | ------ | ------ |
| HG-IF-001 | V1.2 | 2026-10-13 | 한결공조 AS 관리 (Salesforce 온보딩) | 이학민 (초안 Claude) |        |        |

## 변경 이력

| 버전 | 변경일자   | 작성자 | 변경 내용                                                                                                                                                                              |
| ---- | ---------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| V1.0 | 2026-10-13 | 이학민 | 최초 작성: 도로명주소 검색                                                                                                                                                             |
| V1.2 | 2026-10-13 | 이학민 | IF-01(부품 마스터 동기화)·IF-02(차량 재고 동기화) 채움, 둘 다 범위 밖                                                                                                                  |
| V1.1 | 2026-10-13 | 이학민 | 설계 번호 체계 반영: IF-01~05 유지, 재고 이동 → ERP는 IF-06, 도로명주소 검색은 IF-07(옛 IF-05). 목록에 IF-01~07 전체와 상태 표시. 상담원 주소 저장 시 센터 자동 반영(Apex SYSTEM_MODE) |

## 1. 인터페이스 목록

| No  | I/F ID | 인터페이스 명        | 설명                                                             | 송신       | 수신                      | 방향                               | 방식                                     | 처리형태                                | 주기                            | 상태                                                                                                                                                                       |
| --- | ------ | -------------------- | ---------------------------------------------------------------- | ---------- | ------------------------- | ---------------------------------- | ---------------------------------------- | --------------------------------------- | ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | IF-01  | IF_ERP_PART_0001     | ERP → Product2 부품 마스터 동기화 (부품 코드·이름·분류·단가)     | ERP        | Salesforce                | 수신(Inbound)                      | 배치 동기화                              | Batch                                   | 매일                            | **범위 밖** (초기 이관 Data Loader로 대체, External ID `ErpPartCode__c` upsert)                                                                                            |
| 2   | IF-02  | IF_ERP_VANSTOCK_0001 | ERP → Salesforce 재고 변동 동기화 (ERP에서만 생긴 입고·조정)     | ERP        | Salesforce                | 수신(Inbound, Salesforce가 가져옴) | REST(HTTPS GET, JSON, x-api-key)         | Batch + Schedulable                     | 15분마다(시연은 수동)           | **구현 완료** (2026-10-13: 이력 번호 이후 변동 조회 → 입고·조정만 변동량만큼 조정, 새 재고 생성, 기록 ErpInboundLog__c. 기준점 17, 미리 보기로 반영 대상 0건 확인 후 예약) |
| 3   | IF-03  | IF_ERP_CONSUME_0001  | 사용 부품 → ERP 재고 차감 (창고·기사 차량)                       | Salesforce | ERP (Mock)                | 송신(Outbound)                     | REST(HTTPS POST, JSON, x-api-key)        | Online(Queueable 비동기) + 재전송 Batch | 사용 부품 저장 시 · 매시 재전송 | **구현 완료** (5번: 트리거 → Queueable, 200건 = 콜아웃 1번, 2026-10-13 실제 연동 확인. 재전송 Batch는 7번)                                                                 |
| 4   | IF-04  | IF_ERP_STOCK_0001    | ERP 창고 재고 조회                                               | Salesforce | ERP (Mock)                | 송신(Outbound)                     | REST(HTTPS GET, JSON)                    | Online                                  | 조회 시                         | **범위 밖** (Mock 서버에 `GET /api/stock`만 있음, Salesforce 화면 연동 없음)                                                                                               |
| 5   | IF-05  | IF_ERP_SHIPMENT_0001 | 출하 조회 (장비 출하일 등)                                       | Salesforce | ERP                       | 송신(Outbound)                     | —                                        | —                                       | —                               | **범위 밖**                                                                                                                                                                |
| 6   | IF-06  | IF_ERP_TRANSFER_0001 | 재고 이동 → ERP (창고 → 기사 차량 보충, ProductTransfer 수령 시) | Salesforce | ERP (Mock)                | 송신(Outbound)                     | REST(HTTPS POST, JSON, x-api-key)        | Online(Queueable 비동기) + 재전송 Batch | 재고 이동 수령 시 · 매시 재전송 | **구현 완료** (6번: 수령 시 트리거 → Queueable, 200건 = 콜아웃 1번, 기사 수령 테스트 포함. 실제 연동 확인은 9번 리허설, 재전송 Batch는 7번)                                |
| 7   | IF-07  | IF_JUSO_ADDRESS_0001 | 도로명주소 검색 (사업장·고객사 주소 입력, 사업장 센터 자동 지정) | Salesforce | 행정안전부 도로명주소 API | 송신(Outbound)                     | REST(HTTPS POST, form-urlencoded → JSON) | Online                                  | 사용자 검색 시                  | **구현 완료** (2026-10-13, 실제 호출 확인)                                                                                                                                 |

- IF-01(수신): 이번 온보딩 범위 밖, 초기 이관으로 대신함. IF-02(수신) 상세는 3절
- IF-03·IF-06 상세(요청·응답 매핑)는 ERP 연동 구현 후 추가

## 2. IF-07 도로명주소 검색

### ■ 개요

| 항목          | 내용                                                                                                                                                                                                  |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 목적          | 상담원·센터장이 사업장·고객사 주소를 정확한 도로명주소로 입력하고, 사업장은 행정구역 코드로 서비스센터를 자동 지정                                                                                    |
| 호출 화면     | 사업장·고객사 레코드의 빠른 작업 "주소 검색" (`addressEditAction` → 공통 `addressSearch`)                                                                                                             |
| 호출 프로그램 | `[Apex] AddressSearchController.searchAddresses(keyword, pageNumber)` · `saveSiteAddress(siteId, address)` → `CustomerSiteAddressService` · `ServiceCenterMappingService.resolveServiceCenter(admCd)` |
| 대상 URL      | `callout:HG_JusoApi/addrlink/addrLinkApi.do` → `https://business.juso.go.kr/addrlink/addrLinkApi.do`                                                                                                  |
| 인증          | 승인키 `confmKey`. External Credential `HG_JusoApi` 보안 주체 `HG_JusoPrincipal`의 인증 매개변수 `ConfmKey`, 요청 본문 merge field `{!$Credential.HG_JusoApi.ConfmKey}` (코드·Git·로그에 키 없음)     |
| 권한          | 상담원·센터장·관리자 권한 집합: 컨트롤러 실행 + 보안 주체 사용                                                                                                                                        |
| 시간 제한     | 10초                                                                                                                                                                                                  |
| 승인키        | 개발용(30일). 만료 시 `E0014` → 화면에 "승인키가 없거나 만료" 안내 → 관리자가 운영키로 교체                                                                                                           |

### ■ 요청 (OUT: Salesforce → 주소 API)

| IN/OUT | Table       | Seq | Field        | PK  | Type   | 길이 | 필수 | 설명                                                                          |
| ------ | ----------- | --- | ------------ | --- | ------ | ---- | ---- | ----------------------------------------------------------------------------- |
| OUT    | (요청 본문) | 1   | confmKey     |     | String |      | Y    | 승인키 (merge field)                                                          |
| OUT    | (요청 본문) | 2   | keyword      |     | String | 80   | Y    | 검색어. 앞뒤 공백 제거, `% = > < [ ] ( ) ; ' " \` 제거, 80자 제한, URL 인코딩 |
| OUT    | (요청 본문) | 3   | currentPage  |     | Number |      | Y    | 페이지 번호 (1부터)                                                           |
| OUT    | (요청 본문) | 4   | countPerPage |     | Number |      | Y    | 10 고정                                                                       |
| OUT    | (요청 본문) | 5   | resultType   |     | String |      | Y    | `json`                                                                        |

### ■ 응답 (IN: 주소 API → Salesforce)

| IN/OUT | Table          | Seq | Field         | PK  | Type   | 길이 | 필수 | 설명 → 저장 위치                                                                         |
| ------ | -------------- | --- | ------------- | --- | ------ | ---- | ---- | ---------------------------------------------------------------------------------------- |
| IN     | results.common | 1   | errorCode     |     | String |      | Y    | `0` 정상, 그 외 오류 (HTTP는 오류여도 200)                                               |
| IN     | results.common | 2   | errorMessage  |     | String |      | Y    | 오류 메시지                                                                              |
| IN     | results.common | 3   | totalCount    |     | Number |      | Y    | 전체 건수 ("N건 중 M건 표시", "더 보기")                                                 |
| IN     | results.juso   | 4   | roadAddrPart1 |     | String |      | Y    | 도로명주소(참고항목 제외) → 사업장 `RoadAddress__c` / 고객사 `BillingStreet` 앞부분      |
| IN     | results.juso   | 5   | roadAddrPart2 |     | String |      |      | 참고항목 (예: (평택동)) → 사업장 `RoadAddressNote__c`(100자) / 고객사 `BillingStreet` 끝 |
| IN     | results.juso   | 6   | zipNo         |     | String | 5    | Y    | 우편번호 → `PostalCode__c` / `BillingPostalCode`                                         |
| IN     | results.juso   | 7   | siNm          |     | String |      | Y    | 시도 → 사업장 `Sido__c` (고객사는 저장 안 함, 결정 B)                                    |
| IN     | results.juso   | 8   | sggNm         |     | String |      |      | 시군구 → 사업장 `Sigungu__c` / 고객사 `BillingCity`                                      |
| IN     | results.juso   | 9   | admCd         |     | String | 10   | Y    | 행정구역 코드 → 사업장 `AdminDistrictCode__c`, 서비스센터 매핑 키                        |
| IN     | results.juso   | 10  | jibunAddr     |     | String |      |      | 지번주소 (화면 표시만)                                                                   |

### ■ Mapping Rule

| 대상                      | 규칙                                                                                                                                                                                                                                                                                                                          |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 사업장 `ServiceCenter__c` | `ServiceCenterMapping__mdt`에서 admCd **앞 5자리(시군구) → 앞 2자리(시도)** 순으로 찾음. **센터장·관리자**: 매핑 값으로 미리 채우고 저장 전 변경 가능(본인 권한으로 저장). **상담원**: 센터 편집 권한 없음 → 저장 시 서버가 admCd로 다시 매핑해 `SYSTEM_MODE`로 반영(화면에서 보낸 센터 값은 무시). 매핑에 없으면 센터 그대로 |
| 사업장 `DetailAddress__c` | 사용자가 모달에서 입력 (동·층·호)                                                                                                                                                                                                                                                                                             |
| 고객사 청구지             | `BillingCountryCode = KR`, `BillingStateCode` 비움, `BillingCity = sggNm`, `BillingStreet = roadAddrPart1 + ", 상세주소" + " 참고항목"`, `BillingPostalCode = zipNo`                                                                                                                                                          |
| 저장                      | 사업장: Apex `saveSiteAddress` (주소는 `USER_MODE`, 상담원의 센터만 `SYSTEM_MODE`) 후 `notifyRecordUpdateAvailable`. 고객사: LDS `updateRecord` (사용자 권한·검증 규칙 그대로)                                                                                                                                                |

### ■ 오류 처리

| 구분        | 조건                                                     | 화면 안내                                                                 |
| ----------- | -------------------------------------------------------- | ------------------------------------------------------------------------- |
| 검색어 짧음 | 정리 후 2글자 미만                                       | "검색어를 2글자 이상 입력하세요." (API 호출 안 함)                        |
| 승인키 오류 | `E0001` 미승인 · `E0014` 개발키 만료 · `E0015` 범위 초과 | "주소 검색 승인키가 없거나 만료되었습니다. 관리자에게 문의하세요. (코드)" |
| 검색어 오류 | `E0005`~`E0013` 등                                       | API 메시지 그대로 + 코드                                                  |
| 서버 오류   | HTTP 200 외, 시간 초과·연결 실패, JSON 아님              | "주소 검색 서버에 연결하지 못했습니다. 잠시 후 다시 시도하세요."          |
| 결과 없음   | totalCount 0                                             | "검색 결과가 없습니다. 도로명과 건물번호를 함께 입력해 보세요."           |

### ■ 테스트

- `AddressSearchControllerTest` (HttpCalloutMock): 정상 매핑·요청 형식, 결과 없음, 상담원 runAs, 검색어 정리, 짧은 검색어(호출 없음), 키 오류 E0001·E0014, 검색어 오류 E0006, HTTP 500·연결 실패·JSON 아님·common 없음
- `ServiceCenterMappingServiceTest`: 시군구 우선, 시도, 최신·옛 시도 코드(강원 51/42, 전북 52/45, 군위 27720/47720), 매핑 없음, 매핑 값이 서비스센터 picklist 값인지
- 실제 데이터 확인(2026-10-13): 기존 사업장 50곳의 행정구역 코드를 매핑에 넣은 결과 50곳 모두 실제 센터와 일치

## 3. IF-02 ERP 재고 변동 → Salesforce (역방향)

### ■ 개요

| 항목           | 내용                                                                                                                                                                                       |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 목적           | 구매 입고·실사 조정처럼 **ERP에서만 생기는 재고 변동**을 Salesforce 재고(ProductItem)에 반영                                                                                               |
| 방식           | Salesforce가 주기적으로 가져옴(pull). ERP 이력 번호(movements.id) 기준 "마지막으로 가져온 번호 이후"만 조회                                                                                |
| 호출 프로그램  | `ErpStockSyncSchedulable`(00·15·30·45분 예약 4개) → `ErpStockSyncBatch`(scope 1 = 한 쪽 200건, 최대 10쪽) → `ErpStockSyncService.syncNextPage`                                             |
| 대상 URL       | `callout:HG_ErpMock/api/movements?after={번호}&limit=200` (GET)                                                                                                                            |
| 인증           | IF-03과 같음: External Credential `HG_ErpMock` 보안 주체 `HG_ErpPrincipal`의 `ApiKey` → `x-api-key` 헤더                                                                                   |
| 이력 번호 저장 | Custom Setting `ErpSyncState__c.LastMovementId__c`(조직 기본값). 반영·기록과 **같은 저장**에서만 올림                                                                                      |
| 기록           | `ErpInboundLog__c`: ERP 입고·조정 1건마다 반영/오류, 변동량, 반영 후 수량, 메시지. `MovementId__c` 고유(외부 ID)                                                                           |
| 운영 스크립트  | 미리 보기 `d7_erp_inbound_preview.apex`(반영 없이 건수) · 기준점 `d7_erp_inbound_baseline.apex`(운영 시작 1회) · 즉시 실행 `d7_erp_inbound_run.apex` · 예약 `d7_erp_inbound_schedule.apex` |

### ■ 응답 (IN: ERP → Salesforce)

| Field                           | Type                      | 설명                                                                                |
| ------------------------------- | ------------------------- | ----------------------------------------------------------------------------------- |
| items[].id                      | Number                    | 이력 번호 (오름차순)                                                                |
| items[].type                    | String                    | CONSUME · TRANSFER_OUT · TRANSFER_IN · SEED · **RECEIPT(입고)** · **ADJUST(조정)**  |
| items[].origin                  | String                    | SALESFORCE(Salesforce가 보낸 사용·이동) · **ERP(ERP에서만 생김)** · SEED(초기 적재) |
| items[].locationCode / partCode | String                    | → Location.ErpLocationCode__c / Product2.ErpPartCode__c                             |
| items[].quantityChange          | Number                    | 변동량 (±, 소수 둘째 자리)                                                          |
| items[].unit                    | String                    | Each · kg → 새 재고의 QuantityUnitOfMeasure                                         |
| lastId / hasMore / latestId     | Number / Boolean / Number | 이 쪽 마지막 번호 / 다음 쪽 있음 / ERP 최신 번호(기준점용)                          |

### ■ 처리 규칙

| 경우                                 | 처리                                                                                                             |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| origin = ERP 이고 RECEIPT·ADJUST     | 재고를 FOR UPDATE로 잠그고 **현재 수량 + 변동량** (ERP 값으로 덮어쓰지 않음). 기록 "반영"                        |
| 위치+부품 재고가 Salesforce에 없음   | 재고 새로 생성 (소유자 = 위치 소유자, 단위 = ERP 단위)                                                           |
| origin = SALESFORCE · SEED           | 건너뜀 (이미 Salesforce에 있는 변동). 기록 없음, 번호는 넘어감                                                   |
| 없는 위치·부품 코드, 반영하면 0 미만 | **데이터 문제**: 다시 해도 같으므로 기록 "오류"(`[UNKNOWN_CODE]` · `[NEGATIVE_STOCK]`)하고 건너뜀, 번호는 넘어감 |
| 연결 실패 · HTTP 오류 · 저장 실패    | **일시 문제**: 이 쪽 전체 되돌림(Savepoint), 번호 그대로 → 다음 실행에서 다시                                    |
| 같은 변동이 다시 들어옴              | 번호 이후만 조회하므로 정상적으로는 없음. 번호가 되돌려져도 `MovementId__c` 고유키로 저장 거부 → 이중 반영 없음  |
| 기준점 없음                          | `[NO_BASELINE]` 가져오지 않음 (초기 적재·과거 이력 반영 방지)                                                    |

### ■ ERP Mock 입력 (시연용)

- `POST /api/stock/receive` { locationCode, partCode, quantity, note } · `POST /api/stock/adjust` { locationCode, partCode, quantityChange(±), note } — 둘 다 origin = ERP
- 재고 화면(/)의 "ERP 입고 · 재고 조정" 입력. API 키는 화면에서 입력하고 저장하지 않음
