# 배포 절차 — 한결공조 AS 관리 시스템

- 작성: Edwin · 2026-10-16 · 기준 브랜치 `feature/onboarding-d8`, 개발 org `devorg`(Developer Edition, Field Service)
- 가정: 개발은 dev org에서 했지만 **샌드박스(Full 또는 Partial Copy) → 운영** 순서로 배포한다. 샌드박스·운영 org 별칭은 `hg-uat`, `hg-prod`로 가정
- 함께 보는 산출물: `docs/산출물/19_…_소스이관목록_V1.0.xlsx`(구성 요소 목록), `docs/산출물/11_…_CutOver사전점검리스트_V1.0.xlsx`(작업 일정·스모크 테스트), `docs/handoff/v2_facts.md`(권한·공유·자동화 현황)
- 키·비밀 값은 이 문서·Git에 쓰지 않는다. 보관 위치만 적는다

## 1. 배포 전 준비

### 1-1. 저장소에 없는 구성 요소 (먼저 retrieve해서 저장소에 넣는다)

dev org에는 있지만 저장소(`force-app`)에 없는 것. 이대로 배포하면 운영에 빠지므로, 배포 브랜치에서 아래를 retrieve → 커밋 → 다시 비교한다.

| 유형                      | 구성 요소                                                                                                                                            | 비고                                                                           |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| GlobalValueSet            | `ServiceCenter`                                                                                                                                      | 사업장·접수·출동·위치의 서비스센터 선택 목록. **오브젝트 필드보다 먼저** 필요  |
| CustomObject(정의)        | `ServiceSetting__mdt`, `WarrantyPolicy__mdt`, 표준 오브젝트 정의(Asset·Case·WorkOrder·Location·Product2·ProductItem·ProductConsumed·ProductTransfer) | 저장소에는 필드·레코드만 있음. 조직 기본 공유(OWD)도 오브젝트 정의에 들어 있음 |
| RecordType                | `Account.Corporation`·`SoleProprietor`·`Individual`·`Dealer`                                                                                         |                                                                                |
| ValidationRule            | 17개 중 16개(`Asset_AccountRequired`만 저장소에 있음)                                                                                                | 목록은 v2_facts.md 5-5                                                         |
| Flow                      | `HG_Asset_ApplyCorrection`, `HG_WO_AfterReject`                                                                                                      | 승인 프로세스가 사용                                                           |
| SharingRules              | `Case`, `WorkOrder`                                                                                                                                  | Location·ProductItem은 저장소에 있음                                           |
| Queue                     | `HG_SeoulCases`, `HG_ChungcheongCases`                                                                                                               | 경기남부·경기북부는 저장소에 있음                                              |
| Role                      | `HG_ServiceOpsManager`, `HG_CallCenterAgent`, 센터장·기사 역할 6개                                                                                   |                                                                                |
| Group                     | `HG_CallCenter`(공개 그룹)                                                                                                                           | 공유 규칙 대상                                                                 |
| CustomPermission          | `HG_BypassValidation`                                                                                                                                | 권한 집합 HG_Admin이 참조                                                      |
| ExternalClientApplication | `HG_ERP_Mock`                                                                                                                                        | 소비자 키·비밀은 메타데이터에 없음 → 환경마다 새로 발급                        |

```powershell
# 예: 누락분 retrieve (dev org)
sf project retrieve start -o devorg -m GlobalValueSet:ServiceCenter -m CustomObject:ServiceSetting__mdt -m CustomObject:WarrantyPolicy__mdt `
  -m "RecordType:Account.Corporation" -m "RecordType:Account.SoleProprietor" -m "RecordType:Account.Individual" -m "RecordType:Account.Dealer" `
  -m Flow:HG_Asset_ApplyCorrection -m Flow:HG_WO_AfterReject -m SharingRules:Case -m SharingRules:WorkOrder `
  -m Queue:HG_SeoulCases -m Queue:HG_ChungcheongCases -m Role -m Group:HG_CallCenter -m CustomPermission:HG_BypassValidation
