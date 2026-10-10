# 한결공조 AS 관리 시스템 · Claude Code 작업 맥락

Windmillsoft Salesforce 개발자 온보딩(2026.10.1~19) 개인 프로젝트. 가상 고객사 "한결공조"(상업·공장용 공조기 제조·설치·AS)의 AS 관리 시스템.
이 파일은 claude.ai 설계 세션의 결정 사항을 요약한 것. 실제 org 상태는 docs/org_inventory.md(읽기 전용 점검 결과)를 기준으로 한다.

## 환경
- Windows + PowerShell, 프로젝트 루트 C:\project\my-first-project (SFDX, API 62.0)
- 대상 org 별칭: devorg (Developer Edition, Field Service 활성화)
- Git: 브랜치 feature/onboarding-dN (일자별), .husky(Prettier·ESLint) 커밋 훅 있음
- 사용자: 이서연(콜센터 상담원), 김병철(경기남부센터장), 최민호(협력 기사), 관리자 "이 학민"(= 문서의 Edwin, Username edwin…, 서비스운영팀장 역할, 시스템 관리자)
- 역할 계층: 서비스운영팀장 → 콜센터 상담원 / 센터장(경기남부 등) → 각 센터 기사
- 권한 집합: HG_CallCenter, HG_CenterManager, HG_Technician, HG_Admin (프로필은 모두 Minimum Access - Salesforce)

## 데이터 모델 (V1.1, 표준 우선)
| 업무 | 오브젝트 | 핵심 |
|---|---|---|
| 고객사 | Account | Record Type: Corporation / SoleProprietor / Individual / Dealer. 외부 ID BusinessRegistrationNumber__c |
| 사업장 | CustomerSite__c | Account__c(Master-Detail, 자식 관계 AccountCustomerSites), 외부 ID SiteCode__c, ServiceCenter__c(Global Value Set ServiceCenter), UsageType__c |
| 장비 | Asset | AccountId(필수: 검증 규칙 Asset_AccountRequired로 강제), CustomerSite__c(Lookup), 외부 ID SerialKey__c, SalesChannel__c, InstallationDateSource__c, WarrantyBasis__c, fm 보증 Formula, TotalCaseCount__c, LastCaseDate__c |
| 접수 | Case | AssetId(VR 필수), CustomerSite__c, ServiceCenter__c, CancelReason__c, RepeatFailure__c. Status: New/InProgress/Completed/Closed/Canceled. 소유자 = 센터 Queue(할당 규칙 HG_CaseByServiceCenter) |
| 출동 | WorkOrder | CaseId, 소유자 = 기사, Status(Assigned/Accepted/Arrived/PendingApproval/Completed/Declined), ruPaidPartsTotal__c(Roll-Up), fmTotalCharge__c |
| 사용 부품 | ProductConsumed | AutoChargeType__c / ChargeType__c(각각 로컬 restricted picklist, 값 Free/Paid 동일하게 유지), OverrideReason__c |
| 부품·모델 | Product2 | 외부 ID ErpPartCode__c, Family(Compressor/General/EquipmentModel), ErpUnitPrice__c |
| 재고 | Location + ProductItem | 창고·기사 차량, 차량 재고 소유자 = 기사 |
- 기준값: ServiceSetting__mdt.Value__c (ApprovalAmount 500000, VisitFee 30000, RepeatFailureDays 90, RepeatFailureCount 3, SlaHoursDefault 24, SlaHoursJeju 48, SlaWarningHours 6, DealerStartGraceMonths 3, SpecialTermsShipmentMonths 6, WarrantyNoticeDays 30), WarrantyPolicy__mdt.Months__c (General 12, Compressor 36, Extended 24)

## 이미 있는 자동화
- Flow: Case_BeforeSave_FillFromAsset(저장 전, 장비 → 고객사·사업장·센터·긴급), Case_AfterSave_UrgentAlert(긴급 메일), Case_Screen_Cancel(접수 취소)
- 할당 규칙 HG_CaseByServiceCenter(id 01Qaj000008ijWHEAY), 센터 Queue: 서울·경기남부·충청 + 경기북부(추가 예정). 영남·호남·강원·제주는 데이터가 없어 미생성, 규칙에 안 걸리면 기본 사례 소유자(관리자)
- 리포트 3 + 동적 대시보드(HangyeolOpsReports / HangyeolOpsDashboards)
- Validation Rule 다수(사업자번호 형식, 대리점 연장보증 불가, 보증 기준 일치, 장비 필수, 취소 사유 등)
- Case.Closed_Lock: 종결·취소된 접수 수정 차단. 예외는 사용자 지정 권한 HG_BypassValidation(HG_Admin에만). Apex·트리거도 이 규칙의 영향을 받으므로 종결·취소 접수는 갱신 대상에서 제외하는 것이 원칙
- Apex: CaseStatsService (recalculateAssetCaseStats, applyRepeatFailureFlags, markRepeatFailures) — D4에서 배포. markRepeatFailures는 종결·취소 접수 제외
- 승인 프로세스·트리거: 아직 없음 (D5 예정)

## 코딩 규칙 (사내 Naming Convention v3.0)
- 클래스: <속성명>Service / Selector / TriggerHandler / Batch / Schedulable, 테스트는 <클래스명>Test
- 메서드 camelCase 동사+명사, Map 변수는 값By키(예: casesByAsset)
- 파일 헤더 주석: @description, @layer, @author, @date, 변경 이력, @see / 줄 주석 태그 // DESC: // PERF: // WARN:
- 메타데이터 설명: "YY-MM-DD 설명 by Edwin"
- 벌크 안전: 컬렉션 입력, 루프 안 SOQL/DML 금지, 모아서 → 한 번 조회 → Map → 한 번 저장
- 트리거는 회사 트리거 프레임워크(핸들러 패턴), 오브젝트당 트리거 1개

## 일정
- D4(10/7) SOQL·서비스 클래스·200건 벌크 검증 / D5(10/8) 트리거(Case·WorkOrder·ProductConsumed)·승인 프로세스 / D6(10/12) 테스트 85%·Batch / D7~8 LWC·연동(Mock) / D9 배포·산출물 / D11(10/19) 발표

## 권한 (V1.1 매트릭스)
- 협력 기사(HG_Technician)는 고객사·사업장·장비·접수 오브젝트 권한 없음(의도된 설계, 고객 명단 비공개). 현장 정보는 작업 주문의 Formula로
- ProductConsumed: 상담원 R, 센터장 R/E, 기사 C/R/E/D · WorkOrder: 상담원 R, 센터장 C/R/E, 기사 R/E · Product2·Location·ProductItem: 전원 R

## 작업 원칙
- org에 이미 있는 구성과 문서가 다르면 org를 기준으로 하고, 차이를 보고
- 설계 결정이 필요한 변경(필드 추가·이름 변경·로직 변경)은 먼저 묻기
- picklist 값은 API 이름 사용, 실제 값은 org에서 확인
