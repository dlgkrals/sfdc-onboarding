/**
 * @description 출동 사용 부품 화면 (부모) — 이 출동에 쓴 부품, 유·무상 판정, ERP 전송 상태, 유상 부품비·총 청구액·승인 필요
 *              출동(WorkOrder) 레코드 페이지에 배치. 자식 partAddForm이 저장하면 partadded 이벤트를 받아 목록·합계를 다시 읽음
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 데이터 방식: @wire Apex (WorkOrderPartsController.getParts) — 출동 Id만으로 정해지는 조회
 *   - 자식 저장 후: refreshApex(목록·합계) + notifyRecordUpdateAvailable(출동 레코드 → 같은 페이지의 표준 상세도 새 합계로)
 *   - ERP 전송은 비동기라 저장 직후엔 "대기". 새로 고침 버튼으로 결과 확인
 * ----------------------------------------------------------------------------
 * @see partAddForm, WorkOrderPartsController, docs/d7_lwc_memo.md 3절
 */
import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import { refreshApex } from "@salesforce/apex";
import getParts from "@salesforce/apex/WorkOrderPartsController.getParts";
import { reduceErrors } from "c/ldsUtils";

import LABEL_PARTS_TITLE from "@salesforce/label/c.LABEL_PARTS_TITLE";
import LABEL_REFRESH from "@salesforce/label/c.LABEL_REFRESH";
import LABEL_PAID_TOTAL from "@salesforce/label/c.LABEL_PAID_TOTAL";
import LABEL_TOTAL_CHARGE from "@salesforce/label/c.LABEL_TOTAL_CHARGE";
import LABEL_NEEDS_APPROVAL from "@salesforce/label/c.LABEL_NEEDS_APPROVAL";
import LABEL_COL_PART from "@salesforce/label/c.LABEL_COL_PART";
import LABEL_COL_QUANTITY from "@salesforce/label/c.LABEL_COL_QUANTITY";
import LABEL_COL_CHARGE from "@salesforce/label/c.LABEL_COL_CHARGE";
import LABEL_COL_AMOUNT from "@salesforce/label/c.LABEL_COL_AMOUNT";
import LABEL_COL_ERP_STATUS from "@salesforce/label/c.LABEL_COL_ERP_STATUS";
import LABEL_COL_ERP_REMAINING from "@salesforce/label/c.LABEL_COL_ERP_REMAINING";
import MSG_NO_PARTS from "@salesforce/label/c.MSG_NO_PARTS";
import MSG_PART_ADDED from "@salesforce/label/c.MSG_PART_ADDED";
import MSG_PART_JUDGED from "@salesforce/label/c.MSG_PART_JUDGED";
import MSG_ERP_PENDING_HINT from "@salesforce/label/c.MSG_ERP_PENDING_HINT";
import MSG_LOAD_ERROR from "@salesforce/label/c.MSG_LOAD_ERROR";

const CHARGE_PAID = "Paid";
// DESC: ERP 전송 상태 → 아이콘 (색만으로 구분하지 않도록 상태 이름 글자와 함께 표시)
const ERP_ICON_BY_STATUS = {
  Pending: "utility:clock",
  Synced: "utility:success",
  Failed: "utility:error",
  NeedsReview: "utility:warning"
};

const COLUMNS = [
  { label: LABEL_COL_PART, fieldName: "partText", wrapText: true },
  { label: LABEL_COL_QUANTITY, fieldName: "quantityText", initialWidth: 110 },
  {
    label: LABEL_COL_CHARGE,
    fieldName: "chargeTypeLabel",
    initialWidth: 90,
    cellAttributes: { class: { fieldName: "chargeClass" } }
  },
  {
    label: LABEL_COL_AMOUNT,
    fieldName: "amount",
    type: "currency",
    typeAttributes: { currencyCode: "KRW" },
    initialWidth: 120
  },
  {
    label: LABEL_COL_ERP_STATUS,
    fieldName: "erpStatusLabel",
    initialWidth: 130,
    cellAttributes: { iconName: { fieldName: "erpIcon" } }
  },
  {
    label: LABEL_COL_ERP_REMAINING,
    fieldName: "erpRemaining",
    initialWidth: 140
  }
];

export default class WorkOrderParts extends LightningElement {
  @api recordId;

  labels = {
    LABEL_REFRESH,
    LABEL_PAID_TOTAL,
    LABEL_TOTAL_CHARGE,
    LABEL_NEEDS_APPROVAL,
    MSG_NO_PARTS
  };
  columns = COLUMNS;

  rows = [];
  paidTotal = 0;
  totalCharge = 0;
  needsApproval = false;
  canAdd = false;
  errorMessage;
  isLoading = true;
  wiredResult;

  @wire(getParts, { workOrderId: "$recordId" })
  wiredParts(result) {
    this.wiredResult = result;
    const { data, error } = result;
    if (data) {
      this.rows = data.rows.map((row) => ({
        ...row,
        partText: row.partCode
          ? `${row.partName} (${row.partCode})`
          : row.partName,
        quantityText: `${row.quantity} ${row.unitLabel}`.trim(),
        chargeClass:
          row.chargeType === CHARGE_PAID ? "slds-text-color_error" : "",
        erpIcon: ERP_ICON_BY_STATUS[row.erpStatus] || null
      }));
      this.paidTotal = data.paidTotal || 0;
      this.totalCharge = data.totalCharge || 0;
      this.needsApproval = data.needsApproval;
      this.canAdd = data.canAdd;
      this.errorMessage = undefined;
      this.isLoading = false;
    } else if (error) {
      this.errorMessage = reduceErrors(error).join(", ");
      this.rows = [];
      this.isLoading = false;
      this.showToast(MSG_LOAD_ERROR, this.errorMessage, "error");
    }
  }

  get title() {
    return `${LABEL_PARTS_TITLE} (${this.rows.length})`;
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get isEmpty() {
    return !this.isLoading && !this.errorMessage && this.rows.length === 0;
  }

  handleRefresh() {
    return this.refreshAll();
  }

  // DESC: 자식이 저장을 끝냈다는 신호. 판정은 트리거가 했으므로 저장된 결과를 다시 읽어 그 판정을 알려 줌
  //       html의 <c-part-add-form onpartadded={handlePartAdded}>로 자식 요소에 직접 리스너를 닮
  //       → 자식은 bubbles·composed 없이(기본 false) 보내도 받음. 이 컴포넌트 밖으로는 새어 나가지 않음
  async handlePartAdded(event) {
    const { partId } = event.detail;
    await this.refreshAll();
    const added = this.rows.find((row) => row.id === partId);
    const message = added
      ? MSG_PART_JUDGED.replace("{0}", added.partName)
          .replace("{1}", added.quantity)
          .replace("{2}", added.unitLabel)
          .replace("{3}", added.chargeTypeLabel || "")
      : "";
    this.showToast(
      MSG_PART_ADDED,
      `${message} ${MSG_ERP_PENDING_HINT}`.trim(),
      "success"
    );
  }

  async refreshAll() {
    await refreshApex(this.wiredResult);
    // DESC: 출동의 롤업(부품비 합계)·수식(총 청구액)이 바뀜 → 같은 페이지의 표준 상세(LDS)에도 알림
    await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
