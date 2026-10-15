/**
 * @description SC-01 장비 검색 목록 — 상담원이 전화 받으며 고객사·사업장·시리얼로 장비를 찾고 반복 고장 장비를 알아봄
 *              검색(300ms 디바운스, 2글자 이상) · "반복 고장 장비만" 필터 · 서버 정렬 · 20건 페이징
 *              시리얼 클릭 → 장비 요약 팝업 → [장비 열기] / [이 장비로 접수](접수 작성 팝업) / [닫기]
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 1.0  2026-10-13  Edwin  최초 작성 (D7)
 * 1.1  2026-10-15  Edwin  시리얼 클릭 시 이동하지 않고 장비 요약 팝업, "이 장비로 접수" 추가 (CTI 가상 착신)
 * 1.2  2026-10-15  Edwin  접수 작성 팝업 크기 large (오른쪽 카드, 피드백 개선 ①)
 * ----------------------------------------------------------------------------
 * 데이터 방식: imperative Apex (AssetSearchController.searchAssets)
 *   - 검색어 입력·필터·정렬·페이지 이동이 모두 "사용자 동작"이라 호출 시점을 컴포넌트가 정해야 함
 *     (@wire는 인자가 바뀌면 바로 자동 호출 → 디바운스·2글자 기준·이전 응답 무시를 다루기 어려움)
 *   - 메서드는 cacheable=true라 같은 조건 재조회는 클라이언트 캐시 사용
 * ----------------------------------------------------------------------------
 * @see AssetSearchController, docs/d6_screen_design.md SC-01
 */
