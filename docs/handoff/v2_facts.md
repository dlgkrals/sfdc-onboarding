# V2.x 문서용 사실 정리 (요건 정의서 · 권한 매트릭스 V2.1)

- 조회일: 2026-10-15, **갱신 2026-10-16**(0절 변경 요약. 사용자 프로필·센터장 출동 권한·재고 공유 규칙·BR-11·BR-18·출장비 줄은 고침, 5절 자동화 목록 표의 새 Flow·트리거·검증 규칙은 0절 참고) · 대상 org: devorg · 브랜치 feature/onboarding-d8
- 출처: org 조회(SOQL·Tooling API·메타데이터 retrieve)와 저장소 파일. 기억으로 쓴 내용 없음, 확인 못 한 것은 **확인 필요**
- 요건 기준본: `1_요건정의서_1p_V1.1.pdf`(V1.1 · 2026-10-06, BR-01~24, SC-01~16), 권한 기준본: `3_권한매트릭스_1p_V1.1.pdf`(V1.1 · 2026-10-06)
- 주의: 요건서의 SC 번호(SC-01 통합 접수 … SC-16 장비 QR)와 저장소 `docs/d6_screen_design.md`의 SC 번호(SC-01 장비 검색 … SC-10 승인 요청)는 **서로 다른 체계**. 7절에서 대응시킴

## 0. V2.1 변경 요약 (2026-10-16, V2.0 사실 정리 이후)

요건서·권한 매트릭스 V2.1에 반영할 것. 근거는 decision-log 2026-10-16 절, 상세 반영 상태는 `docs/handoff/산출물_갱신_목록.md` 4~9절.

| 구분                 | 바뀐 것                                                                                                                                                                                                                                                                                     | 요건서                 | 권한 매트릭스                                             |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- | --------------------------------------------------------- |
| 프로필               | 역할별 프로필 3개(HG 콜센터 상담원·HG 센터장·HG 협력 기사, Minimum Access 복제). 권한은 계속 권한 집합, 프로필에는 홈 지정·권리(Entitlement) 읽기 해제·기사 리포트/대시보드 탭 숨김만                                                                                                       | —                      | 프로필 행 3개, 사용자-프로필 매핑                         |
| 출동 생성            | 출동은 접수 [기사 배정](빠른 작업 → 화면 Flow Case_Screen_DispatchTechnician → DispatchService)으로만. 센터장 출동 **생성 권한 제거(수정 유지)**, 사용자 지정 권한 HG_DispatchWorkOrder(센터장·관리자), 기사 목록 = 역할 계층, 같은 접수 재사용(회차 + 1), 출장비 = ServiceSetting VisitFee | 출동 생성 경로·BR 신규 | 출동 C 제거, 사용자 지정 권한·DispatchService 클래스 접근 |
| 출동 빈칸 안전망     | 저장 전 Flow WorkOrder_BeforeSave_FillAsset: 접수의 장비·고객사·사업장·서비스센터, 빈 출장비 → 기준값                                                                                                                                                                                       | 자동화 목록            | —                                                         |
| 길 안내              | 목록 보기 배정 대기 접수·재배정 필요·종결 대기 접수(센터장 역할), 접수 경로(Path) 접수·완료 단계 안내, 출동 탭 앱 내 안내는 **게시 해제**                                                                                                                                                   | 화면                   | 목록 보기 공유                                            |
| 역할별 홈            | 앱 HangyeolAS 홈 탭, 앱 기본 = 관리자 홈(ERP 실패·확인 필요 + 운영 대시보드), 프로필별: 상담원(장비 검색 바로가기·오늘 내가 받은 접수·긴급 접수·반복 고장 장비), 센터장(안내 → 배정 대기 → 재배정 필요 → 승인할 항목 → 종결 대기 → 센터 접수 차트), 기사(내 출동·내 차량 재고)              | 화면(시작 화면)        | 목록 보기·리포트 폴더 "센터장 리포트" 공유                |
| 누적 청구액          | 장비·고객사·사업장 TotalWorkOrderCharge__c(방문한 출동 = 도착·승인 대기·완료의 총 청구액 합) + VisitedWorkOrderCount__c(방문 출동 수), 요약 카드 "누적 청구액 ₩X · 방문 출동 N건 (도착·승인 대기·완료 기준)", 출동 이력 동적 목록(5건)                                                      | 새 규칙(누적 기준)     | FLS 상담원·센터장·관리자 읽기                             |
| 접수 자동 완료·BR-18 | 접수 열린 출동 수·완료 출동 수, 처리 중 → 완료 자동, 완료 → 처리 중 재오픈, VR OpenWorkOrders_BlockClose                                                                                                                                                                                    | BR-18 구현             | FLS 읽기                                                  |
| 승인 요청            | AP1 승인 페이지 필드 13개, 출동 ApprovalSummary__c(이유·부품별 줄·사유·고객 동의·메모) = 제출 코멘트 = 승인 요청 메일 본문                                                                                                                                                                  | BR-08 화면             | FLS 기사·관리자 수정(Flow 저장용), 센터장 읽기            |
| 재고 공유            | 재고 ServiceCenter__c·WarehouseStock__c(저장 전 Flow ProductItem_BeforeSave_FillFromLocation), 창고 재고 규칙을 소유자 기준 → 조건 기준(경기남부·창고)으로 교체(다른 센터 창고 재고 노출 결함 수정). 한계: 재고 이동은 공유 규칙 없음(관리자가 만든 이동은 센터장에게 안 보일 수 있음)      | —                      | 재고 행·공유 규칙·남은 위험                               |
| 재고 이동 단위       | 저장 전 Flow ProductTransfer_BeforeSave_FillUnit(빈 단위 → 출발 재고·제품 단위)                                                                                                                                                                                                             | 자동화 목록            | —                                                         |
| R6                   | 사용 부품 삭제 시 Apex 재고 되돌림 제거(표준이 한 번 되돌림, org 확인 14.5 → 13.5 → 14.5)                                                                                                                                                                                                   | —                      | —                                                         |
| 단가                 | 출장비 50,000, 부품·장비 모델 단가 현실화, 단가 원천 = ERP(초기 이관값을 제품 ErpUnitPrice__c에, IF-01 동기화는 다음 단계)                                                                                                                                                                  | 기준값                 | —                                                         |
| 탭                   | 앱 탭 리포트·대시보드: 상담원·센터장·관리자 권한 집합 "보임", 기사 프로필 "숨김"                                                                                                                                                                                                            | —                      | 탭 설정 행                                                |
| 문구                 | "최근" 제거 → 출동 이력·접수 이력, 마지막 접수일·90일 내 접수 수, 중복 경고 "종결되지 않은 접수 N건", 카드 "종결 전 접수"                                                                                                                                                                   | BR-11 문구             | —                                                         |
| 다음 단계 후보       | 출동 [수락]·[거절]·[도착] 버튼, 완료 후 N일 자동 종결, 재통화 기록, 부품 마스터 동기화(IF-01), 재고 이동 센터 공유, 출동 상태 순서 강제                                                                                                                                                     | 범위 밖                | —                                                         |

## 1. 사용자

