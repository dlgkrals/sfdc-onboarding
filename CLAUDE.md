# 한결공조 AS 관리 시스템 · Claude Code 작업 맥락

Windmillsoft Salesforce 개발자 온보딩(2026.10.1~19) 개인 프로젝트. 가상 고객사 "한결공조"(상업·공장용 공조기 제조·설치·AS)의 AS 관리 시스템.
이 파일은 claude.ai 설계 세션의 결정 사항을 요약한 것. 실제 org 상태는 docs/org_inventory.md(읽기 전용 점검 결과)를 기준으로 한다.

## 환경

- Windows + PowerShell, 프로젝트 루트 C:\project\my-first-project (SFDX, sourceApiVersion 67.0, Apex 클래스·트리거 API 67.0)
- 대상 org 별칭: devorg (Developer Edition, Field Service 활성화)
- Git: 브랜치 feature/onboarding-dN (일자별), .husky 커밋 훅(lint-staged → Prettier, LWC는 ESLint·Jest). npm install 해야 훅이 동작(2026-10-11 설치)
- 포맷: Prettier(prettier-plugin-apex, 들여쓰기 2칸). retrieve 후 줄바꿈이 CRLF·LF로 섞이므로 `npx prettier --write "force-app/**/*.{cls,trigger}"` 재실행
- 사용자: 이서연(콜센터 상담원), 김병철(경기남부센터장), 최민호(협력 기사), 관리자 "이 학민"(= 문서의 Edwin, Username edwin…, 서비스운영팀장 역할, 시스템 관리자)
- 역할 계층: 서비스운영팀장 → 콜센터 상담원 / 센터장(경기남부 등) → 각 센터 기사
- 권한 집합: HG_CallCenter, HG_CenterManager, HG_Technician, HG_Admin (프로필은 모두 Minimum Access - Salesforce)

## 데이터 모델 (V1.1, 표준 우선)

| 업무      | 오브젝트               | 핵심                                                                                                                                                                                                                      |
| --------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 고객사    | Account                | Record Type: Corporation / SoleProprietor / Individual / Dealer. 외부 ID BusinessRegistrationNumber__c                                                                                                                    |
| 사업장    | CustomerSite__c        | Account__c(Master-Detail, 자식 관계 AccountCustomerSites), 외부 ID SiteCode__c, ServiceCenter__c(Global Value Set ServiceCenter), UsageType__c                                                                            |
| 장비      | Asset                  | AccountId(필수: 검증 규칙 Asset_AccountRequired로 강제), CustomerSite__c(Lookup), 외부 ID SerialKey__c, SalesChannel__c, InstallationDateSource__c, WarrantyBasis__c, fm 보증 Formula, TotalCaseCount__c, LastCaseDate__c |
| 접수      | Case                   | AssetId(VR 필수), CustomerSite__c, ServiceCenter__c, CancelReason__c, RepeatFailure__c. Status: New/InProgress/Completed/Closed/Canceled. 소유자 = 센터 Queue(할당 규칙 HG_CaseByServiceCenter)                           |
| 출동      | WorkOrder              | CaseId, 소유자 = 기사, Status(Assigned/Accepted/Arrived/PendingApproval/Completed/Declined), ruPaidPartsTotal__c(Roll-Up), fmTotalCharge__c                                                                               |
| 사용 부품 | ProductConsumed        | AutoChargeType__c / ChargeType__c(각각 로컬 restricted picklist, 값 Free/Paid 동일하게 유지), OverrideReason__c                                                                                                           |
| 부품·모델 | Product2               | 외부 ID ErpPartCode__c, Family(Compressor/General/EquipmentModel), ErpUnitPrice__c                                                                                                                                        |
| 재고      | Location + ProductItem | 창고·기사 차량, 차량 재고 소유자 = 기사                                                                                                                                                                                   |

