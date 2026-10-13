/**
 * @description SC-04 장비 상세 — 접수 전에 장비의 기본 정보·보증 상태·부품별 만료일·최근 접수를 한 화면에서 확인
 *              Asset 레코드 페이지에 배치 (recordId 자동 전달)
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 데이터 방식
 *   - 기본 정보·보증 필드: LDS (lightning-record-view-form) — 레코드 한 건 표시는 Apex 불필요.
 *     권한·캐시·다른 곳에서 레코드가 바뀌었을 때의 갱신을 Salesforce가 처리
 *   - 보증 상태 배지·집계 변화 감지: LDS @wire(getRecord) — 배지 색을 정하려면 값이 JS에 필요.
 *     장비 누적 접수 수가 바뀌면(새 접수 저장 → 트리거가 장비 집계) 자식 최근 접수를 refresh
 *   - 최근 접수: 자식 assetRecentCases가 @wire Apex로 조회
 * ----------------------------------------------------------------------------
 * @see assetRecentCases, AssetDetailController, docs/d6_screen_design.md SC-04
 */
import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { reduceErrors } from "c/ldsUtils";

import WARRANTY_STATUS_FIELD from "@salesforce/schema/Asset.fmWarrantyStatus__c";
import TOTAL_CASE_COUNT_FIELD from "@salesforce/schema/Asset.TotalCaseCount__c";
import LAST_CASE_DATE_FIELD from "@salesforce/schema/Asset.LastCaseDate__c";

import LABEL_ASSET_DETAIL_TITLE from "@salesforce/label/c.LABEL_ASSET_DETAIL_TITLE";
import LABEL_BASIC_INFO from "@salesforce/label/c.LABEL_BASIC_INFO";
import LABEL_WARRANTY_SECTION from "@salesforce/label/c.LABEL_WARRANTY_SECTION";
import MSG_LOAD_ERROR from "@salesforce/label/c.MSG_LOAD_ERROR";

const BADGE_CLASS_BY_STATUS = {
  "보증 중": "slds-theme_success",
  "부분 보증": "slds-theme_warning",
  "보증 만료": "slds-theme_error"
};

export default class AssetDetail extends LightningElement {
  @api recordId;
  @api objectApiName;

  labels = {
    LABEL_ASSET_DETAIL_TITLE,
    LABEL_BASIC_INFO,
    LABEL_WARRANTY_SECTION
  };

  // DESC: record-view-form에 그릴 필드 (화면 설계 SC-04 순서)
  basicFields = [
    "SerialKey__c",
    "Product2Id",
    "AccountId",
    "CustomerSite__c",
    "InstallDate",
    "SalesChannel__c",
    "TotalCaseCount__c",
    "LastCaseDate__c",
    "RecentCaseCount__c",
    "RepeatFailure__c"
  ];
  warrantyFields = [
    "fmWarrantyStartDate__c",
    "HasExtendedWarranty__c",
    "fmBasicWarrantyEndDate__c",
    "fmCompressorWarrantyEndDate__c",
    "fmExtendedWarrantyEndDate__c"
  ];

  warrantyStatus;
  lastStatsKey;

  @wire(getRecord, {
    recordId: "$recordId",
    fields: [
      WARRANTY_STATUS_FIELD,
      TOTAL_CASE_COUNT_FIELD,
      LAST_CASE_DATE_FIELD
    ]
  })
  wiredAsset({ data, error }) {
    if (data) {
      this.warrantyStatus = getFieldValue(data, WARRANTY_STATUS_FIELD);
      // DESC: 장비 집계가 바뀌었으면(새 접수·취소 등) 최근 접수 목록도 다시 가져옴. 첫 로드는 자식이 알아서 조회
      const statsKey = `${getFieldValue(data, TOTAL_CASE_COUNT_FIELD)}|${getFieldValue(data, LAST_CASE_DATE_FIELD)}`;
      if (this.lastStatsKey !== undefined && this.lastStatsKey !== statsKey) {
        this.template.querySelector("c-asset-recent-cases")?.refresh();
      }
      this.lastStatsKey = statsKey;
    } else if (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: MSG_LOAD_ERROR,
          message: reduceErrors(error).join(", "),
          variant: "error"
        })
      );
    }
  }

  get badgeClass() {
    return BADGE_CLASS_BY_STATUS[this.warrantyStatus] || "";
  }
}
