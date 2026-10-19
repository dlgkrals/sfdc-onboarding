/**
 * @description 출동 사용 부품 화면 (부모) — 이 출동에 쓴 부품, 유·무상 판정, ERP 전송 상태, 유상 부품비·총 청구액·승인 필요
 *              출동(WorkOrder) 레코드 페이지에 배치. 자식 partAddForm이 저장하면 partadded 이벤트를 받아 목록·합계를 다시 읽음
 *              줄마다 [판정 변경](최종 판정·변경 사유) · [삭제](ERP 실패·확인 필요 건만). 승인 대기·완료 출동은 잠김
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 LWC: 자식 → 부모 이벤트)
 * 1.1    2026-10-19    Edwin     판정 변경·삭제·잠김, 출동 레코드 변경 감지 — 표준 사용 부품 관련 목록 대신 이 화면 하나로
 * ----------------------------------------------------------------------------
 * 데이터 방식: @wire Apex (WorkOrderPartsController.getParts) — 출동 Id만으로 정해지는 조회
 *   - 저장·추가·삭제 뒤: refreshApex(목록·합계) + notifyRecordUpdateAvailable(출동 → 같은 페이지 머리글·세부 사항의 총 청구액·승인 필요)
 *   - 반대 방향: @wire(getRecord) 출동 상태·최종 수정 시각을 지켜보다 바뀌면 목록을 다시 읽음([승인 요청] 제출 → 바로 잠김)
 *   - ERP 전송은 비동기라 저장 직후엔 "대기". 새로 고침 버튼으로 결과 확인
 * ----------------------------------------------------------------------------
 * @see partAddForm, WorkOrderPartsController, docs/d7_lwc_memo.md 3절
 */
import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import {
  getRecord,
  getFieldValue,
  notifyRecordUpdateAvailable
} from "lightning/uiRecordApi";
import { refreshApex } from "@salesforce/apex";
import getParts from "@salesforce/apex/WorkOrderPartsController.getParts";
import updateChargeType from "@salesforce/apex/WorkOrderPartsController.updateChargeType";
import deletePart from "@salesforce/apex/WorkOrderPartsController.deletePart";
import WO_STATUS from "@salesforce/schema/WorkOrder.Status";
import WO_LAST_MODIFIED from "@salesforce/schema/WorkOrder.LastModifiedDate";
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
import LABEL_COL_AUTO_CHARGE from "@salesforce/label/c.LABEL_COL_AUTO_CHARGE";
import LABEL_COL_OVERRIDE_REASON from "@salesforce/label/c.LABEL_COL_OVERRIDE_REASON";
import LABEL_ACTION_CHANGE_CHARGE from "@salesforce/label/c.LABEL_ACTION_CHANGE_CHARGE";
import LABEL_ACTION_DELETE_PART from "@salesforce/label/c.LABEL_ACTION_DELETE_PART";
import LABEL_EDIT_CHARGE_TITLE from "@salesforce/label/c.LABEL_EDIT_CHARGE_TITLE";
import LABEL_FINAL_CHARGE from "@salesforce/label/c.LABEL_FINAL_CHARGE";
import BTN_SAVE from "@salesforce/label/c.BTN_SAVE";
import BTN_CANCEL from "@salesforce/label/c.BTN_CANCEL";
import MSG_NO_PARTS from "@salesforce/label/c.MSG_NO_PARTS";
import MSG_PART_ADDED from "@salesforce/label/c.MSG_PART_ADDED";
import MSG_PART_JUDGED from "@salesforce/label/c.MSG_PART_JUDGED";
import MSG_ERP_PENDING_HINT from "@salesforce/label/c.MSG_ERP_PENDING_HINT";
import MSG_LOAD_ERROR from "@salesforce/label/c.MSG_LOAD_ERROR";
import MSG_OVERRIDE_REASON_HINT from "@salesforce/label/c.MSG_OVERRIDE_REASON_HINT";
import MSG_PART_UPDATED from "@salesforce/label/c.MSG_PART_UPDATED";
import MSG_PART_DELETED from "@salesforce/label/c.MSG_PART_DELETED";
import MSG_PART_DELETE_CONFIRM from "@salesforce/label/c.MSG_PART_DELETE_CONFIRM";

const CHARGE_PAID = "Paid";
const ACTION_EDIT = "edit";
const ACTION_DELETE = "delete";
// DESC: ERP 전송 상태 → 아이콘 (색만으로 구분하지 않도록 상태 이름 글자와 함께 표시)
const ERP_ICON_BY_STATUS = {
  Pending: "utility:clock",
  Synced: "utility:success",
  Failed: "utility:error",
  NeedsReview: "utility:warning"
};

export default class WorkOrderParts extends LightningElement {
  @api recordId;

  labels = {
    LABEL_REFRESH,
    LABEL_PAID_TOTAL,
    LABEL_TOTAL_CHARGE,
    LABEL_NEEDS_APPROVAL,
    LABEL_COL_AUTO_CHARGE,
    LABEL_COL_OVERRIDE_REASON,
    LABEL_FINAL_CHARGE,
    BTN_SAVE,
    BTN_CANCEL,
    MSG_NO_PARTS,
    MSG_OVERRIDE_REASON_HINT
  };

  rows = [];
  paidTotal = 0;
  totalCharge = 0;
  needsApproval = false;
  canAdd = false;
  canEdit = false;
  lockMessage;
  chargeOptions = [];
  errorMessage;
  isLoading = true;
  wiredResult;

