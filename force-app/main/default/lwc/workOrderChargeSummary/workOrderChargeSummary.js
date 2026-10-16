/**
 * @description 장비·고객사·사업장 화면 "최근 출동" 목록 위 요약 한 줄 — "누적 청구액 ₩N · 방문 출동 N건"
 *              값은 전체 출동 기준(출동 트리거가 저장한 TotalWorkOrderCharge__c·VisitedWorkOrderCount__c), 목록의 최근 5건 합이 아님
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-16
 * ----------------------------------------------------------------------------
 * 데이터 방식: LDS getRecord(레코드 페이지의 objectApiName으로 필드 이름을 만듦) — 필드 권한이 없으면 빈 값 → 카드 숨김
 * ----------------------------------------------------------------------------
 * @see WorkOrderChargeService
 */
import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";

import LABEL_CHARGE_SUMMARY from "@salesforce/label/c.LABEL_CHARGE_SUMMARY";
import LABEL_CHARGE_SUMMARY_NOTE from "@salesforce/label/c.LABEL_CHARGE_SUMMARY_NOTE";

const CURRENCY = new Intl.NumberFormat("ko-KR", {
  style: "currency",
  currency: "KRW",
  maximumFractionDigits: 0
});

export default class WorkOrderChargeSummary extends LightningElement {
  @api recordId;
  @api objectApiName;

  note = LABEL_CHARGE_SUMMARY_NOTE;
  record;

  get fields() {
    return this.objectApiName
      ? [
          `${this.objectApiName}.TotalWorkOrderCharge__c`,
          `${this.objectApiName}.VisitedWorkOrderCount__c`
        ]
      : [];
  }

  @wire(getRecord, { recordId: "$recordId", optionalFields: "$fields" })
  wiredRecord({ data }) {
    this.record = data;
  }

  get summary() {
    if (!this.record) {
      return null;
    }
    const total = getFieldValue(this.record, this.fields[0]);
    const count = getFieldValue(this.record, this.fields[1]);
    if (total == null && count == null) {
      return null;
    }
    return LABEL_CHARGE_SUMMARY.replace(
      "{0}",
      CURRENCY.format(total || 0)
    ).replace("{1}", count || 0);
  }
}