| 이름     | Username                                 | 사용자 라이선스        | 프로필                                 | 역할           | 권한 집합                                                                                                                     | 권한 집합 라이선스                                                                                                              |
| -------- | ---------------------------------------- | ---------------------- | -------------------------------------- | -------------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| 김 병철  | epic.c3b435533985@orgfarm.salesforce.com | Salesforce             | HG 센터장                              | 경기남부센터장 | Experience_Profile_Manager, GenieAdmin, Developer_Edition, Case_Read, HG_CenterManager                                        | Data Cloud, Field Service Standard                                                                                              |
| 이 학민  | edwin.b28b9597ca64@agentforce.com        | Salesforce             | 시스템 관리자                          | 서비스운영팀장 | CopilotSalesforceAdmin, AgentforceServiceAgentBuilder, ServiceUserPsl, GenieAdmin, EinsteinGPTPromptTemplateManager, HG_Admin | Enhanced Chat User, Agentforce Service Agent Builder, Data Cloud, Agentforce (Default), Einstein Prompt Templates, Service User |
| 이 서연  | seoyeon.lee@hangyeol-as.dev              | Salesforce             | HG 콜센터 상담원                       | 콜센터 상담원  | HG_CallCenter                                                                                                                 | Field Service Standard                                                                                                          |
| 최 민호  | minho.choi@hangyeol-as.dev               | Salesforce             | HG 협력 기사                           | 경기남부 기사  | HG_Technician                                                                                                                 | Field Service Standard                                                                                                          |
| ERP 연동 | erp.integration@hangyeol-as.dev          | Salesforce Integration | Minimum Access - API Only Integrations | —              | HG_ErpIntegration, HG_ErpIntegrationData                                                                                      | Salesforce API Integration                                                                                                      |

- Manager: 최 민호 → 김 병철 (출동 승인 AP1의 승인자 = 제출자의 Manager)
- Flow User(사용자 체크): 김 병철 —, 이 학민 —, 이 서연 —, 최 민호 —, ERP 연동 —
- 그 밖의 활성 표준 사용자 2명(User Integration·User Security, Analytics Cloud 기본 사용자)은 업무 사용자 아님
- 권한 집합 이름이 `X00e…`인 것은 프로필 소유 권한 집합이 아닌 시스템 생성 권한 집합(라이선스 부여용) — 위 표에서 뺌. 이름별 의미는 **확인 필요**

## 2. 권한 집합

### 2-1. 개요·주요 시스템 권한

| 권한 집합             | 레이블             | 라이선스                   | Flow 실행 | API 사용 | 설정 보기 | 모든 데이터 보기 | 모든 데이터 수정 | 사용자 관리 | 리포트 실행 | 리포트 내보내기 | Lightning |
| --------------------- | ------------------ | -------------------------- | --------- | -------- | --------- | ---------------- | ---------------- | ----------- | ----------- | --------------- | --------- |
| HG_CallCenter         | HG 콜센터 상담원   | (없음)                     | O         | —        | —         | —                | —                | —           | O           | —               | —         |
| HG_CenterManager      | HG 센터장          | (없음)                     | O         | —        | —         | —                | —                | —           | O           | —               | —         |
| HG_Technician         | HG 협력 기사       | (없음)                     | —         | —        | —         | —                | —                | —           | —           | —               | —         |
| HG_Admin              | HG 관리자          | (없음)                     | —         | —        | —         | —                | —                | —           | —           | —               | —         |
| HG_ErpIntegration     | HG ERP 연동        | Salesforce Integration     | —         | —        | —         | —                | —                | —           | —           | —               | —         |
| HG_ErpIntegrationData | HG ERP 연동 데이터 | Salesforce API Integration | —         | —        | —         | —                | —                | —           | —           | —               | —         |

- 상담원·센터장·기사 3명의 프로필은 모두 `Minimum Access - Salesforce`(프로필 자체 Flow 실행 권한 없음, 조회 결과). 기사는 Flow 실행 권한 없이 개별 Flow 접근(flowAccesses)만으로 승인 요청 화면 Flow를 실행함(2026-10-16 확인, Flow 실행 권한은 추가하지 않기로 결정)

### 2-2. 오브젝트 권한

| 오브젝트               | HG_CallCenter | HG_CenterManager | HG_Technician | HG_Admin | HG_ErpIntegration | HG_ErpIntegrationData |
| ---------------------- | ------------- | ---------------- | ------------- | -------- | ----------------- | --------------------- |
| Account                | CRE           | RE               | —             | CREDVAMA | —                 | —                     |
| Asset                  | CRE           | RE               | —             | CREDVAMA | —                 | —                     |
| Case                   | CRE           | RE               | —             | CREDVAMA | —                 | —                     |
| CustomerSite__c        | CRE           | RE               | —             | CREDVAMA | —                 | —                     |
| ErpInboundLog__c       | —             | R                | —             | RVA      | —                 | —                     |
| Location               | R             | R                | R             | CREDVAMA | —                 | R                     |
| Product2               | R             | R                | R             | CRED     | —                 | R                     |
| ProductItem            | R             | R                | R             | CREDVAMA | —                 | R                     |
| ProductTransfer        | —             | R                | CRE           | CREDVAMA | —                 | —                     |
| UserExternalCredential | R             | R                | R             | R        | —                 | —                     |
| WorkOrder              | R             | RE               | RE            | CREDVAMA | —                 | —                     |

- C 생성 · R 읽기 · E 수정 · D 삭제 · VA 모든 레코드 보기 · MA 모든 레코드 수정 · — 없음
- `ProductConsumed`(사용 부품)는 위 표에 없음: org가 이 오브젝트의 권한 행을 저장하지 않음(배포해도 무시, 부모 출동 권한을 따르는 것으로 보임). 필드 권한(FLS)은 권한 집합에 있음 — CLAUDE.md 기록, 근거 문서 **확인 필요**

### 2-3. 클래스·Flow·탭·외부 자격 증명·사용자 지정 권한 접근

| 권한 집합             | Apex 클래스                                                                                                                                 | Flow(재정의 허용)                                              | 외부 자격 증명 보안 주체                                    | 사용자 지정 권한    | 앱                      |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- | ----------------------------------------------------------- | ------------------- | ----------------------- |
| HG_CallCenter         | AccountNewController, AddressSearchController, AssetDetailController, AssetSearchController, CallIntakeController, WorkOrderPartsController | —                                                              | HG_JusoApi / HG_JusoPrincipal                               | —                   | 한결공조 AS(HangyeolAS) |
| HG_CenterManager      | AccountNewController, AddressSearchController, AssetDetailController, AssetSearchController, WorkOrderPartsController                       | —                                                              | HG_JusoApi / HG_JusoPrincipal                               | —                   | 한결공조 AS(HangyeolAS) |
| HG_Technician         | WorkOrderPartsController                                                                                                                    | WorkOrder_Screen_RequestApproval, WorkOrder_Sub_SubmitApproval | HG_ErpMock / HG_ErpPrincipal                                | —                   | 한결공조 AS(HangyeolAS) |
| HG_Admin              | AccountNewController, AddressSearchController, AssetDetailController, AssetSearchController, CallIntakeController, WorkOrderPartsController | WorkOrder_Screen_RequestApproval, WorkOrder_Sub_SubmitApproval | HG_ErpMock / HG_ErpPrincipal, HG_JusoApi / HG_JusoPrincipal | HG_BypassValidation | 한결공조 AS(HangyeolAS) |
| HG_ErpIntegration     | ErpMovementResource                                                                                                                         | —                                                              | —                                                           | —                   | —                       |
| HG_ErpIntegrationData | —                                                                                                                                           | —                                                              | —                                                           | —                   | —                       |