# 검증 규칙은 오브젝트별로 (예: -m "ValidationRule:Case.Closed_Lock")
```

- 프로필은 전체 retrieve로 덮어쓰지 않는다(저장소에는 필요한 부분만 있는 최소 파일: 고객사 레코드 유형 4개·제품 레이아웃 할당, 새 프로필은 권리 읽기 해제·설명). 프로필 6개 = Admin · Minimum Access - Salesforce · Minimum Access - API Only Integrations · HG 콜센터 상담원 · HG 센터장 · HG 협력 기사(2026-10-16)
- **프로필별 제품(Product2) 페이지 레이아웃 할당 필요**: 할당이 없으면 제품 화면이 오류. 최소 파일에 `Product2-Product Layout`이 들어 있으므로 프로필을 배포하면 함께 맞춰짐(새 프로필을 화면에서 만들면 직접 확인)
- **사용자 프로필 되돌리기**(역할별 홈 문제 등): 사용자의 프로필을 `Minimum Access - Salesforce`로 바꾸면 그 전과 같음(권한은 모두 권한 집합, 레이아웃 할당 동일). 예: `sf data update record -s User -w "Username='…'" -v "ProfileId=<Minimum Access Id>"`. 차이는 역할별 홈이 앱 기본 홈(관리자용)으로 바뀌는 것과 권리 읽기가 다시 생기는 것뿐
- retrieve 후 `npx prettier --write "force-app/**/*.{cls,trigger}"`(줄바꿈 정리), 저장소 = org 비교(내용 비교 스크립트, decision-log CTI 합치기 참고)

**2026-10-16 실행 결과 (커밋 d2206cc)**: 위 표 전부 받음. 오브젝트는 정의 단위로 16개(Account·Asset·Case·WorkOrder·Location·Product2·ProductItem·ProductConsumed·ProductTransfer·CustomerSite__c·ErpInboundLog__c·ErpSyncState__c·ServiceSetting__mdt·WarrantyPolicy__mdt·ServiceCenterMapping__mdt·TriggerSetting__mdt)를 받아 OWD·레코드 유형·검증 규칙 17·목록 보기가 함께 들어옴. 역할은 HG\_ 8개만, 외부 클라이언트 앱은 정의(`HG_ERP_Mock.eca-meta.xml`)만이고 OAuth 설정·키는 받지 않음(키 없음 확인). 기존 파일 186개는 retrieve가 요소 순서·줄 포맷을 바꾼 것(내용 변화 없음)

### 1-1-1. 저장소만으로 check-only 배포 (2026-10-16, 대상 dev org)

| 범위                                   | 명령                                                                                          | 결과                                                                                                                                                          |
| -------------------------------------- | --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 저장소 전체(`force-app`)               | `sf project deploy validate --source-dir force-app --test-level RunLocalTests`                | **실패**: Apex 클래스 54개 모두 "보류 중이거나 진행 중인 작업이 있습니다"(dev org의 예약 작업 3개가 참조하는 클래스와 그 의존 클래스). 메타데이터 오류는 아님 |
| Apex·트리거 제외 전체                  | `sf project deploy start --dry-run -d <classes·triggers 외 폴더 전부> --test-level NoTestRun` | **성공: 843 / 843**, 오류 0                                                                                                                                   |
| 저장소 전체(`force-app`), 예약 해제 후 | 예약 3개 `System.abortJob` → 같은 validate → 스크립트로 재예약                                | **성공: 구성 요소 901 / 901, 테스트 193 / 193 통과**, 커버리지 경고 없음(Job 0Afaj00000nv6Z8CAI). 재예약 후 예약 3개 WAITING 확인                             |

- 결론(2026-10-16): **저장소만으로 dev org에 check-only 배포 성공**(901 구성 요소, Apex 포함). 예약 작업이 있는 org에서는 validate도 막히므로 1-3의 예약 해제를 validate 전에 하고, 끝나면 바로 재예약한다
- 재예약 주의: `d7_erp_inbound_schedule.apex`의 APPLY를 바꾼 사본을 PowerShell `Set-Content -Encoding UTF8`로 만들면 BOM이 붙어 익명 Apex가 실행되지 않고 조용히 넘어감 → 사본은 BOM 없는 UTF-8로 저장하거나 원본 APPLY 값을 바꿔 실행하고, 재예약 후 `CronTrigger` 3건을 반드시 조회
- `deploy validate`는 `NoTestRun`을 받지 않음(RunLocalTests 등 필수). 테스트 없이 확인할 때는 `deploy start --dry-run --test-level NoTestRun`(운영에서는 불가)

### 1-2. 품질 기준 확인

| 항목              | 기준                    | 2026-10-15 결과                               |
| ----------------- | ----------------------- | --------------------------------------------- |
| 전체 로컬 테스트  | 모두 통과               | 214건(메서드 193 + @TestSetup 21) Pass        |
| org 커버리지      | 75% 이상(회사 기준 85%) | 96%                                           |
| 클래스별 커버리지 | 낮은 클래스 확인        | 최저 CallIntakeController 86%(예외 처리 블록) |
| 접근 모드         | 조회·DML 모드 명시      | 모드 없는 문장 0(보안 결과표)                 |

### 1-3. 배포를 막는 예약 작업

예약 작업이 참조하는 클래스(와 그 의존 클래스)는 "보류 중인 작업" 오류로 배포가 거부된다. **check-only(validate)도 같다**. 클래스 전체를 한 번에 배포하면 예약과 무관한 클래스까지 모두 거부된다(2026-10-16 dev org 확인, 1-1-1). 대상 org에 이미 예약이 있으면 validate 전에 해제하고 배포 후 다시 예약한다. ("Apex 작업이 있어도 배포 허용" 설정은 켜지 않는다)

| 예약 이름                                  | 실행 클래스                                                    | 막히는 배포 대상                                        | 다시 예약                                                 |
| ------------------------------------------ | -------------------------------------------------------------- | ------------------------------------------------------- | --------------------------------------------------------- |
| HG 반복 고장 재계산 (매일 02:00)           | AssetRepeatFailureSchedulable → AssetRepeatFailureBatch        | Schedulable·Batch·CaseStatsService·WarrantyService 묶음 | `scripts/apex/d6_schedule.apex`                           |
| HG ERP 재전송 (매시 정각)                  | ErpRetrySchedulable(Batch는 Type.forName으로 생성 → 막힘 회피) | ErpRetrySchedulable                                     | `scripts/apex/d7_erp_retry_schedule.apex`                 |
| HG ERP 재고 동기화 :30 (매시, 푸시 안전망) | ErpStockSyncSchedulable                                        | ErpStockSyncSchedulable                                 | `scripts/apex/d7_erp_inbound_schedule.apex`(APPLY = true) |

```apex
// 해제 (익명 Apex) — 이름을 확인하고 실행
for (CronTrigger ct : [SELECT Id, CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name LIKE 'HG %']) {
  System.abortJob(ct.Id);
}
```

## 2. 배포 순서 (의존 관계)

SFDX는 한 번의 배포 안에서 의존 순서를 맞춰 주지만, **환경 설정이 필요한 것·데이터가 필요한 것** 때문에 아래 단계로 나눈다.

| 단계 | 내용            | 구성 요소                                                                                                                                                                                                                                                       | 의존 이유                                                                       |
| ---- | --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 0    | 조직 설정(수동) | Field Service 활성화, 권한 집합 라이선스 Field Service Standard·Salesforce API Integration 확보, 탭 및 레이블 이름 바꾸기(objectTranslations로 배포 가능), 기본 사례 소유자                                                                                     | Field Service 오브젝트(WorkOrder·ProductConsumed·Location 등) 필드 배포 전 필요 |
| 1    | 기반 메타데이터 | GlobalValueSet, CustomObject·CustomField(사용자 지정 메타데이터 유형 포함), RecordType, CustomMetadata 레코드(ServiceSetting 11·WarrantyPolicy 3·ServiceCenterMapping 32·TriggerSetting 3), Custom Setting ErpSyncState__c, CustomLabels(173), CustomPermission | 필드·라벨·기준값을 Apex·Flow가 참조                                             |
| 2    | 보안 기반       | Role, Group, Queue, NamedCredential·ExternalCredential(값 없이), 메일 템플릿·알림 유형                                                                                                                                                                          | 공유 규칙·할당 규칙·콜아웃이 참조                                               |
| 3    | 코드            | Apex 클래스 54(테스트 25 포함), 트리거 4, LWC 15, Aura 2                                                                                                                                                                                                        | 1~2단계 참조                                                                    |
| 4    | 자동화          | Flow 10, 빠른 작업 4, Workflow(필드 업데이트·메일 알림), 승인 프로세스 2, 할당 규칙                                                                                                                                                                             | 승인 프로세스가 Flow·Workflow·메일 템플릿 참조                                  |
| 5    | 화면            | 레이아웃 9, FlexiPage 5(유틸리티 바 포함), 앱 HangyeolAS, 탭, 목록 보기, 리포트·대시보드, objectTranslations                                                                                                                                                    | 앱이 FlexiPage·탭 참조                                                          |
| 6    | 권한·공유       | 권한 집합 6, 프로필(최소 파일), 공유 규칙                                                                                                                                                                                                                       | 클래스·Flow·탭·외부 자격 증명 보안 주체를 참조하므로 마지막                     |

### 2-1. SFDX 명령 (샌드박스 → 운영 동일)

```powershell
# 0) 대상 org 로그인
sf org login web -a hg-uat -r https://test.salesforce.com      # 샌드박스
sf org login web -a hg-prod -r https://login.salesforce.com    # 운영