- 기준값: ServiceSetting__mdt.Value__c (ApprovalAmount 500000, VisitFee 30000, RepeatFailureDays 90, RepeatFailureCount 3, SlaHoursDefault 24, SlaHoursJeju 48, SlaWarningHours 6, DealerStartGraceMonths 3, SpecialTermsShipmentMonths 6, WarrantyNoticeDays 30), WarrantyPolicy__mdt.Months__c (General 12, Compressor 36, Extended 24)

## 이미 있는 자동화

- Flow: Case_BeforeSave_FillFromAsset(저장 전, 장비 → 고객사·사업장·센터·긴급), Case_AfterSave_UrgentAlert(긴급 메일), Case_Screen_Cancel(접수 취소)
- 할당 규칙 HG_CaseByServiceCenter(id 01Qaj000008ijWHEAY), 센터 Queue: 서울·경기남부·충청·경기북부(HG_GyeonggiNorthCases, 경기북부센터장 역할이 없어 구성원 없음). 영남·호남·강원·제주는 데이터가 없어 미생성, 규칙에 안 걸리면 기본 사례 소유자(관리자)
- 리포트 3 + 동적 대시보드(HangyeolOpsReports / HangyeolOpsDashboards)
- Validation Rule 다수(사업자번호 형식, 대리점 연장보증 불가, 보증 기준 일치, 장비 필수, 취소 사유 등)
- Case.Closed_Lock: 종결·취소된 접수 수정 차단. 예외는 사용자 지정 권한 HG_BypassValidation(HG_Admin에만). Apex·트리거도 이 규칙의 영향을 받으므로 종결·취소 접수는 갱신 대상에서 제외하는 것이 원칙
- Apex 서비스: CaseStatsService 1.5 (recalculateAssetCaseStats: 누적·최근 접수일·최근 N일 접수 수·반복 고장 장비 / applyRepeatFailureFlagsForInsert), WarrantyService 1.1 (사용 부품 유·무상 판정). markRepeatFailures·applyRepeatFailureFlags는 1.4에서 삭제
- 시스템 모드: 이 org에서는 Apex 조회·저장이 실행 사용자 권한에 막힘(상담원 → 장비 집계 필드 읽기 전용, 기사 → 접수·장비 권한 없음). 시스템이 계산하는 값은 서비스에서 WITH SYSTEM_MODE / AccessLevel.SYSTEM_MODE로 명시(D6에서 발견)
- 반복 고장 판정(before insert): DB 최근 90일 건수 + 묶음 안에서 Trigger.new 순서대로 센 같은 장비 건수 ≥ 3 → 기준 횟수째 접수부터만 표시. 접수의 RepeatFailure__c는 접수 시점 스냅샷, 다시 판정하지 않음
- 장비 단위 반복 고장(D6): Asset.RecentCaseCount__c(최근 90일 접수 수)·Asset.RepeatFailure__c(반복 고장 장비), 읽기 전용(상담원·센터장·관리자 읽기, 기사 없음). 접수 트리거와 매일 02:00 Batch(AssetRepeatFailureBatch ← AssetRepeatFailureSchedulable, 예약 이름 "HG 반복 고장 재계산", 범위 200)가 재계산. 대상: RecentCaseCount__c > 0 또는 RepeatFailure__c = true
- 트리거(D5): CaseTrigger → CaseTriggerHandler (before insert 반복 고장, after insert/update/delete/undelete 장비 집계), ProductConsumedTrigger → ProductConsumedTriggerHandler 1.1 (before insert 판정만, before update 없음)
- 재귀 방지: CaseTriggerHandler 1.1은 after update를 접수별 마지막 처리 상태(장비 Id + 취소 여부)로 막음. Id 기준 TriggerHandler.filterUnprocessed는 결함 원인이라 TriggerHandler 1.2(D6)에서 삭제
- 트리거 공통: TriggerHandler 부모 클래스, 비활성화 스위치 TriggerSetting__mdt(IsActive__c, 레코드 Case·ProductConsumed, 없으면 활성)
- ProductConsumed의 WorkOrderId·ProductItemId·Product2Id는 생성 후 수정 불가 → 판정은 insert 시점 스냅샷, 부품을 바꾸려면 삭제 후 재입력
- 생성 방식: ProductConsumed는 ProductItemId 방식(표준 가격표 비활성). 필수 WorkOrderId, QuantityConsumed
- 승인 프로세스: 아직 없음 (docs의 승인 상세 정의 기준으로 예정)
- 설계 문서: docs/d5_trigger_design.md, docs/d5_flow_vs_trigger.md, docs/d6_screen_design.md(화면 초안, 검토 전), docs/d6_config_externalization.md / 검증 결과: docs/d5_bulk_verification.md, docs/d6_test_report.md (D4 벌크 검증 결과는 문서 없이 커밋 메시지·채팅으로만 남음)
- 테스트: TestDataFactory 공통 데이터, 메서드 이름 접두어 normal/reject/bulk, 상담원·기사는 System.runAs + 테스트 사용자(기사는 Field Service 권한 집합 라이선스 필요)
- 벌크·정리 스크립트: scripts/apex/d4_bulk.apex(markRepeatFailures 부분은 1.4부터 주석)·d4_cleanup.apex, d5_bulk_case.apex·d5_bulk_case_update.apex·d5_bulk_parts.apex·d5_cleanup.apex (표시: 제목 [BULK5], 위치 BULK5 차량), d6_backfill.apex(새 필드 초기 적재 1회)·d6_run_batch.apex·d6_schedule.apex. 실행 로그는 logs/(커밋 제외)