| 권한 집합             | 탭 설정                                                                                                                                                                                                                                                                                                  |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| HG_CallCenter         | CustomerSite__c(기본 표시), HG_AssetSearch(기본 표시), standard-Account(기본 표시), standard-Asset(기본 표시), standard-Case(기본 표시), standard-Location(기본 표시), standard-Product2(기본 표시), standard-ProductItem(기본 표시), standard-WorkOrder(기본 표시)                                      |
| HG_CenterManager      | CustomerSite__c(기본 표시), HG_AssetSearch(기본 표시), standard-Account(기본 표시), standard-Asset(기본 표시), standard-Case(기본 표시), standard-Location(기본 표시), standard-Product2(기본 표시), standard-ProductItem(기본 표시), standard-ProductTransfer(기본 표시), standard-WorkOrder(기본 표시) |
| HG_Technician         | standard-Location(기본 표시), standard-Product2(기본 표시), standard-ProductItem(기본 표시), standard-ProductTransfer(기본 표시), standard-WorkOrder(기본 표시)                                                                                                                                          |
| HG_Admin              | CustomerSite__c(기본 표시), HG_AssetSearch(기본 표시), standard-Account(기본 표시), standard-Asset(기본 표시), standard-Case(기본 표시), standard-Location(기본 표시), standard-Product2(기본 표시), standard-ProductItem(기본 표시), standard-ProductTransfer(기본 표시), standard-WorkOrder(기본 표시) |
| HG_ErpIntegration     | —                                                                                                                                                                                                                                                                                                        |
| HG_ErpIntegrationData | —                                                                                                                                                                                                                                                                                                        |

## 3. 민감 필드 FLS · 읽기 전용 필드

| 필드                                  | HG_CallCenter | HG_CenterManager | HG_Technician | HG_Admin |
| ------------------------------------- | ------------- | ---------------- | ------------- | -------- |
| Account.AccountStatus__c              | R             | R/E              | —             | R/E      |
| Account.BillingContactEmail__c        | R/E           | R/E              | —             | R/E      |
| Account.BillingContactPhone__c        | R/E           | R/E              | —             | R/E      |
| Account.BusinessRegistrationNumber__c | R/E           | R/E              | —             | R/E      |
| Account.CustomerGrade__c              | R/E           | R/E              | —             | R/E      |
| Account.PaymentMethod__c              | R/E           | R/E              | —             | R/E      |
| Asset.LastCaseDate__c                 | R             | R                | —             | R/E      |
| Asset.RecentCaseCount__c              | R             | R                | —             | R        |
| Asset.RepeatFailure__c                | R             | R                | —             | R        |
| Asset.TotalCaseCount__c               | R             | R                | —             | R/E      |
| Asset.WarrantyBasis__c                | R/E           | R/E              | —             | R/E      |
| Case.CallerPhone__c                   | R/E           | R/E              | —             | R/E      |
| Case.RepeatFailure__c                 | R             | R                | —             | R/E      |
| Case.ServiceCenter__c                 | R             | R/E              | —             | R/E      |
| CustomerSite__c.OnSiteContactPhone__c | R/E           | R/E              | —             | R/E      |
| CustomerSite__c.ServiceCenter__c      | R             | R                | —             | R        |
| Product2.ErpUnitPrice__c              | R             | R                | R             | R/E      |
| ProductConsumed.AutoChargeType__c     | R             | R                | R             | R/E      |
| ProductConsumed.ChargeType__c         | R             | R                | R/E           | R/E      |
| ProductConsumed.ErpSyncStatus__c      | R             | R                | R             | R/E      |
| ProductConsumed.OverrideReason__c     | R             | R                | R/E           | R/E      |
| WorkOrder.ApprovalRejectReason__c     | R             | R/E              | R             | R/E      |
| WorkOrder.ApprovalRequestReason__c    | R             | R/E              | R/E           | R/E      |
| WorkOrder.ApprovalStatus__c           | R             | R                | R             | R        |
| WorkOrder.CustomerConsent__c          | R             | R/E              | R/E           | R/E      |
| WorkOrder.PaymentMethod__c            | R             | R/E              | R             | R/E      |
| WorkOrder.PaymentStatus__c            | R             | R/E              | R/E           | R/E      |

- "미수"는 별도 필드 없음: 고객사 거래 상태 `Account.AccountStatus__c`(Normal 정상 · PaymentWarning 미수 주의 · Suspended 거래 중지)로 관리
- 서비스센터: 사업장 `ServiceCenter__c`는 모든 권한 집합에서 읽기 전용, 저장 시 트리거(`CustomerSiteTrigger`)가 행정구역 코드로 지정. 접수 `ServiceCenter__c`는 저장 전 Flow가 장비→사업장에서 복사
- 시스템 계산 필드(Formula·Roll-Up·집계): `Asset.RecentCaseCount__c`·`RepeatFailure__c`·`TotalCaseCount__c`·`LastCaseDate__c`는 표처럼 읽기만. ERP 전송 상태 `ProductConsumed.ErpSyncStatus__c` 읽기만

## 4. 공유

### 4-1. 조직 기본값 (OWD)

| 오브젝트         | 내부               | 외부               |
| ---------------- | ------------------ | ------------------ |
| Asset            | 공개 읽기/쓰기     | 비공개             |
| CustomerSite__c  | 상위 항목에서 제어 | 상위 항목에서 제어 |
| WorkOrder        | 비공개             | 비공개             |
| Account          | 공개 읽기/쓰기     | 비공개             |
| Case             | 비공개             | 비공개             |
| Contact          | 공개 읽기/쓰기     | 비공개             |
| ProductTransfer  | 비공개             | 비공개             |
| ProductItem      | 비공개             | 비공개             |
| Location         | 비공개             | 비공개             |
| ProductConsumed  | 상위 항목에서 제어 | 상위 항목에서 제어 |
| ErpInboundLog__c | 공개 읽기 전용     | 비공개             |
| Product2         | 공개 읽기/쓰기     | 공개 읽기/쓰기     |

- V1.1 권한 매트릭스와 다름: **장비(Asset)는 "상위 항목에서 제어"가 아니라 공개 읽기/쓰기**(decision-log 보안 R3 유지 결정). 재고 이동(ProductTransfer)·ERP 기록·연락처는 V1.1 표에 없던 항목

### 4-2. 공유 규칙

