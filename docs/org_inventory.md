# devorg 현황 점검 (읽기 전용)

- 점검일: 2026-10-08 (D5 시작 전)
- 대상: devorg (`00Daj000019yyBiEAI`, Developer Edition, 인스턴스 API 67.0 / 프로젝트 sourceApiVersion 62.0)
- 방법: `sf org list metadata`, `sf project retrieve start`(`.tmp_inspect/`, mdapi 형식), `sf sobject describe`, `sf data query`. org에 쓰기·변경은 하지 않음
- 범위: 한결공조 프로젝트 관련 항목만. Developer Edition 샘플 메타데이터(Lead, Opportunity, Offer__c, Property__c, Enablement·EinsteinBot 폴더 등)는 제외

---

## 0. CLAUDE.md와 다른 점

### 0-1. 문서엔 있는데 org에 없는 것

| 항목 | CLAUDE.md | org 실제 | 영향 |
|---|---|---|---|
| Apex `CaseStatsService` | "이미 있는 자동화"에 기재 | **org에 없음.** 로컬에만 있고 git에도 untracked (`force-app/main/default/classes/CaseStatsService.cls`) | D5 트리거가 이 클래스를 호출한다면 먼저 배포해야 함. Asset의 `TotalCaseCount__c` 값이 있는 레코드는 0건 → 집계가 한 번도 실행되지 않음 |
| Global Value Set `ChargeType` | "ChargeType__c(Global Value Set ChargeType: Free/Paid)" | **없음.** `AutoChargeType__c`와 `ChargeType__c`는 각각 **로컬 restricted picklist** (Free, Paid) | 값은 같음. 나중에 값을 추가하면 두 필드를 따로 고쳐야 함 |
| Asset `AccountId(필수)` | 필수 | 필드 수준 필수도 아니고 VR도 없음. 플랫폼은 Account나 Contact 중 하나만 요구함 | 장비가 Contact에만 연결되면 저장됨 |
| `docs/` 설계 문서 | "설계 근거는 docs/ 참고" | 저장소에 `docs/` 폴더가 없었음 (이 파일이 처음) | — |

### 0-2. org엔 있는데 문서에 없는 것

| 구분 | 항목 |
|---|---|
| 사용자 정의 권한 | `HG_BypassValidation` (검증 규칙 우회). `Case.Closed_Lock` VR에서 사용, `HG_Admin`에만 부여 |
| Validation Rule | `Account.BillingContactEmail_Required`, `Asset.InstallDate_RequiredWithSource`, `Asset.Site_AccountMatch`, `Case.Closed_Lock`, `CustomerSite__c.ServiceCenter_Required`, `ProductConsumed.OverrideReason_Required`, `WorkOrder.Case_Required`, `WorkOrder.Complete_RequiresArrival`, `WorkOrder.DeclineReason_Required` |
| CMDT 기준값 | `SlaHoursDefault` 24, `SlaHoursJeju` 48, `SlaWarningHours` 6, `DealerStartGraceMonths` 3, `SpecialTermsShipmentMonths` 6, `WarrantyNoticeDays` 30 / WarrantyPolicy: General 12, Compressor 36, Extended 24 (개월) |
| Case SLA 필드 | `SlaHours__c`, `SlaExcluded__c`, `FirstArrivalDateTime__c`, `fmSlaDueDate__c`, `fmSlaBreached__c`, `SymptomType__c`, `CallerName__c`, `CallerPhone__c`, `PaidNoticeGiven__c` |
| WorkOrder 필드 | 승인용 `ApprovalRequestReason__c`, `ApprovalRejectReason__c`, 그 외 `AssistantTechnician__c`, `CustomerSite__c`, `ServiceCenter__c`, `VisitFee__c`, `VisitNumber__c`, `Purpose__c`, `CompletionResult__c`, `Payment*`, 사업장·장비 정보 Formula 9개 |
| ProductConsumed 필드 | `UnitPriceAtUse__c`, `PartCategoryAtUse__c`, `WarrantyEndDateAtJudgment__c`, `fmAmount__c`, `fmFreeType__c`, ERP 연동 필드 3개 (`ErpSyncStatus__c`, `ErpSyncedAt__c`, `ErpSyncMessage__c`) |
| ERP 키 | `Location.ErpLocationCode__c`, `ProductItem.ErpStockKey__c` (외부 ID), `Product2.ErpLastSyncedAt__c` |
| 기타 | `Location.ServiceCenter__c`, `Account.ruSiteCount__c`(Roll-Up), `Account.CustomerGrade__c`, `AccountStatus__c`, `PaymentMethod__c`, 청구 담당자 필드 3개, `Asset.Dealer__c`, `HasExtendedWarranty__c`, `ShipmentDate__c`, `RefrigerantType__c`, `Capacity__c`, `WarrantySpecialTerms__c` |
| 역할 계층·권한 집합·공개 그룹 | 6장 참고. 문서에는 이름만 일부 나오고 구조는 없음 |

