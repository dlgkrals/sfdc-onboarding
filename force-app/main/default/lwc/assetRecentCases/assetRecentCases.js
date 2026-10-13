/**
 * @description SC-04 장비 상세의 자식 — 이 장비의 최근 접수 5건 + 표준 관련 목록 "모두 보기"
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 데이터 방식: @wire Apex (AssetDetailController.getRecentCases, cacheable=true)
 *   - 사용자 동작 없이 부모가 넘겨 준 assetId만으로 정해지는 조회 → @wire가 맞음 (값이 바뀌면 자동 재조회, 캐시 사용)
 *   - 새 접수 저장 등으로 캐시가 낡으면 부모가 refresh()를 불러 refreshApex로 다시 가져옴
 * ----------------------------------------------------------------------------
 * @see AssetDetailController, assetDetail
 */
import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";
import getRecentCases from "@salesforce/apex/AssetDetailController.getRecentCases";
import { reduceErrors } from "c/ldsUtils";

import LABEL_RECENT_CASES_TITLE from "@salesforce/label/c.LABEL_RECENT_CASES_TITLE";
import LABEL_COL_CASE_NUMBER from "@salesforce/label/c.LABEL_COL_CASE_NUMBER";
import LABEL_COL_CREATED from "@salesforce/label/c.LABEL_COL_CREATED";
import LABEL_COL_SYMPTOM from "@salesforce/label/c.LABEL_COL_SYMPTOM";
import LABEL_COL_STATUS from "@salesforce/label/c.LABEL_COL_STATUS";
import LABEL_COL_REPEAT from "@salesforce/label/c.LABEL_COL_REPEAT";
import LABEL_REPEAT_FLAG from "@salesforce/label/c.LABEL_REPEAT_FLAG";
import LABEL_COL_CENTER from "@salesforce/label/c.LABEL_COL_CENTER";
import BTN_VIEW_ALL from "@salesforce/label/c.BTN_VIEW_ALL";
import MSG_NO_RECENT_CASES from "@salesforce/label/c.MSG_NO_RECENT_CASES";
import MSG_LOAD_ERROR from "@salesforce/label/c.MSG_LOAD_ERROR";

// DESC: 컨트롤러 RECENT_CASE_LIMIT과 같게. 이보다 많을 때만 "모두 보기" 표시
const RECENT_CASE_LIMIT = 5;

const COLUMNS = [
  {
    label: LABEL_COL_CASE_NUMBER,
    fieldName: "recordUrl",
    type: "url",
    typeAttributes: { label: { fieldName: "caseNumber" }, target: "_self" }
  },
  {
    label: LABEL_COL_CREATED,
    fieldName: "createdDate",
    type: "date",
    typeAttributes: {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    }
  },
  { label: LABEL_COL_SYMPTOM, fieldName: "symptom" },
  { label: LABEL_COL_STATUS, fieldName: "status" },
  {
    label: LABEL_COL_REPEAT,
    fieldName: "repeatText",
    cellAttributes: {
      iconName: { fieldName: "repeatIcon" },
      iconAlternativeText: LABEL_REPEAT_FLAG,
      class: { fieldName: "repeatClass" }
    }
  },
  { label: LABEL_COL_CENTER, fieldName: "serviceCenter" }
];

export default class AssetRecentCases extends NavigationMixin(
  LightningElement
) {
  @api assetId;

  labels = { LABEL_RECENT_CASES_TITLE, BTN_VIEW_ALL, MSG_NO_RECENT_CASES };
  columns = COLUMNS;
  rows = [];
  totalCount = 0;
  errorMessage;
  isLoading = true;

  wiredResult;

  @wire(getRecentCases, { assetId: "$assetId" })
  wiredCases(result) {
    this.wiredResult = result;
    const { data, error } = result;
    if (data) {
      this.rows = data.rows.map((row) => ({
        ...row,
        recordUrl: `/lightning/r/Case/${row.id}/view`,
        repeatText: row.repeatFailure ? LABEL_REPEAT_FLAG : "",
        repeatIcon: row.repeatFailure ? "utility:warning" : null,
        repeatClass: row.repeatFailure ? "slds-text-color_error" : ""
      }));
      this.totalCount = data.totalCount;
      this.errorMessage = undefined;
      this.isLoading = false;
    } else if (error) {
      // DESC: 카드 안에 오류 문구 + 토스트 (설계 SC-04 빈 결과/오류)
      this.errorMessage = reduceErrors(error).join(", ");
      this.rows = [];
      this.isLoading = false;
      this.dispatchEvent(
        new ShowToastEvent({
          title: MSG_LOAD_ERROR,
          message: this.errorMessage,
          variant: "error"
        })
      );
    }
  }

  /**
   * @description 캐시된 최근 접수를 다시 가져옴 (부모가 장비 집계 변화 감지 시 호출, 새로 고침 버튼)
   */
  @api
  refresh() {
    return this.wiredResult ? refreshApex(this.wiredResult) : Promise.resolve();
  }

  get title() {
    return `${LABEL_RECENT_CASES_TITLE} (${this.totalCount})`;
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get isEmpty() {
    return !this.isLoading && !this.errorMessage && this.rows.length === 0;
  }

  get showViewAll() {
    return this.totalCount > RECENT_CASE_LIMIT;
  }

  handleRefresh() {
    this.refresh();
  }

  // DESC: 전체 이력은 표준 관련 목록으로 (필터·정렬·내보내기를 새로 만들지 않음)
  handleViewAll() {
    this[NavigationMixin.Navigate]({
      type: "standard__recordRelationshipPage",
      attributes: {
        recordId: this.assetId,
        objectApiName: "Asset",
        relationshipApiName: "Cases",
        actionName: "view"
      }
    });
  }
}