  editingRow;
  editChargeType;
  editReason;
  editError;
  isSaving = false;
  lastSeenModified;

  // DESC: 열은 줄마다 다른 작업 메뉴(수정 가능·삭제 가능)를 쓰므로 함수로 정함
  columns = [
    { label: LABEL_COL_PART, fieldName: "partText", wrapText: true },
    { label: LABEL_COL_QUANTITY, fieldName: "quantityText", initialWidth: 100 },
    {
      label: LABEL_COL_AUTO_CHARGE,
      fieldName: "autoChargeTypeLabel",
      initialWidth: 90
    },
    {
      label: LABEL_COL_CHARGE,
      fieldName: "chargeTypeLabel",
      initialWidth: 90,
      cellAttributes: { class: { fieldName: "chargeClass" } }
    },
    {
      label: LABEL_COL_OVERRIDE_REASON,
      fieldName: "overrideReason",
      wrapText: true
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
      initialWidth: 130
    },
    {
      type: "action",
      typeAttributes: {
        rowActions: (row, done) => done(this.rowActionsOf(row))
      }
    }
  ];

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
      this.canEdit = data.canEdit;
      this.lockMessage = data.lockMessage;
      this.chargeOptions = data.chargeOptions || [];
      if (data.locked) {
        this.closeEditor();
      }
      this.errorMessage = undefined;
      this.isLoading = false;
    } else if (error) {
      this.errorMessage = reduceErrors(error).join(", ");
      this.rows = [];
      this.isLoading = false;
      this.showToast(MSG_LOAD_ERROR, this.errorMessage, "error");
    }
  }

  // DESC: 같은 페이지의 다른 곳(표준 편집·[승인 요청]·승인 결과)이 출동을 바꾸면 목록·잠김 상태를 다시 읽음
  @wire(getRecord, {
    recordId: "$recordId",
    fields: [WO_STATUS, WO_LAST_MODIFIED]
  })
  wiredWorkOrder({ data }) {
    if (!data) {
      return;
    }
    const modified = getFieldValue(data, WO_LAST_MODIFIED);
    if (this.lastSeenModified && modified !== this.lastSeenModified) {
      refreshApex(this.wiredResult);
    }
    this.lastSeenModified = modified;
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

  get editTitle() {
    return this.editingRow
      ? LABEL_EDIT_CHARGE_TITLE.replace("{0}", this.editingRow.partText)
      : "";
  }

  rowActionsOf(row) {
    const actions = [];
    if (this.canEdit) {
      actions.push({ label: LABEL_ACTION_CHANGE_CHARGE, name: ACTION_EDIT });
    }
    if (row.canDelete) {
      actions.push({ label: LABEL_ACTION_DELETE_PART, name: ACTION_DELETE });
    }
    return actions;
  }

  handleRowAction(event) {
    const { action, row } = event.detail;
    if (action.name === ACTION_EDIT) {
      this.editingRow = row;
      this.editChargeType = row.chargeType;
      this.editReason = row.overrideReason;
      this.editError = undefined;
    } else if (action.name === ACTION_DELETE) {
      this.confirmDelete(row);
    }
  }

  handleEditChargeChange(event) {
    this.editChargeType = event.detail.value;
  }

  handleEditReasonChange(event) {
    this.editReason = event.detail.value;
  }

  handleEditCancel() {
    this.closeEditor();
  }

  // DESC: 검증 규칙(변경 사유 필수 등) 오류는 서버 문구 그대로 편집 칸 아래와 토스트에
  async handleEditSave() {
    this.isSaving = true;
    this.editError = undefined;
    try {
      await updateChargeType({
        partId: this.editingRow.id,
        chargeType: this.editChargeType,
        reason: this.editReason
      });
      this.closeEditor();
      await this.refreshAll();
      this.showToast(MSG_PART_UPDATED, "", "success");
    } catch (error) {
      this.editError = reduceErrors(error).join(", ");
      this.showToast(LABEL_ACTION_CHANGE_CHARGE, this.editError, "error");
    } finally {
      this.isSaving = false;
    }
  }

  async confirmDelete(row) {
    const ok = await LightningConfirm.open({
      message: MSG_PART_DELETE_CONFIRM.replace("{0}", row.partText),
      variant: "header",
      theme: "warning",
      label: LABEL_ACTION_DELETE_PART
    });
    if (!ok) {
      return;
    }
    try {
      await deletePart({ partId: row.id });
      if (this.editingRow && this.editingRow.id === row.id) {
        this.closeEditor();
      }
      await this.refreshAll();
      this.showToast(MSG_PART_DELETED, "", "success");
    } catch (error) {
      this.showToast(
        LABEL_ACTION_DELETE_PART,
        reduceErrors(error).join(", "),
        "error"
      );
    }
  }

  closeEditor() {
    this.editingRow = undefined;
    this.editChargeType = undefined;
    this.editReason = undefined;
    this.editError = undefined;
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
    // DESC: 출동의 롤업(부품비 합계·예외 무상 수)·수식(총 청구액·승인 필요)이 바뀜 → 같은 페이지의 머리글·세부 사항(LDS)에도 알림
    await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    // DESC: 삭제하면 차량 재고가 되돌아오므로 부품 추가 선택지(남은 수량)도 다시 읽음
    const addForm = this.template.querySelector("c-part-add-form");
    if (addForm) {
      await addForm.refreshStock();
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