### 0-3. 이름·값이 다르거나 주의할 것

| 항목 | CLAUDE.md | org 실제 |
|---|---|---|
| CustomerSite__c 자식 관계 | `AccountCustomerSites` | 관계 이름 `AccountCustomerSites` → SOQL에서는 **`AccountCustomerSites__r`** |
| 관리자 사용자 | "관리자(Edwin)" | 사용자 이름 **이 학민** (`edwin.b28b9597ca64@agentforce.com`), 역할 `HG_ServiceOpsManager`, 프로필 시스템 관리자 |
| 센터 Queue | "HG_GyeonggiSouthCases 등" | Queue는 **3개**(서울·경기남부·충청)뿐인데 ServiceCenter 값은 8개. 사업장이 있는 **GyeonggiNorth(8곳)는 Queue도 할당 규칙도 없음** → 기본 소유자에게 감 |
| Case Status | (문서에 없음) | `New`, `InProgress`, `Completed`, `Closed`(closed), `Canceled`(closed). VR·Flow는 `Canceled` 철자 사용 |
| 리포트·대시보드 폴더 공유 | (문서에 없음) | 역할 `HG_GyeonggiSouthCenterManager`, 그룹 `HG_CallCenter`만 View. **서울·충청 센터장은 접근 불가** |
| 권한 집합 | (문서에 없음) | **ProductConsumed에 권한을 주는 HG 권한 집합이 하나도 없음**. 기사(`HG_Technician`)는 Case·Asset 읽기 권한도 없음 → D5 ProductConsumed 트리거나 화면 테스트 전에 확인 필요 |
| Apex/API 버전 | API 62.0 | org 최대 67.0. 기존 클래스 `AccountController`는 67.0 (샘플, 프로젝트와 무관) |

---

## 1. 오브젝트별 커스텀 필드

표기: Req = 필드 수준 필수, Unique = 고유, ExtID = 외부 ID, `[R]` = restricted picklist, GVS = Global Value Set

### Account

| API 이름 | 유형 | 플래그 | Picklist 값 / 정의 |
|---|---|---|---|
| BusinessRegistrationNumber__c | Text(12) | Unique, ExtID | |
| CustomerGrade__c | Picklist | | Standard, Major, Strategic [R] |
| AccountStatus__c | Picklist | | Normal, PaymentWarning, Suspended [R] |
| PaymentMethod__c | Picklist | | MonthlyTaxInvoice, OnSiteCard [R] |
| BillingContactName__c | Text(80) | | |
| BillingContactEmail__c | Email | | |
| BillingContactPhone__c | Phone | | |
| ruSiteCount__c | Roll-Up | | COUNT(CustomerSite__c) via Account__c |

샘플 org 기존 필드(프로젝트 무관): Active__c, CustomerPriority__c, NumberofLocations__c, SLA__c, SLAExpirationDate__c, SLASerialNumber__c, UpsellOpportunity__c, Test_Field__c

### CustomerSite__c

| API 이름 | 유형 | 플래그 | Picklist 값 / 정의 |
|---|---|---|---|
| Account__c | Master-Detail(Account) | Req | 자식 관계 `AccountCustomerSites` (cascade 삭제) |
| SiteCode__c | Text(20) | Unique, ExtID | |
| ServiceCenter__c | Picklist | | GVS ServiceCenter [R] |
| UsageType__c | Picklist | | ColdStorage, ServerRoom, Office, Store, Factory, Other [R] |
| RoadAddress__c / DetailAddress__c | Text(255) | | |
| RoadAddressNote__c | Text(100) | | |
| PostalCode__c | Text(5) | | |
| Sido__c / Sigungu__c | Text(20/40) | | |
| AdminDistrictCode__c | Text(10) | | |
| AccessCondition__c | Text(255) | | |
| OnSiteContactName__c | Text(80) | | |
| OnSiteContactPhone__c / SecondaryContactPhone__c | Phone | | |
| PreferredTechnician__c | Text(80) | | (사용자 Lookup 아님) |
| ContractSlaHours__c | Number(3,0) | | |
| WorkAvailableStartTime__c / EndTime__c | Time | | |
| fmFullAddress__c | Formula(Text) | | `RoadAddress__c & ", " & DetailAddress__c & " " & RoadAddressNote__c` (빈 값 생략) |
| fmMapLink__c | Formula(Text) | | 카카오맵 HYPERLINK("지도 보기") |