# 1) 배포 매니페스트 생성 (저장소 전체 기준, 1-1 retrieve 반영 후)
sf project generate manifest --source-dir force-app --name deploy_package --output-dir manifest

# 2) 검증만 (변경 없음, 테스트 실행) — 운영은 RunLocalTests 필수
sf project deploy validate -o hg-uat --manifest manifest/deploy_package.xml --test-level RunLocalTests -w 120
sf project deploy validate -o hg-prod --manifest manifest/deploy_package.xml --test-level RunLocalTests -w 120

# 3) 검증 성공한 Job으로 빠른 배포 (10일 안, 그 사이 대상 org 변경 금지)
sf project deploy quick -o hg-prod --job-id <검증 Job Id> -w 60

# 단계별로 나눌 때 (예: 1단계만)
sf project deploy start -o hg-uat -m GlobalValueSet:ServiceCenter -m "CustomObject:ServiceSetting__mdt" --test-level NoTestRun -w 60
```

- 테스트 옵션: 운영은 `RunLocalTests`(관리 패키지 제외 전체 로컬 테스트). 샌드박스 중간 단계는 `NoTestRun` 가능하지만 마지막 검증은 반드시 `RunLocalTests`
- 배포는 폴더(`-d objects`) 단위가 아니라 매니페스트 또는 `-m 이름`으로(오브젝트 정의 일부만 있는 저장소 구조 때문)
- 라벨 파일을 배포해도 저장소에서 지운 라벨은 대상 org에서 지워지지 않음 → 지울 라벨은 destructiveChanges로

## 3. 배포 후 수동 설정 (환경별)

| No  | 항목                    | 설정 위치                                                                                                                                                                                     | 값·보관 위치                                                                                                   | 확인                                                   |
| --- | ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| 1   | 도로명주소 승인키       | 설정 → 외부 자격 증명 → HG_JusoApi → 보안 주체 HG_JusoPrincipal → 인증 매개변수 ConfmKey                                                                                                      | 운영 승인키(행정안전부 발급). 값은 설정 화면에만                                                               | 사업장 "주소 검색" 결과 표시                           |
| 2   | ERP API 키              | 외부 자격 증명 HG_ErpMock → 보안 주체 HG_ErpPrincipal → ApiKey                                                                                                                                | 환경별 ERP 키. 설정 화면에만                                                                                   | 사용 부품 저장 → ERP 전송 상태 Synced                  |
| 3   | ERP 주소                | 설정 → 이름이 지정된 자격 증명 → HG_ErpMock URL                                                                                                                                               | 환경별 ERP 게이트웨이 주소(코드 변경 없음)                                                                     | —                                                      |
| 4   | 연동 사용자             | 사용자 생성: 라이선스 Salesforce Integration, 프로필 Minimum Access - API Only Integrations, 권한 집합 라이선스 Salesforce API Integration, 권한 집합 HG_ErpIntegration·HG_ErpIntegrationData | 사용자 이름은 환경별                                                                                           | 할당 조회                                              |
| 5   | 외부 클라이언트 앱      | 외부 클라이언트 앱 "HG ERP Mock"(OAuth Client Credentials, Run As = 연동 사용자)                                                                                                              | 소비자 키·비밀은 ERP 쪽 비밀 저장소(현재 Cloudflare secret SF_CLIENT_ID·SF_CLIENT_SECRET, cmd에서 대화형 입력) | ERP `/health` push: configured, 입고 1건 "즉시 반영됨" |
| 6   | AP2 승인자              | 승인 프로세스 HG_WarrantyCorrectionApproval의 승인자(사용자 직접 지정)                                                                                                                        | 환경별 센터장 Username으로 메타데이터 수정 후 배포                                                             | 보증 기준일 정정 요청 → 승인자 확인                    |
| 7   | 사용자·역할·Manager     | 상담원·센터장·기사 생성, 역할 지정, **기사 Manager = 센터장**(AP1 승인자)                                                                                                                     | —                                                                                                              | v2_facts.md 1절                                        |
| 8   | 권한 집합·라이선스 할당 | HG_CallCenter·HG_CenterManager·HG_Technician·HG_Admin + Field Service Standard                                                                                                                | —                                                                                                              | 할당 조회                                              |
| 9   | 공개 그룹·Queue 구성원  | HG_CallCenter(상담원), 센터별 Queue 구성원(센터장 역할 등)                                                                                                                                    | —                                                                                                              | 접수 공유·배정 확인                                    |
| 10  | 출동 [승인 요청] 버튼   | 출동 레코드 페이지 HG_WorkOrderRecordPage 강조 표시 패널 = 동적 작업(메타데이터로 배포됨). 기사에게 Flow 실행 권한은 주지 않음(개별 Flow 접근만)                                              | —                                                                                                              | 기사 화면 강조 표시 패널에 [승인 요청]                 |
| 11  | 할당 규칙 활성          | HG_CaseByServiceCenter 활성, 기본 사례 소유자                                                                                                                                                 | —                                                                                                              | 접수 저장 → 센터 Queue                                 |
| 12  | 예약 작업               | 1-3 표의 스크립트로 3개 다시 예약                                                                                                                                                             | —                                                                                                              | CronTrigger 3건 WAITING                                |
| 13  | ERP 기준 이력 번호      | `scripts/apex/d7_erp_inbound_baseline.apex`로 가져오기 기준점 설정(운영 시작 1회)                                                                                                             | Custom Setting ErpSyncState__c                                                                                 | 미리 보기 `d7_erp_inbound_preview.apex`                |
| 14  | 앱·페이지 지정          | 앱 HangyeolAS 사용자 프로필 지정, 레코드 페이지(장비·접수·출동) 앱 기본값, 유틸리티 바                                                                                                        | 메타데이터로 배포되나 활성 상태 확인                                                                           | 각 페이지 열기                                         |

## 4. 데이터 이관·검증

- **과거 이력 데이터 생성일(감사 필드)**: 이관·이력 데이터의 생성일을 과거로 넣는 절차(2026-10-16 한빛물류 이력 `scripts/apex/d9_hanbit_history.apex`에 사용)
  1. 설정 SecuritySettings `enableAuditFieldsInactiveOwner` = true (설정 → 사용자 인터페이스 "레코드 생성 시 감사 필드 설정 … 사용자 권한 사용"). 사용자 권한은 이 설정을 켠 뒤에야 배포 가능(꺼져 있으면 "Unknown user permission")
  2. 실행 사용자에게 사용자 권한 "레코드 생성 시 감사 필드 설정"(CreateAuditFields)을 임시 권한 집합으로 할당
  3. 생성일은 insert 때만 지정. 스크립트는 `put('CreatedDate', …)`로 동적 지정(권한이 없을 때도 미리 보기가 컴파일되도록)
  4. 끝나면 권한 할당 해제 → 임시 권한 집합 삭제 → 설정 false → retrieve로 false·권한 집합 0건 확인
- **이력 사용 부품은 ERP 상태를 비울 것**: ERP 상태 선택 목록 기본값이 대기(Pending)라, 트리거를 우회해 넣어도 그대로 두면 매시 재전송이 ERP로 보냄 → 저장 직후 비움("연동 전 기존 데이터", decision-log ERP 13). 재고 차감을 피하려면 사용 부품을 재고 대신 가격표 항목에 연결(출동에 같은 가격표 지정)
- **재고 공유 규칙 교체 순서**(2026-10-16): 새 조건 기준 규칙을 먼저 배포 → 성공 확인 후 옛 소유자 기준 규칙 삭제(destructiveChanges, SharingOwnerRule ProductItem.HG_Warehouse_Stock_GS_Tech). 순서를 거꾸로 하면 그 사이 기사가 창고 재고를 못 봄(dev에서 약 1분 발생). 체크박스 조건 값은 **배포 사용자 언어로 저장**("참"/"True") — 저장소 값은 "참"(한국어 사용자), 영어 사용자로 배포하면 "True"로 바꿔야 함. 재고 서비스센터는 `scripts/apex/d9_productitem_center_fill.apex`로 채움(Flow가 위치에서 복사)

| 순서 | 오브젝트                             | 키(외부 ID)                              | 방법                                      | 주의                                                     |
| ---- | ------------------------------------ | ---------------------------------------- | ----------------------------------------- | -------------------------------------------------------- |
| 1    | Product2(부품·모델)                  | ErpPartCode__c                           | Data Loader upsert (IF-01 대신 초기 이관) | Family = Compressor/General/EquipmentModel               |
| 2    | Account(고객사)                      | BusinessRegistrationNumber__c(개인 제외) | upsert, 레코드 유형 지정                  | 사업자번호 형식 검증 규칙                                |
| 3    | CustomerSite__c(사업장)              | SiteCode__c                              | upsert, 행정구역 코드 포함                | 저장 시 트리거가 서비스센터 지정 → 매핑 없는 주소는 거부 |
| 4    | Asset(장비)                          | SerialKey__c                             | upsert                                    | 이름은 Flow가 생성. 고객사 필수(설치처 미확인은 대리점)  |
| 5    | Location·ProductItem(창고·차량 재고) | ErpLocationCode__c / 위치+부품           | insert                                    | 차량 재고 소유자 = 기사                                  |
| 6    | (선택) 과거 접수                     | —                                        | insert                                    | 종결 접수는 수정 잠금 규칙 주의                          |

- 대량 적재 중 트리거 영향을 줄이려면 `TriggerSetting__mdt`(Case·ProductConsumed·ProductTransfer)로 일시 비활성화 → 적재 후 다시 활성화하고 `scripts/apex/d6_backfill.apex`로 장비 집계 재계산
- 사업장 서비스센터를 매핑 변경 후 다시 맞출 때 `scripts/apex/d8_site_center_reapply.apex`(APPLY = false로 대상 건수부터)
- **ERP 연동 전 데이터 주의**: 연동 활성화 전에 만든 사용 부품이 대기 상태로 남아 있으면 재전송 Batch가 ERP로 보내 이중 차감된다(decision-log ERP 13) → 이관 데이터는 ERP 상태를 비우거나 Synced로 넣는다
- 검증: 오브젝트별 원본 건수 = 적재 건수, 외부 ID 중복 0, 장비 고객사 누락 0, 사업장 서비스센터 누락 0, 장비 모델 누락 확인(2026-10-15 dev org 기준 0)

## 5. 배포 후 스모크 테스트 (역할별, 30분 안)

| 역할   | 확인                                                                                                           |
| ------ | -------------------------------------------------------------------------------------------------------------- |
| 상담원 | 가상 착신 → 접수 작성 팝업(카드·중복 경고) → 접수 저장 → 소유자 센터 Queue / 장비 검색 / 사업장 주소 검색      |
| 센터장 | 자기 센터 접수·출동만 보임 / 출동 생성·배정 / 승인 요청 승인·반려                                              |
| 기사   | 고객사·사업장·장비·접수 탭 없음 / 본인 출동만 / 부품 추가(남은 수량 초과 거부) → ERP 전송 Synced / [승인 요청] |
| 관리자 | 예약 작업 3개 WAITING / ERP 입고 1건 푸시 "즉시 반영됨" / 커버리지·테스트 결과                                 |

## 6. 롤백

| 상황                          | 방법                                                                                                                                                                                    |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 검증(validate) 실패           | 대상 org 변경 없음 → 원인 수정 후 다시 검증                                                                                                                                             |
| 빠른 배포 후 기능 문제        | ① 배포 전에 대상 org를 같은 매니페스트로 retrieve해 둔 백업(`backup/<org>-<날짜>`)을 다시 배포 ② 새로 추가된 구성 요소는 `destructiveChanges.xml`로 삭제 배포 ③ Flow는 이전 버전 활성화 |
| 트리거 문제(데이터 오류 확산) | `TriggerSetting__mdt.IsActive__c = false`로 해당 오브젝트 트리거 즉시 중지(배포 없이 설정 변경)                                                                                         |
| ERP 연동 문제                 | 예약 작업 "HG ERP 재전송"·"HG ERP 재고 동기화" 해제, 외부 클라이언트 앱 비활성화(푸시 차단). Salesforce 저장은 유지되고 전송 상태 Failed로 남아 복구 후 재전송                          |
| 데이터 이관 오류              | 적재 전 Data Loader로 대상 오브젝트 export(백업) → 적재분은 성공 파일의 Id로 delete, 원래 값은 백업으로 update                                                                          |

- 롤백 판단 기준: 스모크 테스트 1건이라도 실패하면 Open 보류 → 핫픽스(재검증 + 빠른 배포) 또는 롤백 결정(관리자)
