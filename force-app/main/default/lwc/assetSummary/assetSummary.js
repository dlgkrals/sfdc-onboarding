/**
 * @description 장비 요약 — 보증 상태·반복 고장·접수 이력 5건을 짧게 (장비 요약 팝업, 접수 작성 팝업 "장비 요약 보기")
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-15
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 1.0  2026-10-15  Edwin  최초 작성 (CTI 가상 착신 시뮬레이터)
 * 1.1  2026-10-15  Edwin  모델 없는 장비에 "모델 미지정" 배지 (피드백 개선 ④)
 * ----------------------------------------------------------------------------
 * 데이터 방식
 *   - 필드 표시: LDS (lightning-record-view-form) — 권한 없는 필드는 표시되지 않음
 *   - 배지·반복 고장 경고: LDS @wire(getRecord, optionalFields) — 값이 JS에 필요. 읽기 권한 없는 필드는 빠질 뿐 오류 아님
 *   - 접수 이력: 기존 assetRecentCases 재사용 (@wire AssetDetailController)
 *   - LightningModal 안에서 또 모달을 열지 않도록(중첩 모달) 내용만 컴포넌트로 분리
 * ----------------------------------------------------------------------------
 * @see assetSummaryModal, caseIntakeModal, assetRecentCases, assetDetail
 */
import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";

import SERIAL_KEY_FIELD from "@salesforce/schema/Asset.SerialKey__c";
import WARRANTY_STATUS_FIELD from "@salesforce/schema/Asset.fmWarrantyStatus__c";
import REPEAT_FAILURE_FIELD from "@salesforce/schema/Asset.RepeatFailure__c";
import RECENT_CASE_COUNT_FIELD from "@salesforce/schema/Asset.RecentCaseCount__c";
import PRODUCT2_FIELD from "@salesforce/schema/Asset.Product2Id";

import MSG_REPEAT_FAILURE_WARNING from "@salesforce/label/c.MSG_REPEAT_FAILURE_WARNING";
import LABEL_MODEL_UNSPECIFIED from "@salesforce/label/c.LABEL_MODEL_UNSPECIFIED";

// DESC: assetDetail과 같은 배지 색 (보증 상태 Formula 값 기준)
const BADGE_CLASS_BY_STATUS = {
  "보증 중": "slds-theme_success",
  "부분 보증": "slds-theme_warning",
  "보증 만료": "slds-theme_error"
};

export default class AssetSummary extends LightningElement {
  @api assetId;

  summaryFields = [
    "Product2Id",
    "AccountId",
    "CustomerSite__c",
    "InstallDate",
    "fmWarrantyStatus__c",
    "fmWarrantyStartDate__c",
    "LastCaseDate__c",
    "RecentCaseCount__c"
  ];

  asset;
  labels = { LABEL_MODEL_UNSPECIFIED };

  @wire(getRecord, {
    recordId: "$assetId",
    optionalFields: [
      SERIAL_KEY_FIELD,
      WARRANTY_STATUS_FIELD,
      REPEAT_FAILURE_FIELD,
      RECENT_CASE_COUNT_FIELD,
      PRODUCT2_FIELD
    ]
  })
  wiredAsset({ data }) {
    this.asset = data;
  }

  get serialKey() {
    return this.asset ? getFieldValue(this.asset, SERIAL_KEY_FIELD) : "";
  }

  get warrantyStatus() {
    return this.asset ? getFieldValue(this.asset, WARRANTY_STATUS_FIELD) : null;
  }

  // DESC: 모델 칸이 비면 표준 출력 칸은 빈칸 → 눈에 띄게 배지로
  get isModelMissing() {
    return this.asset ? !getFieldValue(this.asset, PRODUCT2_FIELD) : false;
  }

  get badgeClass() {
    return BADGE_CLASS_BY_STATUS[this.warrantyStatus] || "";
  }

  get repeatFailure() {
    return this.asset
      ? getFieldValue(this.asset, REPEAT_FAILURE_FIELD) === true
      : false;
  }

  get repeatMessage() {
    const count = this.asset
      ? getFieldValue(this.asset, RECENT_CASE_COUNT_FIELD)
      : 0;
    return MSG_REPEAT_FAILURE_WARNING.replace("{0}", count ?? 0);
  }
}