| 오브젝트    | API 이름                              | 레이블                                                   | 유형        | 대상 레코드                                                                                                                | 공유 대상                          | 권한 |
| ----------- | ------------------------------------- | -------------------------------------------------------- | ----------- | -------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- | ---- |
| Case        | HG_CenterCases_CallCenter             | 센터 지정된 접수(Queue 소유 포함) → 콜센터 읽기/쓰기     | 조건 기준   | ServiceCenter__c equals 서울센터,경기북부센터,경기남부·인천센터,충청센터,영남센터,호남센터,강원센터,제주센터               | group:HG_CallCenter                | Edit |
| Case        | HG_AllCases_CallCenter                | 모든 접수 → 콜센터 읽기/쓰기                             | 소유자 기준 | 소유자 allInternalUsers:                                                                                                   | group:HG_CallCenter                | Edit |
| Location    | HG_Chungcheong_Locations_CM           | 충청 창고·차량 → 충청센터장 읽기                         | 조건 기준   | ServiceCenter__c equals 충청센터                                                                                           | role:HG_ChungcheongCenterManager   | Read |
| Location    | HG_GyeonggiSouth_Locations_CM         | 경기남부 창고·차량 → 경기남부센터장 읽기                 | 조건 기준   | ServiceCenter__c equals 경기남부·인천센터                                                                                  | role:HG_GyeonggiSouthCenterManager | Read |
| Location    | HG_GyeonggiSouth_Warehouse_Tech       | 경기남부 창고 → 경기남부 기사 읽기                       | 조건 기준   | LocationType equals 창고 AND ServiceCenter__c equals 경기남부·인천센터 (1 AND 2)                                           | role:HG_GyeonggiSouthTechnician    | Read |
| Location    | HG_Seoul_Locations_CM                 | 서울 창고·차량 → 서울센터장 읽기                         | 조건 기준   | ServiceCenter__c equals 서울센터                                                                                           | role:HG_SeoulCenterManager         | Read |
| Location    | HG_AllLocations_CallCenter            | 모든 창고·차량 → 콜센터 읽기                             | 소유자 기준 | 소유자 allInternalUsers:                                                                                                   | group:HG_CallCenter                | Read |
| ProductItem | HG_AllStock_CallCenter                | 모든 재고 → 콜센터 읽기                                  | 소유자 기준 | 소유자 allInternalUsers:                                                                                                   | group:HG_CallCenter                | Read |
| ProductItem | HG_Chungcheong_Stock_CM               | 충청 기사 차량 재고 → 충청센터장 읽기                    | 소유자 기준 | 소유자 role:HG_ChungcheongTechnician                                                                                       | role:HG_ChungcheongCenterManager   | Read |
| ProductItem | HG_GyeonggiSouth_Stock_CM             | 경기남부 기사 차량 재고 → 경기남부센터장 읽기            | 소유자 기준 | 소유자 role:HG_GyeonggiSouthTechnician                                                                                     | role:HG_GyeonggiSouthCenterManager | Read |
| ProductItem | HG_Seoul_Stock_CM                     | 서울 기사 차량 재고 → 서울센터장 읽기                    | 소유자 기준 | 소유자 role:HG_SeoulTechnician                                                                                             | role:HG_SeoulCenterManager         | Read |
| ProductItem | HG_GyeonggiSouth_Warehouse_Stock_Tech | 경기남부 창고 재고 → 경기남부 기사 읽기(2026-10-16 교체) | 조건 기준   | ServiceCenter__c = 경기남부·인천센터 AND WarehouseStock__c = 참 → role:HG_GyeonggiSouthTechnician 읽기(센터장은 역할 계층) |
| WorkOrder   | HG_Chungcheong_WorkOrders_CM          | 충청 출동 → 충청센터장 읽기/쓰기                         | 조건 기준   | ServiceCenter__c equals 충청센터                                                                                           | role:HG_ChungcheongCenterManager   | Edit |
| WorkOrder   | HG_GyeonggiSouth_WorkOrders_CM        | 경기남부 출동 → 경기남부센터장 읽기/쓰기                 | 조건 기준   | ServiceCenter__c equals 경기남부·인천센터                                                                                  | role:HG_GyeonggiSouthCenterManager | Edit |
| WorkOrder   | HG_Seoul_WorkOrders_CM                | 서울 출동 → 서울센터장 읽기/쓰기                         | 조건 기준   | ServiceCenter__c equals 서울센터                                                                                           | role:HG_SeoulCenterManager         | Edit |
| WorkOrder   | HG_AllWorkOrders_CallCenter           | 모든 출동 → 콜센터 읽기                                  | 소유자 기준 | 소유자 allInternalUsers:                                                                                                   | group:HG_CallCenter                | Read |

- 합계 16개(고객사·장비·재고 이동은 공유 규칙 없음). 공개 그룹: HG_CallCenter(구성원 1)

### 4-3. 역할 계층 (한결공조 역할만, 나머지는 Developer Edition 기본 역할)

| 역할           | 상위 역할      | 사용자  |
| -------------- | -------------- | ------- |
| 경기남부 기사  | 경기남부센터장 | 최 민호 |
| 경기남부센터장 | 서비스운영팀장 | 김 병철 |
| 서비스운영팀장 | (최상위)       | 이 학민 |
| 서울 기사      | 서울센터장     | —       |
| 서울센터장     | 서비스운영팀장 | —       |
| 충청 기사      | 충청센터장     | —       |
| 충청센터장     | 서비스운영팀장 | —       |
| 콜센터 상담원  | 서비스운영팀장 | 이 서연 |

- 경기북부·영남·호남·강원·제주 센터장 역할은 없음(시연 데이터가 없는 센터)

### 4-4. Queue · 할당 규칙

| Queue                 | 레이블                 | 구성원 수 | 오브젝트 |
| --------------------- | ---------------------- | --------- | -------- |
| HG_ChungcheongCases   | 충청센터 접수          | 1         | Case     |
| HG_GyeonggiNorthCases | 경기북부센터 접수      | 0         | Case     |
| HG_GyeonggiSouthCases | 경기남부·인천센터 접수 | 1         | Case     |
| HG_SeoulCases         | 서울센터 접수          | 1         | Case     |

- Queue 구성원은 역할(센터장 역할 등)로 지정된 것으로 보임, 구성원 상세 **확인 필요**. 경기북부 Queue는 구성원 0

할당 규칙 `HG_CaseByServiceCenter`(활성, 접수). 표준 `Standard` 규칙은 비활성(DE 기본)

| 순서 | 조건                                  | 배정 Queue            |
| ---- | ------------------------------------- | --------------------- |
| 1    | Case.ServiceCenter__c = GyeonggiSouth | HG_GyeonggiSouthCases |
| 2    | Case.ServiceCenter__c = Seoul         | HG_SeoulCases         |
| 3    | Case.ServiceCenter__c = Chungcheong   | HG_ChungcheongCases   |
| 4    | Case.ServiceCenter__c = GyeonggiNorth | HG_GyeonggiNorthCases |

- 규칙에 안 걸리면(영남·호남·강원·제주) 기본 사례 소유자(관리자)

## 5. 자동화

### 5-1. Flow (활성)

