# D7 LWC 메모 — 데이터 방식 판단 · 자식→부모 이벤트 설계

- 작성: 2026-10-13 · 대상 화면: SC-01 장비 검색 `assetSearch`, SC-04 장비 상세 `assetDetail` · `assetRecentCases`
- 배치: 한결공조 AS 앱 "장비 검색" 탭(앱 페이지 `HG_AssetSearch`), 장비 레코드 페이지 `HG_AssetRecordPage`(앱 기본 페이지로 지정)

## 1. wire / imperative / LDS — 쓴 곳과 이유 (3줄)

1. **imperative** — `assetSearch`의 `searchAssets`: 검색어 입력(300ms 디바운스, 2글자 기준)·필터·정렬·페이지 이동이 모두 사용자 동작이라 호출 시점을 컴포넌트가 정해야 함. @wire는 인자가 바뀌면 즉시 자동 호출돼 디바운스와 "늦게 온 이전 응답 무시"를 다루기 어려움
2. **@wire (Apex)** — `assetRecentCases`의 `getRecentCases`: 사용자 동작 없이 `recordId`만으로 정해지는 조회. 값이 바뀌면 자동 재조회되고 캐시를 씀. 새 접수 후에는 `refreshApex`로 갱신
3. **LDS** — `assetDetail`의 기본 정보·보증(`lightning-record-view-form`)과 보증 배지(`@wire getRecord`): 레코드 한 건 표시는 Apex가 필요 없고 권한·캐시·다른 곳의 변경 반영을 Salesforce가 처리

## 2. 화면별 정리

| 화면            | 컴포넌트                                                    | 데이터                                      | Apex 메서드                                                                                                                                             | 비고                                                                                                                                                   |
| --------------- | ----------------------------------------------------------- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| SC-01 장비 검색 | `assetSearch`                                               | imperative (cacheable=true)                 | `AssetSearchController.searchAssets(searchKey, repeatOnly, sortField, sortDirection, pageNumber)` → `AssetPage(rows, totalCount, pageNumber, pageSize)` | 20건 고정, 기본 정렬 최근 접수일 내림차순 NULLS LAST, 정렬 필드 화이트리스트, "반복 고장 장비만" 필터, 행(시리얼) 클릭 → `NavigationMixin` 장비 레코드 |
| SC-04 장비 상세 | `assetDetail` (부모, `@api recordId`)                       | LDS (`record-view-form`, `@wire getRecord`) | 없음                                                                                                                                                    | 보증 상태 배지 색: 보증 중 초록 · 부분 보증 주황 · 보증 만료 빨강 · 미확정 기본                                                                        |
| SC-04 최근 접수 | `assetRecentCases` (자식, `@api assetId`, `@api refresh()`) | @wire Apex (cacheable=true)                 | `AssetDetailController.getRecentCases(assetId)` → `RecentCases(rows, totalCount)`                                                                       | 최근 5건, 6건 이상이면 "모두 보기" → 표준 관련 목록(`standard__recordRelationshipPage`, Cases)                                                         |

- 공통: 컨트롤러 `with sharing` + 조회 `USER_MODE`(화면은 사용자 권한대로). 오류는 `c/ldsUtils.reduceErrors` → `ShowToastEvent`(오류). 문구는 Custom Label 29개(`LABEL_` · `MSG_` · `BTN_`)
- 권한: 상담원·센터장·관리자 권한 집합에 두 컨트롤러 클래스 접근과 "장비 검색" 탭 표시 추가. 협력 기사는 장비·접수 권한이 없어 대상 아님(호출하면 오류 → 토스트)
- 부모→자식: `assetDetail`이 장비 누적 접수 수·최근 접수일 변화를 `getRecord`로 감지하면 자식의 `@api refresh()` 호출

## 3. 자식→부모 이벤트로 구현할 기능 (D8 설계)

출동 사용 부품 화면에서 **부품을 추가하면 목록·합계를 다시 그리는** 기능을 자식→부모 이벤트로 구현한다.

```
workOrderParts (부모, 출동 레코드 페이지, @api recordId)
 ├─ 사용 부품 목록 (유·무상 판정 · ERP 전송 상태) + 유상 부품비 합계 + 승인 필요 표시
 └─ partAddForm (자식): 제품 항목 선택 + 수량 → 저장 (imperative, DML이라 cacheable 불가)
       └─ 저장 성공 → this.dispatchEvent(new CustomEvent('partadded', { detail: { partId } }))
부모: onpartadded → refreshApex(목록·합계) → 판정 결과 토스트 ("보증 내 무상" / "유상")
```

- 왜 이벤트인가: 자식(입력 폼)은 저장만 책임지고, 목록과 합계를 가진 부모가 갱신을 책임진다. 자식이 부모 데이터를 직접 고치지 않으므로 폼을 다른 화면에서도 재사용 가능
- `detail`에는 새 사용 부품 Id만 담고, 부모가 서버에서 다시 읽는다(판정은 트리거가 하므로 화면 값이 아닌 저장 결과를 보여야 함)
- 이벤트는 `bubbles: false`(기본) — 바로 위 부모만 받으면 충분

## 4. 시연 체크 (D8 09:00 발표)

| 확인                       | 방법                                                                                                                                                                                              |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 목록 검색·필터·정렬·페이징 | "장비 검색" 탭: `평택` 검색 → "반복 고장 장비만" → 최근 90일 접수 열 정렬 → 다음 페이지                                                                                                           |
| 상세                       | 시리얼 클릭 → 장비 레코드: 보증 배지, 부품별 만료일, 최근 접수 5건                                                                                                                                |
| 오류가 토스트로 보이는지   | 협력 기사(최민호)로 Login As → 주소창에 `/lightning/n/HG_AssetSearch` 입력 → 권한 오류 토스트 (**리허설 때 확인 필요**: 탭이 숨겨져 페이지 자체가 막히면, 장비 상세 화면의 오류 표시로 대신 시연) |
