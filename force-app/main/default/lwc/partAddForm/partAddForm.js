/**
 * @description 출동 사용 부품 화면의 자식 — 담당 기사 차량 재고에서 부품과 수량을 골라 저장만 함
 *              저장이 끝나면 부모에게 partadded 이벤트(detail: { partId })를 올리고, 목록·합계 갱신은 부모가 책임
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 데이터 방식
 *   - 재고 선택지: @wire Apex (WorkOrderPartsController.getVanStock) — 출동 Id만으로 정해지는 조회
 *   - 저장: imperative Apex (addPart) — 사용자가 "추가"를 눌렀을 때, DML이라 cacheable 불가
 * 자식 → 부모: CustomEvent('partadded'). bubbles 기본값(false) — 바로 위 부모만 받으면 충분
 *   detail에는 새 Id만 담음. 유·무상 판정은 트리거가 하므로 부모가 저장된 결과를 다시 읽어야 정확
 * ----------------------------------------------------------------------------
 * @see workOrderParts, WorkOrderPartsController, docs/d7_lwc_memo.md 3절
 */
import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";
import getVanStock from "@salesforce/apex/WorkOrderPartsController.getVanStock";
import addPart from "@salesforce/apex/WorkOrderPartsController.addPart";
import { reduceErrors } from "c/ldsUtils";

import LABEL_PART_ADD_TITLE from "@salesforce/label/c.LABEL_PART_ADD_TITLE";
import LABEL_STOCK from "@salesforce/label/c.LABEL_STOCK";
import LABEL_QUANTITY from "@salesforce/label/c.LABEL_QUANTITY";
import LABEL_STOCK_OPTION from "@salesforce/label/c.LABEL_STOCK_OPTION";
import BTN_ADD_PART from "@salesforce/label/c.BTN_ADD_PART";
import MSG_NO_VAN_STOCK from "@salesforce/label/c.MSG_NO_VAN_STOCK";
import MSG_PART_SELECT_REQUIRED from "@salesforce/label/c.MSG_PART_SELECT_REQUIRED";
import MSG_QUANTITY_INVALID from "@salesforce/label/c.MSG_QUANTITY_INVALID";
import MSG_LOAD_ERROR from "@salesforce/label/c.MSG_LOAD_ERROR";
import MSG_SAVE_ERROR from "@salesforce/label/c.MSG_SAVE_ERROR";

export default class PartAddForm extends LightningElement {
  @api workOrderId;

  labels = {
    LABEL_PART_ADD_TITLE,
    LABEL_STOCK,
    BTN_ADD_PART,
    MSG_NO_VAN_STOCK,
    MSG_PART_SELECT_REQUIRED,
    MSG_QUANTITY_INVALID
  };

  stock = [];
  stockLoaded = false;
  selectedItemId;
  quantity = 1;
  isSaving = false;
  wiredStockResult;

  @wire(getVanStock, { workOrderId: "$workOrderId" })
  wiredStock(result) {
    this.wiredStockResult = result;
    const { data, error } = result;
    if (data) {
      this.stock = data;
      this.stockLoaded = true;
    } else if (error) {
      this.stock = [];
      this.stockLoaded = true;
      this.showToast(MSG_LOAD_ERROR, reduceErrors(error).join(", "), "error");
    }
  }

  get stockOptions() {
    return this.stock.map((item) => ({
      label: LABEL_STOCK_OPTION.replace("{0}", item.partName)
        .replace("{1}", item.partCode || "-")
        .replace("{2}", item.quantityOnHand)
        .replace("{3}", item.unitLabel),
      value: item.productItemId
    }));
  }

  get hasNoStock() {
    return this.stockLoaded && this.stock.length === 0;
  }

  // DESC: 고른 재고의 단위를 수량 칸 이름에 붙임 ("수량 (kg)")
  get quantityLabel() {
    const selected = this.stock.find(
      (item) => item.productItemId === this.selectedItemId
    );
    return selected?.unitLabel
      ? `${LABEL_QUANTITY} (${selected.unitLabel})`
      : LABEL_QUANTITY;
  }

  handleStockChange(event) {
    this.selectedItemId = event.detail.value;
  }

  handleQuantityChange(event) {
    this.quantity = event.target.value;
  }

  async handleAdd() {
    // DESC: 필수·범위 검사는 Base Component에 맡기고, 서버에서도 한 번 더 검사(addPart)
    const inputs = [
      ...this.template.querySelectorAll("lightning-combobox, lightning-input")
    ];
    const valid = inputs.every((input) => input.reportValidity());
    if (!valid) {
      return;
    }
    this.isSaving = true;
    try {
      const partId = await addPart({
        workOrderId: this.workOrderId,
        productItemId: this.selectedItemId,
        quantity: Number(this.quantity)
      });
      this.selectedItemId = undefined;
      this.quantity = 1;
      // DESC: 보유 수량이 줄었으므로 선택지도 다시 읽음
      await refreshApex(this.wiredStockResult);
      this.dispatchEvent(new CustomEvent("partadded", { detail: { partId } }));
    } catch (error) {
      this.showToast(MSG_SAVE_ERROR, reduceErrors(error).join(", "), "error");
    } finally {
      this.isSaving = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