| API 이름                            | 레이블                                             | 유형      | 시작                | 설명(메타데이터)                                                                                                                                                                                                                                                                                                                                                                                             |
| ----------------------------------- | -------------------------------------------------- | --------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Account_AfterSave_RenameAssets      | 고객사 저장 후 - 이름 바뀌면 장비 이름 다시 만들기 | 자동 실행 | 고객사 저장 후      | 26-10-14 고객사 이름이 바뀐 경우만 그 고객사의 장비를 저장해 장비 저장 전 Flow가 이름을 다시 만들게 함. 여러 고객사를 한 번에 바꿔도 장비 저장은 묶어서 한 번(Flow 벌크 처리)                                                                                                                                                                                                                                |
| Asset_BeforeSave_NameAndSerialKey   | 장비 저장 전 - 이름·시리얼 키 자동                 | 자동 실행 | 장비 저장 전        | 26-10-14 장비 저장 전(생성·수정): 이름 = 모델/고객사/사업장/시리얼 끝자리(마지막 하이픈 뒤), 빈 칸은 건너뜀·모두 비면 "미지정 장비". 시리얼 키 = 일련번호(외부 ID·고유. 일련번호가 비면 시리얼 키를 일련번호로 채워 두 값을 같게). 생성, 또는 모델·고객사·사업장·일련번호·시리얼 키·이름이 바뀔 때 다시 만듦(장비 집계 저장 등에는 안 돎). 사업장·고객사 이름 변경 Flow는 이름을 "-"로 저장해 다시 만들게 함 |
| Case_AfterSave_UrgentAlert          | 긴급 접수 알림(저장 후)                            | 자동 실행 | 접수 저장 후        | 26-10-06 긴급 접수 생성 시 경기남부센터장에게 메일. 메일 실패는 관리자 알림만 하고 저장은 막지 않음                                                                                                                                                                                                                                                                                                          |
| Case_BeforeSave_FillFromAsset       | 접수 자동 채우기(저장 전)                          | 자동 실행 | 접수 저장 전        | 26-10-06 장비의 고객사·사업장·서비스센터를 접수에 복사하고 냉동창고·서버실이면 긴급으로 지정                                                                                                                                                                                                                                                                                                                 |
| Case_Screen_Cancel                  | 접수 취소                                          | 화면 Flow | 빠른 작업·하위 Flow | 26-10-06 종결 전 접수를 사유와 함께 취소. 종결·취소된 접수는 안내 후 종료                                                                                                                                                                                                                                                                                                                                    |
| CustomerSite_AfterSave_RenameAssets | 사업장 저장 후 - 이름 바뀌면 장비 이름 다시 만들기 | 자동 실행 | 사업장 저장 후      | 26-10-14 사업장 이름이 바뀐 경우만 그 사업장의 장비를 저장해 장비 저장 전 Flow가 이름을 다시 만들게 함. 여러 사업장을 한 번에 바꿔도 장비 저장은 묶어서 한 번(Flow 벌크 처리)                                                                                                                                                                                                                                |
| HG_Asset_ApplyCorrection            | 보증 기준일 정정 반영                              | 자동 실행 | 장비 저장 후        | 26-10-07 정정 승인된 설치일·근거·보증 기준을 장비에 반영하고 반영 완료로 표시                                                                                                                                                                                                                                                                                                                                |
| HG_WO_AfterReject                   | 출동 승인 반려 후 유상 전환                        | 자동 실행 | 출동 저장 후        | 26-10-07 출동 승인이 반려되면 예외 무상 부품을 유상으로 전환                                                                                                                                                                                                                                                                                                                                                 |
| WorkOrder_Screen_RequestApproval    | 출동 승인 요청                                     | 화면 Flow | 빠른 작업·하위 Flow | 26-10-15 출동 빠른 작업 "승인 요청"(기사, 데스크톱): 승인이 필요한 이유(예외 무상 건수·청구 합계 vs ServiceSetting ApprovalAmount)를 보여 주고 사유(필수)·고객 동의(기준 초과 시 필수)·센터장 메모를 받아 WorkOrder_Sub_SubmitApproval 호출. 도착 상태가 아니거나 승인이 필요 없으면 안내만                                                                                                                  |
| WorkOrder_Sub_SubmitApproval        | 출동 승인 요청 제출                                | 자동 실행 | 빠른 작업·하위 Flow | 26-10-15 출동 승인 요청: 사유·고객 동의 저장 → 승인 프로세스 HG_WorkOrderApproval 제출(메모 = 제출 코멘트). 진입 조건 판단은 승인 프로세스. 실패 시 저장 되돌림은 호출한 화면 Flow가 Roll Back Records로(자동 실행 Flow는 롤백 요소 불가). 화면 WorkOrder_Screen_RequestApproval이 호출, Apex 테스트 WorkOrderApprovalFlowTest                                                                               |

### 5-2. 트리거

| 트리거                 | 오브젝트        | 상태   | 처리(저장소 코드 기준)                                                                                                                                                                                                                       |
| ---------------------- | --------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CaseTrigger            | Case            | Active | CaseTriggerHandler: before insert 반복 고장 판정, after insert/update/delete/undelete 장비 집계(CaseStatsService)                                                                                                                            |
| ProductConsumedTrigger | ProductConsumed | Active | ProductConsumedTriggerHandler: before insert 차량 재고 초과 거부(VanStockService)·유무상 판정(WarrantyService), after insert ERP 전송 예약(IF-03), before delete 삭제 규칙, after delete 재고 되돌림(R6 제거 예정), after undelete 복원 거부 |
| ProductTransferTrigger | ProductTransfer | Active | ProductTransferTriggerHandler: 수령 시 ERP 전송 예약(IF-06)                                                                                                                                                                                  |
| CustomerSiteTrigger    | CustomerSite__c | Active | CustomerSiteTriggerHandler: before insert/update 서비스센터 자동 지정(ServiceCenterMapping__mdt)                                                                                                                                             |

- 스위치 `TriggerSetting__mdt`: Case 활성, ProductConsumed 활성, ProductTransfer 활성 (CustomerSite는 레코드 없음 = 활성)

### 5-3. Batch · 예약 작업

| 예약 이름                                  | Cron         | 상태    | 실행 클래스                                                                                |
| ------------------------------------------ | ------------ | ------- | ------------------------------------------------------------------------------------------ |
| HG 반복 고장 재계산                        | 0 0 2 * * ?  | WAITING | AssetRepeatFailureSchedulable → AssetRepeatFailureBatch (장비 최근 90일 접수 수·반복 고장) |
| HG ERP 재전송                              | 0 0 * * * ?  | WAITING | ErpRetrySchedulable → ErpRetryBatch (IF-03·06 실패·10분 넘은 대기 재전송, 상한 3)          |
| HG ERP 재고 동기화 :30 (매시, 푸시 안전망) | 0 30 * * * ? | WAITING | ErpStockSyncSchedulable → ErpStockSyncBatch (IF-02 가져오기)                               |

### 5-4. 승인 프로세스

| API 이름                                              | 오브젝트  | 상태   | 진입 조건                                                                                                                                                                                                        | 승인자                                             | 결과 처리                                                                                                                           |
| ----------------------------------------------------- | --------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| HG_WorkOrderApproval (AP1, 출동 승인)                 | WorkOrder | Active | 상태 Arrived + 승인 요청 사유 있음 + (예외 무상 포함 또는 청구 합계 > 500000) + (500000 이하 또는 고객 동의). 500000은 숫자로 고정(진입 조건에 $CustomMetadata 불가), 기준값 일치는 WorkOrderApprovalTest로 검증 | 제출자의 Manager(위임 허용). 제출자 = 소유자(기사) | 제출: PendingApproval·승인 대기 / 승인·반려·회수: Arrived + 승인 상태, 결과 메일. 반려 시 Flow HG_WO_AfterReject가 예외 무상 → 유상 |
| HG_WarrantyCorrectionApproval (AP2, 보증 기준일 정정) | Asset     | Active | 요청 설치일·요청 근거·정정 사유 입력 + 정정 상태가 Requested 아님                                                                                                                                                | 김병철 사용자 직접 지정(org별 Username)            | 필드 업데이트 4개(workflows/Asset), 승인 시 Flow HG_Asset_ApplyCorrection이 장비에 반영                                             |

### 5-5. 검증 규칙 (모두 활성)

| 오브젝트        | 이름                              | 설명(메타데이터)                                          |
| --------------- | --------------------------------- | --------------------------------------------------------- |
| Account         | BillingContactEmail_Required      | 청구 담당자 이메일 필수                                   |
| Account         | BusinessRegistrationNumber_Format | 개인 외 고객은 사업자번호 숫자 10자리 필수                |
| Asset           | Asset_AccountRequired             | 장비 고객사 필수(Asset 표준은 연락처만 있어도 저장되므로) |
| Asset           | Dealer_NoExtendedWarranty         | 대리점 장비 연장보증 불가                                 |
| Asset           | Dealer_WarrantyBasisMatch         | 대리점 장비 보증 기준 일치                                |
| Asset           | InstallDate_ChangeViaApproval     | 확정된 설치일·근거를 승인 없이 수정                       |
| Asset           | InstallDate_RequiredWithSource    | 근거 있으면 설치일 필수                                   |
| Asset           | Site_AccountMatch                 | 장비·사업장 고객사 일치                                   |
| Case            | Asset_Required                    | 장비 필수                                                 |
| Case            | CancelReason_Required             | 취소 사유 필수                                            |
| Case            | Closed_Lock                       | 종결·취소 후 수정 잠금                                    |
| CustomerSite__c | ServiceCenter_Required            | 서비스센터 필수                                           |
| ProductConsumed | OverrideReason_Required           | 판정 변경 사유 필수                                       |
| WorkOrder       | Case_Required                     | 접수 필수                                                 |
| WorkOrder       | Complete_RequiresArrival          | 도착 없이 완료 불가                                       |
| WorkOrder       | DeclineReason_Required            | 거절 사유 필수                                            |
| WorkOrder       | RejectReason_Required             | 반려 사유 없이 반려                                       |

