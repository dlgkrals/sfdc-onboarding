# D6 화면 설계 초안 (D7 LWC 준비)

- 작성: 2026-10-12 · 초안 Claude 작성 → **Edwin 검토 필요** · 사용자: 콜센터 상담원(HG_CallCenter), 센터장(HG_CenterManager). 협력 기사는 장비 권한이 없어 SC-01·SC-04 대상 아님
- 공통: Apex 컨트롤러는 `with sharing` + 조회 `WITH USER_MODE`(화면은 사용자 권한대로), 오류는 `reduceErrors` → `ShowToastEvent`(오류), 문구는 Custom Label(`LABEL_`, `MSG_`, `BTN_`)

## SC-01 장비 검색 목록 — `assetSearch`

| 항목           | 내용                                                                                                                                                                                                                                                         |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 목적           | 전화 접수 때 고객이 말한 고객사·사업장·시리얼로 장비를 빨리 찾고, 반복 고장 장비를 바로 알아봄                                                                                                                                                               |
| 배치           | Lightning 앱 페이지(AS 관리 앱의 "장비 검색" 탭)                                                                                                                                                                                                             |
| 컴포넌트       | `assetSearch`(부모: 검색어·정렬·페이지 상태 보유) ⊃ `lightning-input`(검색) · `lightning-datatable`(목록) · 페이지 버튼(이전/다음, `N / 총 M쪽`)                                                                                                             |
| 열             | 시리얼(`SerialKey__c`, 행 클릭 링크) · 모델 · 고객사 · 사업장 · 센터 · 보증 상태(`fmWarrantyStatus__c`) · 최근 90일 접수(`RecentCaseCount__c`) · **반복 고장**(`RepeatFailure__c` → 빨간 경고 아이콘 + 행 강조)                                              |
| 검색           | 한 칸 입력 → 고객사명·사업장명·시리얼 LIKE 검색. 입력 후 300ms 디바운스, 2글자 이상부터                                                                                                                                                                      |
| 정렬           | 열 머리글 클릭(`onsort`) → 서버 정렬. 허용 필드 화이트리스트(시리얼·고객사·최근 접수·보증 상태)만                                                                                                                                                            |
| 페이징         | 20건씩, 서버 `LIMIT/OFFSET` (OFFSET 최대 2,000 → 장비 수 증가 시 키셋 페이징으로 전환)                                                                                                                                                                       |
| 데이터         | **imperative** 호출 — 검색·정렬·페이지 이동이 모두 사용자 동작이라 호출 시점을 컴포넌트가 정함. 메서드는 `cacheable=true`로 같은 조건 재조회는 캐시                                                                                                          |
| Apex           | `AssetSearchController.searchAssets(String searchKey, String sortField, String sortDirection, Integer pageSize, Integer pageNumber)` → `AssetSearchController.AssetPage`(rows, totalCount). 검색어는 바인드 변수, 정렬 필드는 화이트리스트(SOQL 인젝션 방어) |
| 행 클릭        | `NavigationMixin`으로 장비 레코드 페이지(SC-04가 배치된 페이지)로 이동                                                                                                                                                                                       |
| 빈 결과 / 오류 | 결과 0건: "검색 결과가 없습니다. 고객사명·사업장명·시리얼을 확인하세요."(`MSG_ASSET_NOT_FOUND`) / 오류: 토스트 + 목록 유지 / 로딩: `lightning-spinner`                                                                                                       |

## SC-04 장비 상세 — `assetDetail`

| 항목           | 내용                                                                                                                                                                                                                                                       |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 목적           | 접수 전에 장비의 보증 상태·부품별 만료일·최근 접수 이력을 한 화면에서 확인                                                                                                                                                                                 |
| 배치           | Asset 레코드 페이지 (`recordId` 자동 전달)                                                                                                                                                                                                                 |
| 컴포넌트       | `assetDetail`(부모, `@api recordId`) ⊃ `lightning-record-view-form`(기본 정보·보증) · `assetRecentCases`(자식, 최근 접수 목록)                                                                                                                             |
| 기본 정보      | 시리얼 · 모델 · 고객사 · 사업장 · 설치일 · 판매 경로 · 누적 접수 · 최근 90일 접수 · 반복 고장 장비 (`lightning-output-field`, 읽기 전용)                                                                                                                   |
| 보증           | 보증 상태 배지(`fmWarrantyStatus__c`: 보증 중/부분 보증/보증 만료/미확정) · 시작일 · 기본/압축기/연장 만료일 (Formula 3개)                                                                                                                                 |
| 데이터         | 기본 정보·보증: **LDS** (`record-view-form`) — 캐시·레코드 변경 시 자동 갱신, Apex 불필요. 최근 접수: **@wire** `AssetDetailController.getRecentCases(Id assetId, Integer limitSize)` (`cacheable=true`) — `recordId`에 반응해 자동 조회, 사용자 동작 없음 |
| 최근 접수      | `lightning-datatable` 10건: 접수번호 · 접수일 · 증상 · 상태 · 반복 고장(접수 시점 표시) · 센터. 새 접수 저장 후 `refreshApex`                                                                                                                              |
| 빈 결과 / 오류 | 접수 0건: "최근 접수가 없습니다."(`MSG_NO_RECENT_CASES`) / 오류: 카드 안에 오류 문구 + 토스트 / 권한 없음(기사 등): 컴포넌트를 페이지 가시성 규칙으로 숨김                                                                                                 |

## SC-xx 출동 사용 부품 (D8 스케치)

```
workOrderParts (부모, 출동 레코드 페이지, @api recordId)
 ├─ 사용 부품 목록 (lightning-datatable: 부품·수량·자동 판정·최종 판정·금액) + 합계(유상 부품비)
 └─ partAddForm (자식): 제품 항목 선택 + 수량 → 저장(imperative, DML이라 cacheable 불가)
       └─ 저장 성공 시 CustomEvent('partadded', { detail: { partId } }) → 부모
부모: onpartadded → refreshApex(목록·합계) → 판정 결과 토스트 ("보증 내 무상" / "유상")
```

- 저장은 트리거가 유·무상을 판정하므로 화면은 수량·제품 항목만 받음. 사유 입력은 최종 판정을 바꿀 때만 표시
- 기사 사용자로 동작해야 함 → 컨트롤러는 `with sharing` + 기사 차량 재고만 조회 (D6에서 발견한 권한 결함 참고)

## 검토 요청 (결정 필요)

1. SC-01 검색 대상에 **접수 번호**도 넣을지 (현재: 고객사·사업장·시리얼)
2. SC-01 기본 정렬: 반복 고장 장비 먼저 → 최근 접수 많은 순 (제안) / 시리얼 순
3. SC-04 최근 접수 건수 10건 고정 vs "더 보기"
4. 페이지 크기 20건 고정 vs 사용자가 선택(10/20/50)
