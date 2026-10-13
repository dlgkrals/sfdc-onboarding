# 인터페이스 정의서 — 한결공조 AS 관리

| 문서번호  | 버전 | 작성일자   | 프로젝트                             | 작성자               | 검토자 | 승인자 |
| --------- | ---- | ---------- | ------------------------------------ | -------------------- | ------ | ------ |
| HG-IF-001 | V1.0 | 2026-10-13 | 한결공조 AS 관리 (Salesforce 온보딩) | 이학민 (초안 Claude) |        |        |

## 변경 이력

| 버전 | 변경일자   | 작성자 | 변경 내용                        |
| ---- | ---------- | ------ | -------------------------------- |
| V1.0 | 2026-10-13 | 이학민 | 최초 작성: IF-05 도로명주소 검색 |

## 1. 인터페이스 목록

| No  | I/F ID | 인터페이스 명        | 설명                                      | 송신       | 수신                      | 방향           | 방식                                     | 처리형태 | 주기           | 매핑 항목수      | 시트 |
| --- | ------ | -------------------- | ----------------------------------------- | ---------- | ------------------------- | -------------- | ---------------------------------------- | -------- | -------------- | ---------------- | ---- |
| 1   | IF-05  | IF_JUSO_ADDRESS_0001 | 도로명주소 검색 (사업장·고객사 주소 입력) | Salesforce | 행정안전부 도로명주소 API | 송신(Outbound) | REST(HTTPS POST, form-urlencoded → JSON) | Online   | 사용자 검색 시 | 요청 5 · 응답 10 | 2장  |

- I/F ID: ERP 연동이 IF-03(사용 부품 → ERP)·IF-04(재고 이동 → ERP)로 예정돼 있어 IF-05 사용. **설계 세션의 IF 번호 체계와 맞는지 확인 필요**

## 2. IF-05 도로명주소 검색

### ■ 개요

| 항목          | 내용                                                                                                                                                                                              |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 목적          | 상담원·센터장이 사업장·고객사 주소를 정확한 도로명주소로 입력하고, 사업장은 행정구역 코드로 서비스센터를 자동 지정                                                                                |
| 호출 화면     | 사업장·고객사 레코드의 빠른 작업 "주소 검색" (`addressEditAction` → 공통 `addressSearch`)                                                                                                         |
| 호출 프로그램 | `[Apex] AddressSearchController.searchAddresses(keyword, pageNumber)` · `[Apex] ServiceCenterMappingService.resolveServiceCenter(admCd)`                                                          |
| 대상 URL      | `callout:HG_JusoApi/addrlink/addrLinkApi.do` → `https://business.juso.go.kr/addrlink/addrLinkApi.do`                                                                                              |
| 인증          | 승인키 `confmKey`. External Credential `HG_JusoApi` 보안 주체 `HG_JusoPrincipal`의 인증 매개변수 `ConfmKey`, 요청 본문 merge field `{!$Credential.HG_JusoApi.ConfmKey}` (코드·Git·로그에 키 없음) |
| 권한          | 상담원·센터장·관리자 권한 집합: 컨트롤러 실행 + 보안 주체 사용                                                                                                                                    |
| 시간 제한     | 10초                                                                                                                                                                                              |
| 승인키        | 개발용(30일). 만료 시 `E0014` → 화면에 "승인키가 없거나 만료" 안내 → 관리자가 운영키로 교체                                                                                                       |

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

| 대상                      | 규칙                                                                                                                                                                                                                              |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 사업장 `ServiceCenter__c` | `ServiceCenterMapping__mdt`에서 admCd **앞 5자리(시군구) → 앞 2자리(시도)** 순으로 찾음. 찾으면 미리 채우고 저장 전 변경 가능. 없으면 현재 값 유지·사용자 선택. 서비스센터 수정 권한이 없는 사용자(상담원)는 센터를 저장하지 않음 |
| 사업장 `DetailAddress__c` | 사용자가 모달에서 입력 (동·층·호)                                                                                                                                                                                                 |
| 고객사 청구지             | `BillingCountryCode = KR`, `BillingStateCode` 비움, `BillingCity = sggNm`, `BillingStreet = roadAddrPart1 + ", 상세주소" + " 참고항목"`, `BillingPostalCode = zipNo`                                                              |
| 저장                      | 화면에서 LDS `updateRecord` (사용자 권한·검증 규칙 그대로)                                                                                                                                                                        |

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