- 합계 17개. 예외 사용자 지정 권한 HG_BypassValidation(HG_Admin만)을 쓰는 규칙은 Case.Closed_Lock(CLAUDE.md 기록, 수식 원문 **확인 필요**)

## 6. 요건서 BR-01~24 구현 상태

구분: **구현**(무엇으로) · **부분** · **표준 대체** · **범위 밖/미구현**. 근거는 org 메타데이터·저장소 파일

| BR    | 요약(V1.1)                                                                               | 상태                     | 근거                                                                                                                                                                                                                                         |
| ----- | ---------------------------------------------------------------------------------------- | ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BR-01 | 보증 시작일(직판 시운전일, 특약 = 설치일과 출하+6개월 중 빠른 날)                        | 구현                     | Asset.fmWarrantyStartDate__c Formula(WarrantyBasis__c 분기, ServiceSetting SpecialTermsShipmentMonths 6)                                                                                                                                     |
| BR-02 | 대리점: 확인서 있으면 설치일, 없으면 출하+3개월                                          | 구현                     | 같은 Formula(DealerStartGraceMonths 3) + VR Asset.Dealer_WarrantyBasisMatch                                                                                                                                                                  |
| BR-03 | 보증 기간 1년·압축기 3년·연장 2년(직판만)                                                | 구현                     | WarrantyPolicy__mdt 12/36/24, Formula fmBasic·fmCompressor·fmExtendedWarrantyEndDate__c, VR Asset.Dealer_NoExtendedWarranty                                                                                                                  |
| BR-04 | 만료일 자동 계산, 근거 없으면 "미확정"                                                   | 구현                     | Formula(수기 입력 필드 없음), fmWarrantyStatus__c에 "미확정" 값 있음                                                                                                                                                                         |
| BR-05 | 보증 기준일 정정: 근거 첨부·센터장 승인·이력 보존                                        | 부분                     | AP2 HG_WarrantyCorrectionApproval + VR InstallDate_ChangeViaApproval + Flow HG_Asset_ApplyCorrection, 필드 이력 추적(WarrantyBasis__c·CorrectionStatus__c·HasExtendedWarranty__c). 근거 파일 첨부 강제·InstallDate 이력 추적은 **확인 필요** |
| BR-06 | 유·무상 자동 판정 + 기사 최종 확정(변경 사유)                                            | 구현                     | ProductConsumedTrigger → WarrantyService(AutoChargeType__c), ChargeType__c 확정, VR ProductConsumed.OverrideReason_Required                                                                                                                  |
| BR-07 | 예외 무상: 센터장 승인·사유, 구분 집계                                                   | 부분                     | WorkOrder.ruExceptionFreeCount__c·HasExceptionFree__c → AP1 진입. 구분 집계 리포트는 **확인 필요**(리포트 3개 중 해당 없음으로 보임)                                                                                                         |
| BR-08 | 유상 50만 원 초과 시 고객 동의 + 센터장 승인                                             | 구현                     | AP1 진입 조건, 승인 요청 Screen Flow(동의 필수), ServiceSetting ApprovalAmount 500000                                                                                                                                                        |
| BR-09 | SLA 24h(제주 48h·계약 기준), 연기 건 제외                                                | 부분                     | 필드만: Case.SlaHours__c·fmSlaDueDate__c(생성일 + SlaHours)·fmSlaBreached__c·SlaExcluded__c, CustomerSite.ContractSlaHours__c, CMDT SlaHoursDefault 24·SlaHoursJeju 48. **SlaHours__c를 자동으로 채우는 Flow·Apex는 찾지 못함**              |
| BR-10 | SLA 마감 6시간 전 임박 경고                                                              | 미구현                   | CMDT SlaWarningHours 6만 있음, 사용하는 자동화 없음(저장소 검색)                                                                                                                                                                             |
| BR-11 | 냉동창고·서버실 자동 긴급, 열린 접수 중복 경고                                           | 구현(경고는 팝업 경로만) | Flow Case_BeforeSave_FillFromAsset(긴급) + Case_AfterSave_UrgentAlert(메일), 중복 경고 caseIntakeModal + IntakeContextService(2026-10-15). 표준 "새 접수" 화면에는 경고 없음                                                                 | **2026-10-16** 경고 문구 "이 장비에 종결되지 않은 접수가 N건 있습니다. 같은 고장이면 새로 만들지 말고 기존 접수를 열어 주세요."(완료 포함, 근거 요건서 As-Is 중복 접수 월 80건)                                      |
| BR-12 | 대형 냉동기 자격 기사, 재방문 직전 기사, 보조 기사                                       | 부분                     | 필드만: CustomerSite.PreferredTechnician__c, WorkOrder.AssistantTechnician__c. 자격·자동 배정 없음                                                                                                                                           |
| BR-13 | 기사 수락/거절(무응답 알림), 본인 출동만, 금액 비공개                                    | 부분                     | 출동 상태 Accepted·Declined + VR DeclineReason_Required, 출동 OWD 비공개, 기사에게 고객사·사업장·장비·접수 권한 없음. 무응답 알림 없음                                                                                                       |
| BR-14 | 90일 3회 반복 고장 표시, 보증 만료 30일 전 알림                                          | 부분                     | 반복 고장: CaseTriggerHandler·CaseStatsService + 매일 02:00 Batch(구현). 보증 만료 알림: CMDT WarrantyNoticeDays 30만 있고 자동화 없음                                                                                                       |
| BR-15 | 고객 구분 Record Type별 화면·필수, 사업자번호 필수·중복 불가, 개인 계열 사업장 자동 생성 | 부분                     | Record Type 4개, VR BusinessRegistrationNumber_Format·BillingContactEmail_Required, BusinessRegistrationNumber__c 외부 ID·고유. **사업장 자동 생성은 찾지 못함**                                                                             |
| BR-16 | 법인 월말 세금계산서, 개인사업자 현장 카드(미수)                                         | 부분                     | 필드: Account.PaymentMethod__c, WorkOrder.PaymentMethod__c·PaymentStatus__c, 거래 상태 AccountStatus__c. 정산 처리 없음                                                                                                                      |
| BR-17 | 기준값은 관리자가 개발 없이 변경                                                         | 구현(예외 1)             | ServiceSetting__mdt 11개·WarrantyPolicy__mdt 3개. 예외: AP1 진입 조건의 500000은 숫자 고정                                                                                                                                                   |
| BR-18 | 상태 순서 전이, 도착 없이 완료 불가, 열린 출동 있으면 접수 완료 불가, 종결 후 잠금       | 구현(순서 강제 제외)     | VR WorkOrder.Complete_RequiresArrival, Case.Closed_Lock, Case.CancelReason_Required + 화면 Flow Case_Screen_Cancel. 순서 강제·"열린 출동이 있으면 접수 완료 불가"는 찾지 못함                                                                | **2026-10-16**: 열린 출동 수·완료 출동 수(CaseWorkOrderStatsService) + VR Case.OpenWorkOrders_BlockClose(열린 출동 있으면 완료·종결 불가) + 처리 중 → 완료 자동, 완료 → 처리 중 재오픈. 출동 상태 순서 강제는 미구현 |
| BR-19 | 반려 시 도착 복귀(사유 필수), 예외 무상 → 유상                                           | 구현                     | AP1 반려 필드 업데이트(Arrived), VR WorkOrder.RejectReason_Required, Flow HG_WO_AfterReject                                                                                                                                                  |
| BR-20 | 열람 범위(상담원 전 센터, 센터장 자기 센터, 기사 본인, 팀장 전체)                        | 구현                     | 4절 OWD·공유 규칙·역할·Queue                                                                                                                                                                                                                 |
| BR-21 | ERP 동기화 부품·차량 재고에서 선택, 차감 후 ERP 전송(재시도·상태)                        | 구현                     | partAddForm·WorkOrderPartsController, VanStockService(초과 거부), IF-03·IF-06(Queueable + 재전송 Batch), IF-02 Push + Pull, ErpSyncStatus__c. IF-01 부품 마스터 동기화는 범위 밖(초기 이관)                                                  |
| BR-22 | 판매 경로별 보증 기준·근거 선택지 제한, 대리점 연장·특약 불가                            | 구현                     | WarrantyBasis__c 종속 picklist(valueSettings) + VR Dealer_NoExtendedWarranty·Dealer_WarrantyBasisMatch. 특약 입력 차단 VR은 **확인 필요**                                                                                                    |
| BR-23 | 고객사·사업장 화면에 장비 목록, 설치처 미확인 장비는 대리점 소속                         | 구현                     | 레이아웃 장비 관련 목록(2026-10-14), VR Asset_AccountRequired(오류 문구에 대리점 지정 안내)                                                                                                                                                  |
| BR-24 | 출동 일정 캘린더, 장비 QR(선택)                                                          | 범위 밖                  | 구현 없음. 장비 QR은 decision-log CTI 5에서 다음 단계 후보                                                                                                                                                                                   |