### Asset

| API 이름 | 유형 | 플래그 | Picklist 값 / 정의 |
|---|---|---|---|
| CustomerSite__c | Lookup(CustomerSite__c) | | 자식 관계 `CustomerSiteAssets`, 삭제 시 SetNull |
| Dealer__c | Lookup(Account) | | 자식 관계 `DealerAssets`, SetNull |
| SerialKey__c | Text(50) | Unique, ExtID | |
| SalesChannel__c | Picklist | | Direct, Dealer [R] (제어 필드) |
| InstallationDateSource__c | Picklist | **Req** | CommissioningReport, InstallationCertificate, CustomerEvidence, Unverified [R], SalesChannel__c에 종속 |
| WarrantyBasis__c | Picklist | | InstallationDate, ShipmentDate, ContractSpecialTerms [R], SalesChannel__c에 종속 |
| HasExtendedWarranty__c | Checkbox | | 기본값 false |
| ShipmentDate__c | Date | | |
| WarrantySpecialTerms__c | Long Text | | |
| InstallationLocation__c | Text(255) | | |
| RefrigerantType__c | Picklist | | R22, R410A, R32, R407C, R404A, R134a, R290, R744, Other [R] |
| Capacity__c | Number(8,2) | | |
| TotalCaseCount__c | Number(5,0) | | Apex로 채울 값 (현재 값이 있는 레코드 0건) |
| LastCaseDate__c | Date | | Apex로 채울 값 |
| fmWarrantyStartDate__c | Formula(Date) | | WarrantyBasis별: 설치일 / 출하일(대리점이면 + `DealerStartGraceMonths`) / 계약특약(설치일과 출하일 + `SpecialTermsShipmentMonths` 중 빠른 날) |
| fmBasicWarrantyEndDate__c | Formula(Date) | | 시작일 + `WarrantyPolicy.General` - 1일 |
| fmCompressorWarrantyEndDate__c | Formula(Date) | | 시작일 + `WarrantyPolicy.Compressor` - 1일 |
| fmExtendedWarrantyEndDate__c | Formula(Date) | | Direct이고 연장보증이면 기본 종료 + `WarrantyPolicy.Extended` |
| fmWarrantyStatus__c | Formula(Text) | | `미확정` / `보증 중` / `부분 보증` / `보증 만료` (한글 리터럴) |

종속 picklist 매핑

| SalesChannel__c | InstallationDateSource__c | WarrantyBasis__c |
|---|---|---|
| Direct | CommissioningReport, Unverified | InstallationDate, ContractSpecialTerms |
| Dealer | InstallationCertificate, CustomerEvidence, Unverified | InstallationDate, ShipmentDate |

### Case

| API 이름 | 유형 | 플래그 | Picklist 값 / 정의 |
|---|---|---|---|
| CustomerSite__c | Lookup(CustomerSite__c) | | 자식 관계 `CustomerSiteCases`, **Restrict** 삭제 |
| ServiceCenter__c | Picklist | | GVS ServiceCenter [R] |
| CancelReason__c | Text(255) | | |
| RepeatFailure__c | Checkbox | | 기본값 false (현재 true인 레코드 0건) |
| SymptomType__c | Picklist | | NoCooling, Noise, Leak, ErrorCode, Other [R] |
| CallerName__c | Text(80) | | |
| CallerPhone__c | Phone | | |
| PaidNoticeGiven__c | Checkbox | | |
| SlaHours__c | Number(3,0) | | |
| SlaExcluded__c | Checkbox | | |
| FirstArrivalDateTime__c | DateTime | | |
| fmSlaDueDate__c | Formula(DateTime) | | `CreatedDate + SlaHours__c/24` |
| fmSlaBreached__c | Formula(Checkbox) | | 제외가 아니고, (첫 도착 또는 현재)가 기한을 넘으면 true |

