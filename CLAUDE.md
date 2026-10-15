# 한결공조 AS 관리 시스템 · Claude Code 작업 맥락

마지막 갱신: 2026-10-15

Windmillsoft Salesforce 개발자 온보딩(2026.10.1~19) 개인 프로젝트. 가상 고객사 "한결공조"(상업·공장용 공조기 제조·설치·AS)의 AS 관리 시스템.
실제 org 상태가 기준이고, 이 파일과 다르면 org를 따른 뒤 차이를 보고한다. 결정 근거는 docs/decision-log.md(최신이 위). docs/org_inventory.md는 10/6 시점 점검 결과(오래됨).

## 환경

- Windows + PowerShell(Git Bash도 있음), 프로젝트 루트 C:\project\my-first-project (SFDX, sourceApiVersion 67.0, Apex 클래스·트리거 API 67.0)
- 대상 org 별칭: devorg (Developer Edition, Field Service 활성화). sf CLI가 느리면 `$env:SF_DISABLE_AUTOUPDATE='true'`
- Git: 브랜치 feature/onboarding-dN(일자별), 현재 feature/onboarding-d8. .husky 커밋 훅(lint-staged → Prettier, LWC는 ESLint·Jest)
- 포맷: Prettier(prettier-plugin-apex, 2칸). retrieve 후 CRLF·LF가 섞이면 `npx prettier --write "force-app/**/*.{cls,trigger}"`
- 사용자: 이서연(콜센터 상담원), 김병철(경기남부센터장), 최민호(경기남부 협력 기사, Manager = 김병철), 관리자 "이 학민"(= Edwin, 서비스운영팀장 역할, 시스템 관리자)
- 역할 계층: 서비스운영팀장 → 콜센터 상담원 / 센터장(경기남부 등) → 각 센터 기사
- 권한 집합: HG_CallCenter, HG_CenterManager, HG_Technician, HG_Admin. 프로필은 상담원·센터장·기사 모두 Minimum Access - Salesforce(같은 프로필), 관리자는 시스템 관리자
- 커밋·PR에 Claude 표기(Co-Authored-By 등) 넣지 않음. 답은 한국어

## 데이터 모델 (V1.1, 표준 우선 · 화면 이름은 objectTranslations 한국어)

| 업무      | 오브젝트(화면 이름)                | 핵심                                                                                                                                                                                                                                                                                                   |
| --------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 고객사    | Account(고객사)                    | Record Type: Corporation / SoleProprietor / Individual / Dealer. 외부 ID BusinessRegistrationNumber__c. 레이아웃 HG 고객사 Layout(대리점 포함, 장비 관련 목록)                                                                                                                                         |
| 사업장    | CustomerSite__c(사업장)            | Account__c(Master-Detail), 외부 ID SiteCode__c, ServiceCenter__c(완전 자동, 아래), 주소 필드(도로명·우편번호·시도·시군구·행정구역 코드), OnSiteContactPhone__c·SecondaryContactPhone__c(Phone 타입). 사업장 Layout에 장비 관련 목록                                                                    |
| 장비      | Asset(장비)                        | AccountId 필수(VR Asset_AccountRequired), CustomerSite__c, 외부 ID SerialKey__c(= SerialNumber, Flow가 맞춤), 보증 Formula, TotalCaseCount__c·LastCaseDate__c·RecentCaseCount__c·RepeatFailure__c(읽기 전용 집계). 이름은 Flow 자동 생성. 목록 보기 "전체 장비"·"반복 고장 장비"(센터장·운영팀장 공유) |
| 접수      | Case(접수)                         | AssetId(VR 필수), CustomerSite__c, ServiceCenter__c, SymptomType__c(NoCooling·Noise·Leak·ErrorCode·Other), CancelReason__c, RepeatFailure__c. Status: New/InProgress/Completed/Closed/Canceled. 소유자 = 센터 Queue. 레코드 페이지 HG_CaseRecordPage                                                   |
| 출동      | WorkOrder(출동)                    | CaseId, 소유자 = 기사, Status(Assigned/Accepted/Arrived/PendingApproval/Completed/Declined), ruPaidPartsTotal__c, fmTotalCharge__c, fmNeedsApproval__c, 승인 필드(HasExceptionFree__c·CustomerConsent__c·ApprovalRequestReason__c·ApprovalRejectReason__c·ApprovalStatus__c)                           |
| 사용 부품 | ProductConsumed(사용 부품)         | AutoChargeType__c / ChargeType__c(Free/Paid), OverrideReason__c, ErpSyncStatus__c(Pending/Synced/Failed/NeedsReview)·재시도 횟수·메시지·ERP 남은 수량. WorkOrderId·ProductItemId·Product2Id는 생성 후 수정 불가                                                                                        |
| 부품·모델 | Product2(제품)                     | 외부 ID ErpPartCode__c, Family(Compressor/General/EquipmentModel), ErpUnitPrice__c                                                                                                                                                                                                                     |
| 재고      | Location(위치) + ProductItem(재고) | 창고·기사 차량(LocationType Warehouse/Van), Location.ErpLocationCode__c(WH-GS-001, VAN-GS-001 등). 차량 재고 소유자 = 기사                                                                                                                                                                             |
| 재고 이동 | ProductTransfer(재고 이동)         | 창고 → 차량 보충, 수령 시 IF-06 전송. ERP 상태 필드는 사용 부품과 같음                                                                                                                                                                                                                                 |
| ERP 기록  | ErpInboundLog__c, ErpSyncState__c  | IF-02 역방향 기록(목록 보기 "전체 기록"), Custom Setting LastMovementId__c(기준 이력 번호)                                                                                                                                                                                                             |