### 6-1. V1.1 이후 새로 생긴 규칙 (요건서에 없음)

| 규칙                                                                                                                   | 구현                                                       | 근거(decision-log)   |
| ---------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- | -------------------- |
| 사업장 서비스센터 완전 자동(누가 저장하든 행정구역 코드 → 센터), 주소 검색 없이 저장·손수정·매핑 없음·센터만 변경 거부 | CustomerSiteTrigger + ServiceCenterMapping__mdt 32건       | 도로명주소 9 (10/14) |
| 도로명주소 검색으로만 주소 입력(사업장·고객사)                                                                         | addressSearch·AddressSearchController(IF-07)               | 도로명주소 1·6       |
| 차량 재고보다 많이 쓰면 거부(정확히 남은 수량은 허용), 모든 입력 경로                                                  | partAddForm + 컨트롤러 + VanStockService(트리거)           | 보안 R1 (10/14)      |
| 사용 부품 삭제는 ERP 실패·거부 건만, 휴지통 복원 거부                                                                  | ProductConsumedTriggerHandler before delete·after undelete | ERP 6·19             |
| ERP 재고 원칙: Salesforce 재고를 ERP 값으로 덮어쓰지 않고 변동량만 반영, 이력 번호 중복 반영 금지                      | ErpStockSyncService·ErpMovementResource                    | ERP 4·14·21          |
| 장비 이름 = 모델/고객사/사업장/시리얼 끝자리, 시리얼 키 = 일련번호                                                     | Flow Asset_BeforeSave_NameAndSerialKey + Rename Flow 2개   | 장비 이름 1~3        |
| 전화 접수는 가상 착신 → 접수 작성 팝업, 자동 저장 없음, 발신 번호는 CallerPhone__c                                     | callSimulator·caseIntakeModal·CallerMatchService           | CTI 1~3              |
| 접수 제목 기본값 "{증상} · {사업장} · {시리얼}"                                                                        | caseIntakeModal + CallIntakeController                     | 개선 2               |
| 모델 없는 장비는 "모델 미지정" 표시                                                                                    | CallerMatchService·AssetSearchController·assetSummary      | 개선 4               |
| 기사의 승인 요청은 화면 Flow로(필요 이유 표시, 기준 초과 시 동의 필수)                                                 | WorkOrder_Screen_RequestApproval·Sub_SubmitApproval        | 개선 5               |
| 종결·취소 접수는 Apex도 갱신하지 않음                                                                                  | Case.Closed_Lock + 트리거 원칙                             | CLAUDE.md            |

## 7. 화면 목록 (요건서 SC-01~16 기준)

| 요건 SC | 화면                                          | 상태                        | 구현(LWC·Flow·표준)                                                                                                                                                                               | 저장소 화면 설계서 번호 |
| ------- | --------------------------------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| SC-01   | 통합 접수(검색·보증·이력·미수)                | 구현                        | 장비 검색 탭 assetSearch(AssetSearchController), 가상 착신 callSimulator → 접수 작성 팝업 caseIntakeModal ⊃ intakeContextCards(거래 상태 = 미수 표시), 장비 요약 assetSummaryModal ⊃ assetSummary | SC-01·07·08·09          |
| SC-02   | 고객사·사업장 등록(개인사업자 분기)           | 구현(사업장 자동 생성 없음) | 새로 만들기 재정의 accountNewOverride ⊃ accountNew, customerSiteNewOverride ⊃ customerSiteNew, addressSearch·addressEditAction                                                                    | SC-05·06                |
| SC-03   | 미등록 장비 등록(ERP 출하 조회)               | 표준 대체                   | 표준 장비 새로 만들기. ERP 출하 조회(IF-05)는 범위 밖                                                                                                                                             | —                       |
| SC-04   | 장비 상세(부품별 보증·근거·이력)              | 구현                        | HG_AssetRecordPage: assetDetail + assetRecentCases(AssetDetailController)                                                                                                                         | SC-04                   |
| SC-05   | 설치 정보 등록(확인서 대리 입력)              | 표준 대체                   | 표준 장비 편집(설치일·근거 필드) — 별도 화면 없음, **확인 필요**                                                                                                                                  | —                       |
| SC-06   | 보증 기준일 정정 요청·승인                    | 표준 대체                   | 장비 정정 요청 필드 + 표준 승인 요청(AP2) + Flow HG_Asset_ApplyCorrection                                                                                                                         | —                       |
| SC-07   | 배정 보드(SLA 순)                             | 범위 밖                     | 표준 Queue·목록 보기로 대신하는지 **확인 필요**                                                                                                                                                   | —                       |
| SC-08   | 내 출동 목록(수락/거절)                       | 표준 대체                   | 표준 출동 목록·상태 변경(모바일 범위 밖)                                                                                                                                                          | —                       |
| SC-09   | 출동 작업 입력(차량 재고 부품·판정·사진·서명) | 부분                        | HG_WorkOrderRecordPage: workOrderParts ⊃ partAddForm(WorkOrderPartsController). 사진·서명 없음, 데스크톱                                                                                          | SC-xx(D8 스케치)        |
| SC-10   | 승인(예외 무상·고액 유상)                     | 구현                        | 요청: 빠른 작업 "승인 요청" Screen Flow WorkOrder_Screen_RequestApproval / 승인: 표준 승인 화면(AP1)                                                                                              | SC-10                   |
| SC-11   | 월말 정산(청구·현장 결제·미수)                | 범위 밖                     | —                                                                                                                                                                                                 | —                       |
| SC-12   | 운영 대시보드                                 | 부분                        | 리포트 3(AssetsByWarrantyStatus·CasesByServiceCenter·UrgentCasesByServiceCenter) + 대시보드 ServiceOperationsOverview                                                                             | —                       |
| SC-13   | 기준값 관리                                   | 표준 대체                   | Custom Metadata 설정 화면(ServiceSetting·WarrantyPolicy·ServiceCenterMapping·TriggerSetting)                                                                                                      | —                       |
| SC-14   | 방문 일정 캘린더                              | 범위 밖                     | —                                                                                                                                                                                                 | —                       |
| SC-15   | 내 차량 재고                                  | 표준 대체                   | 표준 재고(ProductItem) 목록 — 화면 구성 **확인 필요**                                                                                                                                             | —                       |
| SC-16   | 장비 QR(선택)                                 | 범위 밖                     | 다음 단계 후보                                                                                                                                                                                    | —                       |