샘플 org 기존 필드(무관): EngineeringReqNumber__c, PotentialLiability__c, Product__c, SLAViolation__c

### WorkOrder

| API 이름 | 유형 | 플래그 | Picklist 값 / 정의 |
|---|---|---|---|
| CustomerSite__c | Lookup(CustomerSite__c) | | 자식 관계 `CustomerSiteWorkOrders`, Restrict |
| AssistantTechnician__c | Lookup(User) | | 자식 관계 `AssistantWorkOrders`, SetNull |
| ServiceCenter__c | Picklist | | GVS ServiceCenter [R] |
| Purpose__c | Picklist | | Diagnosis, Repair, PartReplacement, Recheck [R] |
| CompletionResult__c | Picklist | | Repaired, RevisitRequired, NotRepaired [R] |
| PaymentMethod__c | Picklist | | MonthlyTaxInvoice, OnSiteCard [R] |
| PaymentStatus__c | Picklist | | NotApplicable, Unpaid, Paid [R] |
| VisitFee__c | Currency(7,0) | | |
| VisitNumber__c | Number(2,0) | | |
| ArrivalDateTime__c / CompletedDateTime__c | DateTime | | |
| DeclineReason__c | Text(255) | | |
| ApprovalRequestReason__c / ApprovalRejectReason__c | Text(255) | | |
| CustomerConsent__c | Checkbox | | |
| WorkInstruction__c / WorkResult__c | Long Text(5000) | | |
| ruPaidPartsTotal__c | Roll-Up | | SUM(ProductConsumed.fmAmount__c) WHERE ChargeType__c = Paid |
| fmTotalCharge__c | Formula(Currency) | | `BLANKVALUE(VisitFee__c,0) + BLANKVALUE(ruPaidPartsTotal__c,0)` |
| fmWarrantyStatus__c | Formula(Text) | | `Asset.fmWarrantyStatus__c` |
| fmAssetInfo__c | Formula(Text) | | 모델명 / S/N / 설치 위치 / 냉매 |
| fmSymptom__c | Formula(Text) | | `Case.Subject` |
| fmSiteName__c, fmSiteAddress__c, fmSiteMapLink__c, fmOnSiteContact__c, fmAccessCondition__c, fmWorkHours__c | Formula(Text) | | CustomerSite__r 값 표시 |

### ProductConsumed

| API 이름 | 유형 | 플래그 | Picklist 값 / 정의 |
|---|---|---|---|
| AutoChargeType__c | Picklist | | Free, Paid [R] (**로컬 값, GVS 아님**) |
| ChargeType__c | Picklist | | Free, Paid [R] (**로컬 값, GVS 아님**) |
| OverrideReason__c | Text(255) | | |
| UnitPriceAtUse__c | Currency(10,0) | | |
| PartCategoryAtUse__c | Text(40) | | |
| WarrantyEndDateAtJudgment__c | Date | | |
| fmAmount__c | Formula(Currency) | | `QuantityConsumed * UnitPriceAtUse__c` |
| fmFreeType__c | Formula(Text) | | Free일 때 자동 판정도 Free면 `보증 내 무상`, 아니면 `예외 무상` |
| ErpSyncStatus__c | Picklist | | Pending, Synced, Failed [R] |
| ErpSyncedAt__c | DateTime | | |
| ErpSyncMessage__c | Text(255) | | |

### Product2 / Location / ProductItem

| 오브젝트 | API 이름 | 유형 | 플래그 |
|---|---|---|---|
| Product2 | ErpPartCode__c | Text(30) | Unique, ExtID |
| Product2 | ErpUnitPrice__c | Currency(10,0) | |
| Product2 | ErpLastSyncedAt__c | DateTime | |
| Location | ErpLocationCode__c | Text(30) | Unique, ExtID |
| Location | ServiceCenter__c | Picklist (GVS ServiceCenter) [R] | |
| ProductItem | ErpStockKey__c | Text(60) | Unique, ExtID |

### 표준 picklist (Standard Value Set) 와 Global Value Set