- 표준 필드 레이블은 설정 → 탭 및 레이블 이름 바꾸기로 바꿨고 objectTranslations/<오브젝트>-ko/*.fieldTranslation-meta.xml로 저장소에 있음. 조회 필드 이름은 가리키는 오브젝트 이름을 따라감(예: 장비의 모델 칸 = "제품"). 레이블 변경 후 화면 확인은 Ctrl+Shift+R
- 기준값(저장소에 전부 있음): ServiceSetting__mdt.Value__c — ApprovalAmount 500000, VisitFee 30000, RepeatFailureDays 90, RepeatFailureCount 3, SlaHoursDefault 24, SlaHoursJeju 48, SlaWarningHours 6, DealerStartGraceMonths 3, SpecialTermsShipmentMonths 6, WarrantyNoticeDays 30, ErpMaxRetry 3
- WarrantyPolicy__mdt(General 12, Compressor 36, Extended 24)는 저장소에 있음, ServiceCenterMapping__mdt 32건(시군구 5자리·시도 2자리 → 센터), TriggerSetting__mdt 3건(Case·ProductConsumed·ProductTransfer)

## 이미 있는 자동화

### Flow · 규칙 · 승인

- Flow: Case_BeforeSave_FillFromAsset(장비 → 고객사·사업장·센터·긴급), Case_AfterSave_UrgentAlert, Case_Screen_Cancel, Asset_BeforeSave_NameAndSerialKey(이름 = 모델/고객사/사업장/시리얼 끝자리, 시리얼 키 = 일련번호, 생성 또는 관련 값 변경 시만), CustomerSite_AfterSave_RenameAssets·Account_AfterSave_RenameAssets(이름 바뀌면 장비 이름 다시 생성)
- 할당 규칙 HG_CaseByServiceCenter, 센터 Queue: 서울·경기남부·충청·경기북부(구성원 없음). 그 밖은 기본 사례 소유자(관리자)
- Validation Rule 다수. Case.Closed_Lock(종결·취소 접수 수정 차단, 예외 사용자 지정 권한 HG_BypassValidation = HG_Admin만) — Apex도 영향을 받으므로 종결·취소 접수는 갱신 대상에서 제외
- 승인 프로세스 1 `WorkOrder.HG_WorkOrderApproval` "출동 승인 (예외 무상·고액 유상)"(10/07 설정 화면 생성, 활성, 저장소에 있음): 진입 = 상태 Arrived + 승인 요청 사유 + (HasExceptionFree__c 또는 fmTotalCharge__c > 500000) + (500000 이하이거나 CustomerConsent__c). **500000이 숫자로 박혀 있음**. 기준값(ServiceSetting ApprovalAmount)을 따라가게 바꾸기로 했으나, 승인 프로세스 진입 조건은 $CustomMetadata를 쓰는 수식 필드(fmNeedsApproval__c 등)를 참조할 수 없음(배포 오류 "필드가 없습니다") → 방법 결정 대기. 제출자 = 소유자(기사), 승인자 = 제출자의 Manager(센터장, 단계 "센터장 승인", 위임 허용). 제출 시 승인 대기·상태 PendingApproval, 승인·반려·회수 시 상태 Arrived + 승인 상태 필드 갱신, 결과 메일 알림. 필드 업데이트·메일 알림은 workflows/WorkOrder.workflow-meta.xml, 메일 템플릿은 email/unfiled$public/HG_WO_ApprovalRequest·HG_WO_ApprovalResult
- 승인 프로세스 2 `Asset.HG_WarrantyCorrectionApproval` "보증 기준일 정정 승인"(10/07, 활성, 저장소에 있음): 진입 = 요청 설치일·요청 근거·정정 사유 입력 + 정정 상태가 Requested 아님. 승인자 = 김병철 사용자 직접 지정(org별 Username, 다른 org 배포 시 바꿔야 함). 필드 업데이트 4개는 workflows/Asset.workflow-meta.xml, 메일 템플릿 HG_Asset_CorrectionRequest
- 리포트 3 + 동적 대시보드(HangyeolOpsReports / HangyeolOpsDashboards)

### Apex · 트리거

- 트리거(회사 프레임워크, 오브젝트당 1개, 부모 TriggerHandler, 스위치 TriggerSetting__mdt, 우회 TriggerHandler.bypassedHandlers):
  - CaseTrigger → CaseTriggerHandler(before insert 반복 고장 판정, after insert/update/delete/undelete 장비 집계 CaseStatsService)
  - ProductConsumedTrigger → ProductConsumedTriggerHandler 1.4(before insert 재고 초과 거부 VanStockService + 유·무상 판정 WarrantyService, after insert ERP 전송 예약, before delete 삭제 규칙, after delete 재고 되돌림(R6로 제거 예정), after undelete 복원 거부)
  - ProductTransferTrigger → ProductTransferTriggerHandler(수령 시 ERP 전송 예약)
  - CustomerSiteTrigger → CustomerSiteTriggerHandler(before insert/update 서비스센터 자동 지정)
- 반복 고장: 접수 RepeatFailure__c는 before insert 스냅샷(최근 90일 + 같은 묶음, 기준 3건째부터). 장비 단위 RecentCaseCount__c·RepeatFailure__c는 트리거 + 매일 02:00 Batch(AssetRepeatFailureBatch ← AssetRepeatFailureSchedulable, 예약 "HG 반복 고장 재계산")
- 접근 모드: API 67.0부터 Apex 기본이 user mode. **모든 조회·DML에 모드 명시**(모드 없는 문장 0). 시스템 계산(집계·판정·ERP·Batch) = WITH SYSTEM_MODE / AccessLevel.SYSTEM_MODE, 화면 컨트롤러 = with sharing + WITH USER_MODE. WITH SECURITY_ENFORCED는 67.0에서 불가
- 사업장 서비스센터 **완전 자동**: 누가 저장하든 CustomerSiteTrigger가 행정구역 코드 → ServiceCenterMapping__mdt로 센터를 채움(트리거 필드 지정이라 FLS와 무관). 서비스센터 필드는 모든 권한 집합에서 읽기 전용. 주소 검색 없이 저장·주소 손수정·매핑 없는 주소·센터만 변경은 거부. 매핑 변경 후 재적용 scripts/apex/d8_site_center_reapply.apex(APPLY=false 미리 보기)
- 재고 초과: 화면(partAddForm) + 컨트롤러(addPart) + 사용 부품 트리거(VanStockService, 모든 입력 경로)에서 같은 문구로 거부, 정확히 남은 수량은 허용

### LWC · 화면

- 장비 검색 탭(HG_AssetSearch → assetSearch, AssetSearchController), 장비 레코드 페이지 HG_AssetRecordPage(assetDetail + assetRecentCases, AssetDetailController)
- 출동 레코드 페이지 HG_WorkOrderRecordPage: workOrderParts(부모, @wire getParts) ⊃ partAddForm(자식, 기사 차량 재고 목록·남은 0 비활성, 저장 후 partadded 이벤트). WorkOrderPartsController. 출동 페이지 표준 "사용 부품 새로 만들기"는 숨김(사용 부품 탭 등 다른 곳엔 남음)
- 고객사·사업장 새로 만들기 재정의(데스크톱만, 모바일은 표준): Aura 래퍼 accountNewOverride·customerSiteNewOverride(lightning:actionOverride + isUrlAddressable, pageReference 변화 시 LWC 다시 그림) ⊃ accountNew·customerSiteNew(LDS record-edit-form, 저장·취소 때 초기화). 관련 목록에서 열면 고객사 자동 입력(inContextOfRef), 고객사 유형은 표준 선택 화면에서 전달
- 도로명주소 검색(IF-07): 공통 addressSearch(검색·선택만, addressselected 이벤트, Enter = 바로 검색) — 사업장 등록·고객사 등록·빠른 작업 "주소 검색"(addressEditAction) 세 곳에서 사용. AddressSearchController(Named Credential HG_JusoApi), CustomerSiteAddressService
- 공통 c/ldsUtils.reduceErrors. 화면 문구는 Custom Label(95개, 기본 언어 en_US에 한국어 값, 생성 스크립트로 관리). 컨트롤러는 with sharing + USER_MODE
- 주의: 일반 HTML 요소(option 등)에 불리언 속성을 바인딩할 때 false 대신 null(LWC가 disabled="false"를 남김)

### ERP 연동 (Mock ERP, docs/interface_definition.md IF-01~07)

- Mock: erp-mock/(Cloudflare Workers + D1), https://hg-erp-mock.hg-erp-mock.workers.dev. `/api/*` = Salesforce용, x-api-key 필수 / `/ui/stock/receive·adjust` = 재고 화면 전용, 키 없음 / `/`(재고·이력 화면) / `/api/admin/maintenance`(시연용 장애 모드 → 503) / `/api/admin/seed`(초기 적재·재적재). 이력 번호(AUTOINCREMENT)는 재적재해도 이어서 증가. 배포는 wrangler(로그인은 Edwin이 직접)
- 인증: Named Credential HG_ErpMock, 키는 External Credential HG_ErpMock 보안 주체 HG_ErpPrincipal의 ApiKey(설정 화면에서 입력, 메타데이터·Git에 없음). **실행 사용자에게 보안 주체 접근 + UserExternalCredential 읽기 둘 다 필요**(HttpCalloutMock 테스트로는 안 잡힘 → 실제 사용자로 확인)
- 재고 원칙: Salesforce 재고를 ERP 값으로 덮어쓰지 않음. ERP 응답 남은 수량은 기록만(불일치 표시). ERP에서만 생긴 변동은 변동량만큼 조정
- IF-03 사용 부품 → ERP 차감 / IF-06 재고 이동(수령) → ERP: 트리거 after insert/update → ErpSyncQueueable → ErpInventoryService(200건 = 콜아웃 1번, 결과 SYSTEM_MODE 저장, 메시지 "[코드] 내용"). 일시적 실패(5xx·시간 초과·연결·401) = Failed → 재전송, 영구적(재고 부족·없는 코드)·상한 초과 = NeedsReview. 재전송 ErpRetryBatch ← ErpRetrySchedulable(매시 정각, 예약 "HG ERP 재전송", 상한 ErpMaxRetry 3, 10분 넘은 Pending도 대상, Batch를 Type.forName으로 생성해 배포 막힘 회피)
- 사용 부품 삭제: 실패·ERP 거부(NeedsReview)만 허용, 대기·완료는 before delete 거부, 휴지통 복원 거부. **삭제 시 Salesforce 표준도 재고를 되돌리는데 Apex(restoreStockForDeleted)도 되돌려 이중 증가(R6)** → 표준에 맡기기로 결정, 코드 수정 대기
- IF-02 ERP → Salesforce 역방향(현재 Pull): ErpStockSyncSchedulable(00·15·30·45분 예약 4개 "HG ERP 재고 동기화 :00" 등) → ErpStockSyncBatch(쪽 단위) → ErpStockSyncService. `GET /api/movements?after={LastMovementId}`. 이력 출처 SALESFORCE·ERP·SEED 중 **ERP 출처 RECEIPT·ADJUST만** 변동량만큼 반영, 없는 재고는 새로 생성. 데이터 문제(없는 코드·0 미만)는 ErpInboundLog__c에 오류 기록 후 건너뜀, 통신·저장 실패는 Savepoint로 되돌리고 번호 유지. 스크립트 d7_erp_inbound_preview·baseline·run·schedule.apex
- 초기 적재·시연 초기화 scripts/apex/d7_erp_seed.apex(대기·실패 건이 있으면 중단). 재전송 수동 d7_erp_retry_run.apex. 창고 WH-GS-001(경기남부, 기사 읽기 공유)

## 코딩 규칙 (사내 Naming Convention v3.0)

- 클래스: <속성명>Service / Selector / TriggerHandler / Batch / Schedulable, 테스트는 <클래스명>Test
- 메서드 camelCase 동사+명사, Map 변수는 값By키
- 파일 헤더 주석: @description, @layer, @author, @date, 변경 이력, @see / 줄 주석 태그 // DESC: // PERF: // WARN:
- 메타데이터 설명: "YY-MM-DD 설명 by Edwin"
- 벌크 안전: 컬렉션 입력, 루프 안 SOQL/DML 금지
- 테스트: TestDataFactory 공통 데이터, 메서드 접두어 normal/reject/bulk, 상담원·기사는 System.runAs(기사는 Field Service 권한 집합 라이선스 필요), ERP 테스트만 ErpInventoryService.enqueueInTests = true

## 일정 · 현황

- D4~D8 완료(브랜치 feature/onboarding-d4 a15d9a5, d5 9070a35, d6 a24d1a2, d7 63abe71, d8 진행 중 최신 375728a). D11(10/19) 발표 완료
- 테스트 163개 통과(테스트 클래스 19), org 커버리지 96%(2026-10-14)
- 삭제됨: CaseRejectPracticeTest(저장소·org), AccountController(저장소·org), 루트 schema.sql
- 문서: docs/decision-log.md, docs/interface_definition.md(IF-01~07: 구현 02·03·06·07, 범위 밖 01·04·05), docs/d8_security_review.md(보안 결과표, 남은 위험 R2·R4·R6), docs/d8_lwc_memo.md, docs/d7_lwc_memo.md, docs/d6_screen_design.md(SC-01~06), docs/d6_test_report.md, docs/d6_config_externalization.md, docs/d5_*.md, docs/org_inventory.md(10/6 점검)
- 산출물(요건서·권한 매트릭스 V1.1 → V2.0, ERD 재작성 중, 배포 절차 미작성)은 저장소 밖(다운로드·바탕 화면)

### 대기 중인 일

- R6: ProductConsumedTriggerHandler after delete의 restoreStockForDeleted 제거(삭제 허용·복원 거부 규칙은 유지)
- 승인 프로세스 1 진입 조건을 기준값 따라가게: 승인 진입 조건은 $CustomMetadata 수식 필드를 못 씀 → 방법 결정 대기(시험용 수식 필드 WorkOrder.fmConsentSatisfied__c가 org에만 배포돼 있음, 저장소 미커밋)
- CTI 가상 착신 시뮬레이터: 설계 완료·구현 대기. 유틸리티 바 패널(발신 번호 + IVR 증상 + 시리얼 뒤 4자리) → SOSL로 사업장 현장·보조 번호 → 고객사 대표 번호 순 조회 → LightningModal 접수 작성 팝업(1건 채움·여러 건 후보·없음 검색, 자동 저장 없음). 장비 검색 시리얼 클릭 = 장비 요약 모달. 새 필드·오브젝트 없음
- ERP → Salesforce 즉시 반영(Push) 검토: 다른 세션에서 진행 예정

## 권한 (V1.1 매트릭스 + D8)

- 협력 기사(HG_Technician)는 고객사·사업장·장비·접수 오브젝트 권한 없음(고객 명단 비공개). 현장 정보는 출동의 Formula로
- OWD: 접수·출동·위치·재고·재고 이동 비공개, 사업장·사용 부품 부모 따름, 고객사·장비 공개 읽기/쓰기(R3: 고객사가 여러 센터에 걸쳐 유지), ERP 기록 공개 읽기. 공유 규칙 16개(접수 2·출동 4·위치 5·재고 5)
- ProductConsumed 오브젝트 권한은 org가 받지 않음(부모 WorkOrder 권한을 따름), FLS는 권한 집합에 있음
- 외부 자격 증명 보안 주체: 주소(HG_JusoPrincipal) = 상담원·센터장·관리자, ERP(HG_ErpPrincipal) = 기사·관리자. 4개 모두 UserExternalCredential 읽기
- 프로필은 저장소에 최소 파일만(대리점 레이아웃 지정): profiles/Admin·Minimum Access - Salesforce. 전체 프로필 retrieve로 덮어쓰지 말 것

## 작업 원칙

- org와 문서가 다르면 org 기준, 차이 보고. 설계 결정이 필요한 변경(필드·이름·로직)은 먼저 묻기. picklist 값은 API 이름
- **실제 org에서 Batch 실행·재적재·일괄 변경 전 대상 건수부터 확인**(연동 전 사용 부품 8건이 ERP로 가 이중 차감된 사고, 재적재 사이 저장으로 이중 차감된 사고 — decision-log ERP 13·15). 시연 데이터는 쓰고 나면 되돌리기
- 예약 작업 "HG 반복 고장 재계산"이 있으면 Schedulable → Batch → CaseStatsService → WarrantyService 묶음 배포가 "보류 중인 작업"으로 막힘 → System.abortJob → 배포 → scripts/apex/d6_schedule.apex로 재예약("Apex 작업이 있어도 배포 허용"은 켜지 않음). ERP 예약 클래스는 Type.forName으로 회피
- 배포는 폴더(-d objects) 말고 -m 메타데이터 이름으로. 오브젝트 정의 일부·Global Value Set은 저장소에 없음
- 화면 확인은 실제 사용자 동작으로(스크립트로 값을 넣으면 disabled 같은 문제를 못 잡음). 레이블 변경 후 Ctrl+Shift+R
- 키·logs/는 커밋 금지

## 여러 세션 작업 규칙

- 세션마다 git worktree로 폴더·브랜치를 나눔(예: 메인 C:\project\my-first-project = feature/onboarding-d8, ERP 푸시 C:\project\my-first-project-push = feature/erp-push)
- 세션은 맡은 범위의 파일만 수정, 다른 세션 범위는 읽기만
- CLAUDE.md·decision-log는 각 세션이 직접 고치지 말고, 끝날 때 바꿀 내용을 정리해 보고 → 메인 세션이 합쳐서 반영
- 같은 org에 배포하므로 배포 전에 대상 메타데이터 목록을 확인하고, 다른 세션 범위의 메타데이터는 배포하지 않음
- 실제 org 데이터 변경(재적재·일괄 저장)은 한 번에 한 세션만, 하기 전에 Edwin에게 확인
