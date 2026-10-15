/**
 * @description 출동 사용 부품 화면의 자식 — 담당 기사 차량 재고에서 부품과 수량을 골라 저장만 함
 *              저장이 끝나면 부모에게 partadded 이벤트(detail: { partId })를 올리고, 목록·합계 갱신은 부모가 책임
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 1.0  2026-10-13  Edwin  최초 작성 (D7)
 * 1.1  2026-10-14  Edwin  재고 선택을 "부품 이름 · 위치 · 남은 수량(단위)" 목록으로, 남은 수량 0은 비활성 (D8)
 * 1.2  2026-10-14  Edwin  남은 수량보다 많이 쓰면 거부 (화면 + 서버, D8 결정)
 * 1.3  2026-10-15  Edwin  재고 목록 항목이 모두 선택 불가로 보이던 결함 수정 (disabled·selected에 false 대신 null)
 * ----------------------------------------------------------------------------
 * 데이터 방식
 *   - 재고 선택지: @wire Apex (WorkOrderPartsController.getVanStock, cacheable=true, with sharing + USER_MODE)
 *     출동 Id만으로 정해지는 조회라 wire가 맞음(값이 들어오면 자동 조회·캐시). 저장 뒤 남은 수량이 바뀌므로 refreshApex
 *     USER_MODE라 기사는 자기 차량 재고만, 서버가 "이 출동 담당 기사의 차량"으로 한 번 더 좁힘
 *   - 저장: imperative Apex (addPart) — 사용자가 "추가"를 눌렀을 때만, DML이라 cacheable 불가
 *   - 표준 조회 필드(재고 번호 PI0001 검색) 대신 목록: 기사는 재고 번호를 모르고, 다른 위치 재고를 고르는 실수를 막음
 *   - lightning-combobox는 항목별 비활성이 없어 SLDS select 사용 (남은 수량 0은 보이되 고를 수 없게)
 * ----------------------------------------------------------------------------
 * @see workOrderParts, WorkOrderPartsController, docs/d8_lwc_memo.md
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
import MISC_OUT_OF_STOCK from "@salesforce/label/c.MISC_OUT_OF_STOCK";
import BTN_ADD_PART from "@salesforce/label/c.BTN_ADD_PART";
import MSG_NO_VAN_STOCK from "@salesforce/label/c.MSG_NO_VAN_STOCK";
import MSG_PART_SELECT_REQUIRED from "@salesforce/label/c.MSG_PART_SELECT_REQUIRED";
import MSG_QUANTITY_INVALID from "@salesforce/label/c.MSG_QUANTITY_INVALID";
import MSG_STOCK_SHORT from "@salesforce/label/c.MSG_STOCK_SHORT";
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
  selectedItemId = "";
  stockError;
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

  // DESC: "부품 이름 · 위치 · 남은 수량(단위)". 남은 수량 0은 "재고 없음"을 붙이고 비활성
  get stockOptions() {
    return this.stock.map((item) => {
      const label = LABEL_STOCK_OPTION.replace("{0}", item.partName)
        .replace("{1}", item.locationName)
        .replace("{2}", item.quantityOnHand)
        .replace("{3}", item.unitLabel)
        .trim();
      return {
        label: item.available ? label : `${label} (${MISC_OUT_OF_STOCK})`,
        value: item.productItemId,
        // WARN: 일반 HTML <option>에 false를 바인딩하면 LWC가 disabled="false" 속성을 남겨 브라우저는 "선택 불가"로 봄
        //       (불리언 속성은 값과 상관없이 있으면 켜짐) → 끌 때는 null로 넘겨 속성 자체를 지움
        disabled: item.available ? null : true,
        selected: item.productItemId === this.selectedItemId ? true : null
      };
    });
  }

  get hasNoStock() {
    return this.stockLoaded && this.stock.length === 0;
  }

  get stockFieldClass() {
    return this.stockError
      ? "slds-form-element slds-has-error"
      : "slds-form-element";
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
    this.selectedItemId = event.target.value;
    this.stockError = undefined;
    this.clearShortage();
  }

  handleQuantityChange(event) {
    this.quantity = event.target.value;
    this.clearShortage();
  }

  clearShortage() {
    this.template.querySelector("lightning-input")?.setCustomValidity("");
  }

  // DESC: 남은 수량보다 많이 쓰면 "차량 재고가 부족합니다(남은 n단위)…" (서버 addPart도 같은 규칙으로 거부)
  //       정확히 남은 수량만큼은 허용
  shortageMessage() {
    const selected = this.stock.find(
      (item) => item.productItemId === this.selectedItemId
    );
    if (!selected || Number(this.quantity) <= selected.quantityOnHand) {
      return "";
    }
    return MSG_STOCK_SHORT.replace(
      "{0}",
      Number(selected.quantityOnHand)
    ).replace("{1}", selected.unitLabel);
  }

  async handleAdd() {
    // DESC: 재고 미선택은 직접, 수량 필수·범위는 Base Component, 재고 부족은 setCustomValidity. 서버(addPart)도 한 번 더 검사
    this.stockError = this.selectedItemId
      ? undefined
      : MSG_PART_SELECT_REQUIRED;
    const quantityInput = this.template.querySelector("lightning-input");
    if (quantityInput) {
      quantityInput.setCustomValidity(this.shortageMessage());
    }
    const quantityValid = quantityInput ? quantityInput.reportValidity() : true;
    if (this.stockError || !quantityValid) {
      return;
    }
    this.isSaving = true;
    try {
      const partId = await addPart({
        workOrderId: this.workOrderId,
        productItemId: this.selectedItemId,
        quantity: Number(this.quantity)
      });
      this.selectedItemId = "";
      this.quantity = 1;
      const select = this.template.querySelector("select");
      if (select) {
        select.value = "";
      }
      // DESC: 남은 수량이 줄었으므로 선택지도 다시 읽음 (0이 되면 비활성으로 바뀜)
      await refreshApex(this.wiredStockResult);
      // DESC: 자식 → 부모 이벤트. bubbles: false · composed: false (기본값)
      //       부모가 <c-part-add-form onpartadded={...}>로 이 요소에 직접 리스너를 달므로 위로 퍼질 필요가 없음.
      //       bubbles를 켜면 부모 template 안의 다른 요소에서도 보이고, composed를 켜면 그림자 DOM 경계를 넘어
      //       부모 바깥(레코드 페이지)까지 새어 나감 → 의도하지 않은 곳이 같은 이름 이벤트를 받을 수 있음
      this.dispatchEvent(
        new CustomEvent("partadded", {
          detail: { partId },
          bubbles: false,
          composed: false
        })
      );
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