## 코딩 규칙 (사내 Naming Convention v3.0)

- 클래스: <속성명>Service / Selector / TriggerHandler / Batch / Schedulable, 테스트는 <클래스명>Test
- 메서드 camelCase 동사+명사, Map 변수는 값By키(예: casesByAsset)
- 파일 헤더 주석: @description, @layer, @author, @date, 변경 이력, @see / 줄 주석 태그 // DESC: // PERF: // WARN:
- 메타데이터 설명: "YY-MM-DD 설명 by Edwin"
- 벌크 안전: 컬렉션 입력, 루프 안 SOQL/DML 금지, 모아서 → 한 번 조회 → Map → 한 번 저장
- 트리거는 회사 트리거 프레임워크(핸들러 패턴), 오브젝트당 트리거 1개

## 일정

- 진행: D4 완료(a15d9a5, feature/onboarding-d4), D5 완료(45af40d·e5ff670·9070a35, feature/onboarding-d5), D6 완료(feature/onboarding-d6). 테스트 36개 통과(정상 26·불허 4·벌크 6), org 커버리지 94%(docs/d6_test_report.md)
- D5 계획 중 미구현: WorkOrder 트리거(선택 항목), 승인 프로세스
- D4(10/7) SOQL·서비스 클래스·200건 벌크 검증 / D5(10/8) 트리거(Case·WorkOrder·ProductConsumed)·승인 프로세스 / D6(10/12) 테스트 85%·Batch / D7~8 LWC·연동(Mock) / D9 배포·산출물 / D11(10/19) 발표

## 권한 (V1.1 매트릭스)

- 협력 기사(HG_Technician)는 고객사·사업장·장비·접수 오브젝트 권한 없음(의도된 설계, 고객 명단 비공개). 현장 정보는 작업 주문의 Formula로
- ProductConsumed: 상담원 R, 센터장 R/E, 기사 C/R/E/D (목표) · WorkOrder: 상담원 R, 센터장 C/R/E, 기사 R/E · Product2·Location·ProductItem: 전원 R
- 실제: ProductConsumed 오브젝트 권한은 org가 받지 않음(배포해도 무시, 시스템 관리자 프로필에도 행 없음) → 부모 WorkOrder 권한을 따르는 것으로 보임. 필드 권한(FLS)은 세 권한 집합에 있음. Login As 확인 전

## 작업 원칙

- org에 이미 있는 구성과 문서가 다르면 org를 기준으로 하고, 차이를 보고
- 설계 결정이 필요한 변경(필드 추가·이름 변경·로직 변경)은 먼저 묻기
- picklist 값은 API 이름 사용, 실제 값은 org에서 확인