import { LightningElement, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import searchAssets from "@salesforce/apex/AssetSearchController.searchAssets";
import canCreateCase from "@salesforce/apex/CallIntakeController.canCreateCase";
import AssetSummaryModal from "c/assetSummaryModal";
import CaseIntakeModal from "c/caseIntakeModal";
import { reduceErrors } from "c/ldsUtils";

import LABEL_ASSET_SEARCH_TITLE from "@salesforce/label/c.LABEL_ASSET_SEARCH_TITLE";
import LABEL_SEARCH from "@salesforce/label/c.LABEL_SEARCH";
import MSG_SEARCH_PLACEHOLDER from "@salesforce/label/c.MSG_SEARCH_PLACEHOLDER";
import LABEL_REPEAT_ONLY from "@salesforce/label/c.LABEL_REPEAT_ONLY";
import LABEL_COL_SERIAL from "@salesforce/label/c.LABEL_COL_SERIAL";
import LABEL_COL_MODEL from "@salesforce/label/c.LABEL_COL_MODEL";
import LABEL_COL_ACCOUNT from "@salesforce/label/c.LABEL_COL_ACCOUNT";
import LABEL_COL_SITE from "@salesforce/label/c.LABEL_COL_SITE";
import LABEL_COL_CENTER from "@salesforce/label/c.LABEL_COL_CENTER";
import LABEL_COL_WARRANTY from "@salesforce/label/c.LABEL_COL_WARRANTY";
import LABEL_COL_LAST_CASE from "@salesforce/label/c.LABEL_COL_LAST_CASE";
import LABEL_COL_RECENT_CASES from "@salesforce/label/c.LABEL_COL_RECENT_CASES";
import LABEL_COL_REPEAT from "@salesforce/label/c.LABEL_COL_REPEAT";
import LABEL_REPEAT_FLAG from "@salesforce/label/c.LABEL_REPEAT_FLAG";
import BTN_PREVIOUS from "@salesforce/label/c.BTN_PREVIOUS";
import BTN_NEXT from "@salesforce/label/c.BTN_NEXT";
import LABEL_PAGE_INFO from "@salesforce/label/c.LABEL_PAGE_INFO";
import MSG_ASSET_NOT_FOUND from "@salesforce/label/c.MSG_ASSET_NOT_FOUND";
import MSG_LOAD_ERROR from "@salesforce/label/c.MSG_LOAD_ERROR";
import LABEL_ASSET_SUMMARY_TITLE from "@salesforce/label/c.LABEL_ASSET_SUMMARY_TITLE";
import LABEL_CASE_INTAKE_TITLE from "@salesforce/label/c.LABEL_CASE_INTAKE_TITLE";
import MSG_CASE_CREATED from "@salesforce/label/c.MSG_CASE_CREATED";

const SEARCH_DELAY_MS = 300;
const MIN_SEARCH_LENGTH = 2;
const DEFAULT_SORT_FIELD = "lastCaseDate";
const DEFAULT_SORT_DIRECTION = "desc";
const ACTION_VIEW = "view";
// DESC: assetSummaryModal 닫기 결과 값과 같게
const SUMMARY_RESULT_OPEN = "open";
const SUMMARY_RESULT_INTAKE = "intake";

const DATE_FORMAT = { year: "numeric", month: "2-digit", day: "2-digit" };
// DESC: 반복 고장 장비는 시리얼·반복 고장 칸을 빨간 글씨로 강조
const ROW_CLASS = { fieldName: "rowClass" };

const COLUMNS = [
  {
    label: LABEL_COL_SERIAL,
    fieldName: "serialKey",
    type: "button",
    sortable: true,
    typeAttributes: {
      label: { fieldName: "serialKey" },
      name: ACTION_VIEW,
      variant: "base"
    },
    cellAttributes: { class: ROW_CLASS }
  },
  { label: LABEL_COL_MODEL, fieldName: "model" },
  { label: LABEL_COL_ACCOUNT, fieldName: "accountName", sortable: true },
  { label: LABEL_COL_SITE, fieldName: "siteName" },
  { label: LABEL_COL_CENTER, fieldName: "serviceCenter" },
  { label: LABEL_COL_WARRANTY, fieldName: "warrantyStatus", sortable: true },
  {
    label: LABEL_COL_LAST_CASE,
    fieldName: "lastCaseDate",
    type: "date-local",
    sortable: true,
    typeAttributes: DATE_FORMAT
  },
  {
    label: LABEL_COL_RECENT_CASES,
    fieldName: "recentCaseCount",
    type: "number",
    sortable: true,
    initialWidth: 140,
    cellAttributes: { alignment: "left" }
  },
  {
    label: LABEL_COL_REPEAT,
    fieldName: "repeatText",
    initialWidth: 120,
    cellAttributes: {
      iconName: { fieldName: "repeatIcon" },
      iconAlternativeText: LABEL_REPEAT_FLAG,
      class: ROW_CLASS
    }
  }
];

export default class AssetSearch extends NavigationMixin(LightningElement) {
  labels = {
    LABEL_ASSET_SEARCH_TITLE,
    LABEL_SEARCH,
    MSG_SEARCH_PLACEHOLDER,
    LABEL_REPEAT_ONLY,
    BTN_PREVIOUS,
    BTN_NEXT,
    MSG_ASSET_NOT_FOUND
  };
  columns = COLUMNS;

  rows = [];
  totalCount = 0;
  pageNumber = 1;
  pageSize = 20;
  searchKey = "";
  repeatOnly = false;
  sortedBy = DEFAULT_SORT_FIELD;
  sortedDirection = DEFAULT_SORT_DIRECTION;
  isLoading = false;
  hasLoaded = false;
  // DESC: 접수 생성 권한(상담원·관리자). 클래스 접근이 없는 센터장은 호출 실패 → false → "이 장비로 접수" 숨김
  canIntake = false;

  searchTimer;
  // DESC: 빠르게 연속 호출될 때 늦게 도착한 이전 응답이 최신 결과를 덮지 않도록 요청 번호로 구분
  requestSeq = 0;

  @wire(canCreateCase)
  wiredCanIntake({ data }) {
    this.canIntake = data === true;
  }

  connectedCallback() {
    this.loadPage();
  }

  disconnectedCallback() {
    clearTimeout(this.searchTimer);
  }

  get totalPages() {
    return Math.max(1, Math.ceil(this.totalCount / this.pageSize));
  }

  get isFirstPage() {
    return this.pageNumber <= 1 || this.isLoading;
  }

  get isLastPage() {
    return this.pageNumber >= this.totalPages || this.isLoading;
  }

  get isEmpty() {
    return this.hasLoaded && !this.isLoading && this.rows.length === 0;
  }

  get pageInfo() {
    return LABEL_PAGE_INFO.replace("{0}", this.pageNumber)
      .replace("{1}", this.totalPages)
      .replace("{2}", this.totalCount);
  }

  // DESC: 입력이 300ms 멈추면 검색. 1글자는 서버에서 무시되므로 호출하지 않음 (지우면 전체로 복귀)
  handleSearchChange(event) {
    const value = (event.target.value || "").trim();
    clearTimeout(this.searchTimer);
    if (value.length > 0 && value.length < MIN_SEARCH_LENGTH) {
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => {
      this.searchKey = value;
      this.pageNumber = 1;
      this.loadPage();
    }, SEARCH_DELAY_MS);
  }

  handleRepeatOnlyChange(event) {
    this.repeatOnly = event.target.checked;
    this.pageNumber = 1;
    this.loadPage();
  }

  // DESC: 정렬은 서버에서 (페이지가 나뉘어 있어 화면에서만 정렬하면 현재 20건 안에서만 정렬됨)
  handleSort(event) {
    this.sortedBy = event.detail.fieldName;
    this.sortedDirection = event.detail.sortDirection;
    this.pageNumber = 1;
    this.loadPage();
  }

  handlePrevious() {
    this.pageNumber -= 1;
    this.loadPage();
  }

  handleNext() {
    this.pageNumber += 1;
    this.loadPage();
  }

  // DESC: 시리얼 클릭 → 바로 이동하지 않고 장비 요약 팝업 (통화 중 목록을 벗어나지 않게)
  async handleRowAction(event) {
    if (event.detail.action.name !== ACTION_VIEW) {
      return;
    }
    const assetId = event.detail.row.id;
    const choice = await AssetSummaryModal.open({
      size: "medium",
      label: LABEL_ASSET_SUMMARY_TITLE,
      assetId,
      canIntake: this.canIntake
    });
    if (choice === SUMMARY_RESULT_OPEN) {
      this.navigateToRecord(assetId, "Asset");
    } else if (choice === SUMMARY_RESULT_INTAKE) {
      // DESC: 모달 안에서 모달을 열지 않고, 요약 팝업이 닫힌 뒤 여기서 접수 작성 팝업(장비만 채움)
      const result = await CaseIntakeModal.open({
        size: "large",
        label: LABEL_CASE_INTAKE_TITLE,
        assetId
      });
      if (result?.caseId) {
        this.dispatchEvent(
          new ShowToastEvent({ title: MSG_CASE_CREATED, variant: "success" })
        );
        this.navigateToRecord(result.caseId, "Case");
      }
    }
  }

  navigateToRecord(recordId, objectApiName) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId, objectApiName, actionName: "view" }
    });
  }

  async loadPage() {
    const seq = ++this.requestSeq;
    this.isLoading = true;
    try {
      const page = await searchAssets({
        searchKey: this.searchKey,
        repeatOnly: this.repeatOnly,
        sortField: this.sortedBy,
        sortDirection: this.sortedDirection,
        pageNumber: this.pageNumber
      });
      if (seq !== this.requestSeq) {
        return;
      }
      this.rows = page.rows.map((row) => ({
        ...row,
        repeatText: row.repeatFailure ? LABEL_REPEAT_FLAG : "",
        repeatIcon: row.repeatFailure ? "utility:warning" : null,
        rowClass: row.repeatFailure ? "slds-text-color_error" : ""
      }));
      this.totalCount = page.totalCount;
      this.pageNumber = page.pageNumber;
      this.pageSize = page.pageSize;
    } catch (error) {
      // DESC: 오류여도 기존 목록은 유지하고 토스트로 알림 (설계 SC-01 빈 결과/오류)
      if (seq === this.requestSeq) {
        this.dispatchEvent(
          new ShowToastEvent({
            title: MSG_LOAD_ERROR,
            message: reduceErrors(error).join(", "),
            variant: "error"
          })
        );
      }
    } finally {
      if (seq === this.requestSeq) {
        this.isLoading = false;
        this.hasLoaded = true;
      }
    }
  }
}