| 값 집합 | API 이름 (라벨) |
|---|---|
| GVS **ServiceCenter** | Seoul(서울센터), GyeonggiNorth(경기북부센터), GyeonggiSouth(경기남부·인천센터), Chungcheong(충청센터), Yeongnam(영남센터), Honam(호남센터), Gangwon(강원센터), Jeju(제주센터) |
| CaseStatus | New(접수), InProgress(처리 중), Completed(완료), Closed(종결, closed), Canceled(취소, closed) |
| CasePriority | Urgent(긴급), Normal(일반) |
| CaseOrigin | Phone(전화), Sales(영업담당), Email(이메일) |
| WorkOrderStatus | Assigned(배정), Accepted(수락), Arrived(도착), PendingApproval(승인 대기), Completed(완료), Declined(거절) |
| WorkOrderPriority | Low, Medium, High, Critical (기본값 그대로) |
| Product2Family | Compressor(압축기), General(일반 부품), EquipmentModel(장비 모델) |
| LocationType | Warehouse(창고), Van(차량) |

### 자식 관계 이름 (프로젝트 관련)

| 부모 | 자식.필드 | 관계 이름 (SOQL 하위 쿼리) |
|---|---|---|
| Account | CustomerSite__c.Account__c | `AccountCustomerSites__r` (cascade) |
| Account | Asset.Dealer__c | `DealerAssets__r` |
| Account | Asset.AccountId / Case.AccountId / WorkOrder.AccountId | `Assets` / `Cases` / `WorkOrders` |
| CustomerSite__c | Asset / Case / WorkOrder .CustomerSite__c | `CustomerSiteAssets__r` / `CustomerSiteCases__r` / `CustomerSiteWorkOrders__r` |
| Asset | Case.AssetId / WorkOrder.AssetId | `Cases` / `WorkOrders` |
| Case | WorkOrder.CaseId | `WorkOrders` |
| WorkOrder | ProductConsumed.WorkOrderId | `ProductsConsumed` (cascade) |
| Product2 | ProductConsumed / ProductItem / Asset .Product2Id | `ProductsConsumed` / `ProductItems` / `Assets` |
| Location | ProductItem.LocationId | `ProductItems` |
| ProductItem | ProductConsumed.ProductItemId | `ProductsConsumed` |
| User | WorkOrder.AssistantTechnician__c | `AssistantWorkOrders` |

---

## 2. Record Type

| 오브젝트 | DeveloperName | 활성 |
|---|---|---|
| Account | Corporation | O |
| Account | SoleProprietor | O |
| Account | Individual | O |
| Account | Dealer | O |

다른 프로젝트 오브젝트에는 Record Type이 없음 (Metric.Completion/Progress는 샘플)

---

## 3. Validation Rule (14개, 모두 활성)

| 오브젝트 | 이름 | 수식 요약 |
|---|---|---|
| Account | BusinessRegistrationNumber_Format | Individual이 아니면 사업자번호가 숫자 10자리여야 함 |
| Account | BillingContactEmail_Required | Individual이 아니면 청구 담당자 이메일 필수 |
| CustomerSite__c | ServiceCenter_Required | ServiceCenter__c 필수 |
| Asset | Dealer_NoExtendedWarranty | Dealer면 HasExtendedWarranty__c 불가 |
| Asset | Dealer_WarrantyBasisMatch | Dealer: 설치확인서·고객증빙이면 InstallationDate, Unverified면 ShipmentDate |
| Asset | InstallDate_RequiredWithSource | 근거가 Unverified가 아니면 InstallDate 필수 |
| Asset | Site_AccountMatch | 사업장의 Account__c가 장비 AccountId와 같아야 함 |
| Case | Asset_Required | AssetId 필수 |
| Case | CancelReason_Required | Status = Canceled면 CancelReason__c 필수 |
| Case | Closed_Lock | 이전 Status가 Closed/Canceled면 수정 불가 (`$Permission.HG_BypassValidation` 있으면 예외) |
| WorkOrder | Case_Required | CaseId 필수 |
| WorkOrder | Complete_RequiresArrival | Status = Completed면 ArrivalDateTime__c 필수 |
| WorkOrder | DeclineReason_Required | Status = Declined면 DeclineReason__c 필수 |
| ProductConsumed | OverrideReason_Required | AutoChargeType__c가 있고 ChargeType__c와 다르면 OverrideReason__c 필수 |

> D5 트리거 참고: `Case.Closed_Lock` 때문에 종결·취소된 Case를 트리거나 Apex로 update하면(예: RepeatFailure__c 표시) 실행 사용자에게 `HG_BypassValidation`이 없을 경우 실패함

---

## 4. Flow