- 그 밖의 구현 화면: 접수 레코드 페이지 HG_CaseRecordPage(표준 구성 요소만), 유틸리티 바 HG_AS_UtilityBar, 접수 취소 화면 Flow Case_Screen_Cancel(빠른 작업 "접수 취소")

## 8. 기준값 (Custom Metadata 현재 값)

| 유형                | API 이름                   | 레이블                        | 값     |
| ------------------- | -------------------------- | ----------------------------- | ------ |
| ServiceSetting__mdt | ApprovalAmount             | 센터장 승인 기준 금액         | 500000 |
| ServiceSetting__mdt | DealerStartGraceMonths     | 대리점 미확인 시작 유예(개월) | 3      |
| ServiceSetting__mdt | ErpMaxRetry                | ERP 재전송 최대 횟수          | 3      |
| ServiceSetting__mdt | RepeatFailureCount         | 반복 고장 횟수                | 3      |
| ServiceSetting__mdt | RepeatFailureDays          | 반복 고장 기간(일)            | 90     |
| ServiceSetting__mdt | SlaHoursDefault            | SLA 기본 시간                 | 24     |
| ServiceSetting__mdt | SlaHoursJeju               | SLA 제주 시간                 | 48     |
| ServiceSetting__mdt | SlaWarningHours            | SLA 임박 경고(시간)           | 6      |
| ServiceSetting__mdt | SpecialTermsShipmentMonths | 계약 특약 출하 후 상한(개월)  | 6      |
| ServiceSetting__mdt | VisitFee                   | 출장비                        | 50000  | (2026-10-16 30000 → 50000, decision-log 18) |
| ServiceSetting__mdt | WarrantyNoticeDays         | 보증 만료 안내(일)            | 30     |
| WarrantyPolicy__mdt | Compressor                 | 압축기 보증                   | 36개월 |
| WarrantyPolicy__mdt | Extended                   | 연장보증                      | 24개월 |
| WarrantyPolicy__mdt | General                    | 기본 보증                     | 12개월 |

- ServiceCenterMapping__mdt 32건(시군구 5자리·시도 2자리 → 서비스센터), TriggerSetting__mdt 3건
- V1.1 요건서 기준값과 같음. V1.1에 없던 값: ErpMaxRetry 3, RepeatFailureCount·Days, WarrantyNoticeDays(요건 BR-14에는 있음)

## 9. 인터페이스 요약 (산출물 `docs/산출물/06_한결공조_AS관리_인터페이스_정의서_V1.0.xlsx`)

| IF      | 이름               | 방향                  | 방식                                                                 | 주기                       | 상태               |
| ------- | ------------------ | --------------------- | -------------------------------------------------------------------- | -------------------------- | ------------------ |
| IF-01   | 부품 마스터 동기화 | ERP → SFDC            | 배치                                                                 | 일                         | 범위 밖(초기 이관) |
| IF-02-P | 재고 변동 푸시     | ERP → SFDC            | Apex REST ErpMovementResource, OAuth Client Credentials(연동 사용자) | 입고·조정 시               | 구현               |
| IF-02-R | 재고 변동 가져오기 | ERP → SFDC            | REST GET callout:HG_ErpMock, Batch + Schedulable                     | 매시 30분                  | 구현(안전망)       |
| IF-03   | 사용 부품 차감     | SFDC → ERP            | REST POST, Queueable + 재전송 Batch                                  | 저장 시 · 매시 정각 재전송 | 구현               |
| IF-04   | 창고 재고 조회     | SFDC → ERP            | REST GET                                                             | 조회 시                    | 범위 밖            |
| IF-05   | 출하 조회          | SFDC → ERP            | —                                                                    | —                          | 범위 밖            |
| IF-06   | 재고 이동          | SFDC → ERP            | REST POST, Queueable + 재전송 Batch                                  | 수령 시 · 매시 정각 재전송 | 구현               |
| IF-07   | 도로명주소 검색    | SFDC → 행정안전부 API | REST POST(form) → JSON, callout:HG_JusoApi                           | 요청 시                    | 구현               |

## 10. 요건·권한에 영향 준 결정 (decision-log 요약)

| 섹션 · 번호                  | 결정 한 줄                                                                                                                        |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| 승인 버튼 미표시 1~4 (10/16) | 원인은 피드 배치(빠른 작업이 Chatter 게시자 영역), 출동 페이지 강조 표시 패널을 동적 작업으로. 기사에게 Flow 실행 권한 추가 안 함 |
| ERP 연동(10/13) 1~5          | Mock ERP(Cloudflare), 저장 즉시 Queueable 전송, 일시 실패만 재전송(상한 3), Salesforce 재고를 ERP 값으로 덮어쓰지 않음            |
| ERP 6 · 19                   | 사용 부품 삭제는 실패·ERP 거부만, 삭제 시 재고 되돌림은 표준에 맡김(R6 코드 제거 대기)                                            |
| ERP 7 · 10                   | 재고 이동 권한: 기사 C/R/E(삭제 없음)·센터장 R, 창고는 공유 규칙으로 기사 읽기                                                    |
| ERP 9                        | IF-01은 초기 이관으로 대신(범위 밖)                                                                                               |
| ERP 21~23                    | IF-02 Push + Pull, 연동 사용자 권한 2개로 분리(클래스 실행 / 재고·위치·제품 읽기), 입구 클래스 without sharing + 입력 검증        |
| 도로명주소 1~9               | 주소 검색 API, 서비스센터 자동 매핑 → 완전 자동(트리거), 서비스센터 필드는 전원 읽기 전용                                         |
| 표준 오브젝트 화면 이름 1~5  | Account 고객사·Asset 장비·Case 접수·WorkOrder 출동 등 한국어 이름, Product2 "제품"·Location "위치"                                |
| 새로 만들기 재정의 1~2       | 고객사·사업장 등록은 주소 검색 포함 재정의 화면(데스크톱만)                                                                       |
| 장비 이름 1~7                | 장비 이름 자동 생성, 고객사·사업장 화면에 장비 관련 목록(BR-23)                                                                   |
| 보안 점검 R1 · R3            | 재고 초과 거부를 트리거에도, 고객사·장비 공개 읽기/쓰기 유지                                                                      |
| 보안 점검 3                  | 대리점 고객사 레이아웃 = HG 고객사 Layout(같은 Minimum Access 프로필 공유)                                                        |
| 승인 프로세스 1 · 2          | AP1 진입 조건 500000 숫자 + 테스트로 일치 검증, AP2 승인자는 사용자 직접 지정(환경별 변경 필요)                                   |
| CTI 1~6                      | 가상 착신 시뮬레이터, 발신 번호 = CallerPhone__c, 기사에게는 안내만, 장비 요약 팝업                                               |
| 개선 1~5 (10/15)             | 접수 팝업 카드·제목 형식·중복 경고(BR-11)·모델 미지정·승인 요청 Screen Flow(기사는 Flow 접근만, RunFlow 없음)                     |

## 11. 확인 필요 목록

- 권한 집합 `X00e…`(시스템 생성) 각각의 의미
- Queue 구성원(역할 기준인지)
- ProductConsumed 오브젝트 권한이 org에 저장되지 않는 근거
- BR-05 근거 파일 첨부 강제·설치일 이력 추적
- BR-07 예외 무상 구분 집계 리포트
- BR-22 대리점 특약 입력 차단 규칙
- SC-05·07·15 표준 화면 구성
- Case.Closed_Lock 수식에서 HG_BypassValidation 사용 여부(수식 원문)