| 이름 | 유형 | 트리거 오브젝트 / 시점 | 진입 조건 | 활성 버전 |
|---|---|---|---|---|
| Case_BeforeSave_FillFromAsset | Record-Triggered (Before Save) | Case / 생성·수정 | AssetId가 있고 (신규이거나 AssetId 변경) | v1 (최신 v1) |
| Case_AfterSave_UrgentAlert | Record-Triggered (After Save) | Case / 생성 | Priority = Urgent | v1 (최신 v1) |
| Case_Screen_Cancel | Screen Flow | — | — | v1 (최신 v1) |

모두 API 62.0. 그 밖의 `sfdc_default_ReportExport_Protection_Flow`는 플랫폼 기본 Flow

---

## 5. 승인 프로세스 · 할당 규칙 · Queue · 공개 그룹

### 승인 프로세스
없음 (ProcessDefinition 0건). D5 예정

### 할당 규칙 (Case)

| 규칙 | Id | 활성 | 항목 |
|---|---|---|---|
| HG_CaseByServiceCenter | 01Qaj000008ijWHEAY | O | 1) ServiceCenter__c = GyeonggiSouth → HG_GyeonggiSouthCases<br>2) = Seoul → HG_SeoulCases<br>3) = Chungcheong → HG_ChungcheongCases |
| Standard | 01Qaj000008cN5TEAU | X | 샘플 규칙 (Account SLA 기준) |

나머지 5개 센터(GyeonggiNorth, Yeongnam, Honam, Gangwon, Jeju)는 해당하는 항목이 없음

### Queue

| DeveloperName | 라벨 | 오브젝트 | 구성원 |
|---|---|---|---|
| HG_GyeonggiSouthCases | 경기남부·인천센터 접수 | Case | 역할 HG_GyeonggiSouthCenterManager |
| HG_SeoulCases | 서울센터 접수 | Case | 역할 HG_SeoulCenterManager |
| HG_ChungcheongCases | 충청센터 접수 | Case | 역할 HG_ChungcheongCenterManager |

Queue 이메일 없음

### 공개 그룹

| DeveloperName | 라벨 | 구성원 | 관리자 포함 |
|---|---|---|---|
| HG_CallCenter | 콜센터 | 역할 HG_CallCenterAgent | 아니오 |

---

## 6. 권한 집합 · 역할 계층 · 사용자

### 권한 집합 HG_* (오브젝트 권한, R/C/E/D/VA=View All/MA=Modify All)

| 오브젝트 | HG_Admin | HG_CallCenter | HG_CenterManager | HG_Technician |
|---|---|---|---|---|
| Account | RCED VA MA | RCE | RE | — |
| CustomerSite__c | RCED VA MA | RCE | RE | — |
| Asset | RCED VA MA | RCE | RE | — |
| Case | RCED VA MA | RCE | RE | — |
| WorkOrder | RCED VA MA | R | RCE | RE |
| **ProductConsumed** | **—** | **—** | **—** | **—** |
| Product2 | RCED | R | R | R |
| Location | RCED VA MA | R | R | R |
| ProductItem | RCED VA MA | R | R | R |
| 기타 | 사용자 정의 권한 HG_BypassValidation | RunFlow, RunReports | RunFlow, RunReports | — |
| Account Record Type | 4개 전부 | 4개 전부 | 4개 전부 | — |
| 필드 권한 수(편집 가능) | 130 (107) | 131 (55) | 131 (82) | 54 (11) |

배정: HG_Admin → 이 학민, HG_CallCenter → 이 서연, HG_CenterManager → 김 병철, HG_Technician → 최 민호

### 역할 계층

```
HG_ServiceOpsManager (서비스운영팀장)
├─ HG_CallCenterAgent (콜센터 상담원)
├─ HG_SeoulCenterManager (서울센터장)
│   └─ HG_SeoulTechnician (서울 기사)
├─ HG_GyeonggiSouthCenterManager (경기남부센터장)
│   └─ HG_GyeonggiSouthTechnician (경기남부 기사)
└─ HG_ChungcheongCenterManager (충청센터장)
    └─ HG_ChungcheongTechnician (충청 기사)
```

모든 HG 역할의 Case 접근 = Edit. 그 밖의 역할(CEO, SVP… 등 18개)은 샘플

### 활성 사용자 (Standard)

| 이름 | Username | 역할 | 프로필 |
|---|---|---|---|
| 이 학민 | edwin.b28b9597ca64@agentforce.com | HG_ServiceOpsManager | 시스템 관리자 |
| 이 서연 | seoyeon.lee@hangyeol-as.dev | HG_CallCenterAgent | Minimum Access - Salesforce |
| 김 병철 | epic.c3b435533985@orgfarm.salesforce.com | HG_GyeonggiSouthCenterManager | Minimum Access - Salesforce |
| 최 민호 | minho.choi@hangyeol-as.dev | HG_GyeonggiSouthTechnician | Minimum Access - Salesforce |

---

## 7. Custom Metadata

### ServiceSetting__mdt (Value__c, Number 18,0)

| DeveloperName | 라벨 | Value__c |
|---|---|---|
| ApprovalAmount | 센터장 승인 기준 금액 | 500000 |
| VisitFee | 출장비 | 30000 |
| RepeatFailureDays | 반복 고장 기간(일) | 90 |
| RepeatFailureCount | 반복 고장 횟수 | 3 |
| SlaHoursDefault | SLA 기본 시간 | 24 |
| SlaHoursJeju | SLA 제주 시간 | 48 |
| SlaWarningHours | SLA 임박 경고(시간) | 6 |
| DealerStartGraceMonths | 대리점 미확인 시작 유예(개월) | 3 |
| SpecialTermsShipmentMonths | 계약 특약 출하 후 상한(개월) | 6 |
| WarrantyNoticeDays | 보증 만료 안내(일) | 30 |

### WarrantyPolicy__mdt (Months__c, Number 4,0)

| DeveloperName | 라벨 | Months__c |
|---|---|---|
| General | 기본 보증 | 12 |
| Compressor | 압축기 보증 | 36 |
| Extended | 연장보증 | 24 |

---

## 8. Apex 클래스 · 트리거

| 종류 | 이름 | API | 비고 |
|---|---|---|---|
| 클래스 | AccountController | 67.0 | 샘플/연습용으로 보임, 프로젝트 네이밍 규칙과 다름 |
| 클래스 | CaseStatsService | — | **org에 없음** (로컬 untracked만) |
| 트리거 | (없음) | — | D5 예정 |

---

## 9. 리포트 · 대시보드

| 폴더 (DeveloperName / 라벨) | 공유 | 항목 |
|---|---|---|
| HangyeolOpsReports / 한결공조 운영 리포트 | 역할 HG_GyeonggiSouthCenterManager: View, 그룹 HG_CallCenter: View | `CasesByServiceCenter` 센터별 접수 현황 (CaseList, Matrix, ServiceCenter__c별 그룹)<br>`UrgentCasesByServiceCenter` 긴급 접수 현황 (CaseList, Summary, Priority = Urgent)<br>`AssetsByWarrantyStatus` 보증 상태별 장비 (AssetWithProduct, Summary, fmWarrantyStatus__c·SalesChannel__c별 그룹) |
| HangyeolOpsDashboards / 한결공조 운영 대시보드 | 위와 같음 | `ServiceOperationsOverview` 서비스 운영 현황. 동적(LoggedInUser), 위 리포트 3개 사용 |

---

## 10. 데이터 건수

| 오브젝트 | 전체 | 내역 |
|---|---|---|
| Account | 53 | Corporation 24, SoleProprietor 11, Dealer 5, Record Type 없음 13 (샘플 데이터로 보임) |
| CustomerSite__c | 50 | GyeonggiSouth 19, Seoul 14, Chungcheong 9, GyeonggiNorth 8 |
| Asset | 77 | Direct 49, Dealer 28. TotalCaseCount__c 값이 있는 레코드 0 |
| Case | 45 | New 42 (Urgent 15 / Normal 27), Closed 1, Canceled 2. RepeatFailure__c = true 0건 |
| Case 소유자 | — | 이 학민 35, 경기남부·인천센터 접수 7, 서울센터 접수 2, 충청센터 접수 1 |
| WorkOrder | 4 | Assigned 2, Accepted 1, Arrived 1 |
| ProductConsumed | 2 | Paid 1, Free 1 |
| Product2 | 39 | General 10, EquipmentModel 8, Compressor 4, Family 없음 17 (GenWatt 등 샘플) |
| Location | 1 | Van 1 ("최민호 차량", 소유자 최 민호, GyeonggiSouth, VAN-GS-001). **Warehouse 없음** |
| ProductItem | 2 | 최민호 차량: 압축기 50HP 1, 냉매 R-404A 17.5 (소유자 최 민호) |
