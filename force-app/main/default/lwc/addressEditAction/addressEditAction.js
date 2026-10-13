/**
 * @description 빠른 작업 "주소 검색" (사업장 CustomerSite__c · 고객사 Account 공용)
 *              공통 addressSearch로 주소 선택 → 상세주소 입력 → (사업장) 서비스센터 확인·변경 → 저장
 *              - 사업장: 도로명주소·참고항목·상세주소·우편번호·시도·시군구·행정구역 코드 + 서비스센터(매핑으로 미리 채움)
 *              - 고객사: 청구지 국가 KR, 시도 비움, 시 = 시군구, 번지 = 도로명주소(+상세주소), 우편번호
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 데이터 방식
 *   - 주소 검색: 자식 addressSearch (imperative Apex) → addressselected 이벤트로 받음 (자식→부모)
 *   - 현재 값·필드 수정 권한·서비스센터 선택지: LDS @wire (getRecord · getObjectInfo · getPicklistValues)
 *     레코드·메타데이터 읽기는 Apex 불필요, 사용자 권한(FLS) 정보도 같이 옴
 *   - 저장: LDS updateRecord (imperative) — 사용자가 저장을 눌렀을 때만, 사용자 권한·검증 규칙 그대로 적용
 * ----------------------------------------------------------------------------
 * @see addressSearch, AddressSearchController, ServiceCenterMappingService
 */
import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue, updateRecord } from "lightning/uiRecordApi";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import { CloseActionScreenEvent } from "lightning/actions";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { reduceErrors } from "c/ldsUtils";

import SITE_OBJECT from "@salesforce/schema/CustomerSite__c";
import SITE_CENTER_FIELD from "@salesforce/schema/CustomerSite__c.ServiceCenter__c";

import LABEL_ADDRESS_ACTION_TITLE from "@salesforce/label/c.LABEL_ADDRESS_ACTION_TITLE";
import LABEL_SELECTED_ADDRESS from "@salesforce/label/c.LABEL_SELECTED_ADDRESS";
import LABEL_DETAIL_ADDRESS from "@salesforce/label/c.LABEL_DETAIL_ADDRESS";
import LABEL_SERVICE_CENTER from "@salesforce/label/c.LABEL_SERVICE_CENTER";
import LABEL_POSTAL_CODE from "@salesforce/label/c.LABEL_POSTAL_CODE";
import MSG_CENTER_AUTO from "@salesforce/label/c.MSG_CENTER_AUTO";
import MSG_CENTER_MANUAL from "@salesforce/label/c.MSG_CENTER_MANUAL";
import MSG_CENTER_READONLY from "@salesforce/label/c.MSG_CENTER_READONLY";
import MSG_SELECT_ADDRESS_FIRST from "@salesforce/label/c.MSG_SELECT_ADDRESS_FIRST";
import MSG_ADDRESS_SAVED from "@salesforce/label/c.MSG_ADDRESS_SAVED";
import MSG_SAVE_ERROR from "@salesforce/label/c.MSG_SAVE_ERROR";
import BTN_CANCEL from "@salesforce/label/c.BTN_CANCEL";
import BTN_SAVE from "@salesforce/label/c.BTN_SAVE";
import BTN_RESELECT from "@salesforce/label/c.BTN_RESELECT";

const SITE = "CustomerSite__c";
const ACCOUNT = "Account";
const COUNTRY_KOREA = "KR";
// DESC: 사업장 참고항목 필드 길이 (RoadAddressNote__c Text(100))
const NOTE_MAX_LENGTH = 100;

export default class AddressEditAction extends LightningElement {
  @api recordId;
  @api objectApiName;

  labels = {
    LABEL_ADDRESS_ACTION_TITLE,
    LABEL_SELECTED_ADDRESS,
    LABEL_DETAIL_ADDRESS,
    LABEL_SERVICE_CENTER,
    LABEL_POSTAL_CODE,
    MSG_SELECT_ADDRESS_FIRST,
    BTN_CANCEL,
    BTN_SAVE,
    BTN_RESELECT
  };

  selected;
  detailAddress = "";
  serviceCenter;
  mappedCenter;
  centerOptions = [];
  centerUpdateable = false;
  isSaving = false;

  // DESC: 사업장의 현재 서비스센터 (매핑이 없을 때 기본값으로 유지)
  @wire(getRecord, { recordId: "$siteRecordId", fields: [SITE_CENTER_FIELD] })
  wiredSite;

  // DESC: 서비스센터 필드 수정 권한 확인 + picklist 조회용 레코드 유형
  @wire(getObjectInfo, { objectApiName: "$siteObjectApiName" })
  wiredSiteInfo({ data }) {
    if (data) {
      this.centerUpdateable = data.fields.ServiceCenter__c?.updateable === true;
      this.siteRecordTypeId = data.defaultRecordTypeId;
    }
  }

  siteRecordTypeId;

  @wire(getPicklistValues, {
    recordTypeId: "$siteRecordTypeId",
    fieldApiName: SITE_CENTER_FIELD
  })
  wiredCenters({ data }) {
    if (data) {
      this.centerOptions = data.values.map((v) => ({
        label: v.label,
        value: v.value
      }));
    }
  }

  get isSite() {
    return this.objectApiName === SITE;
  }

  // DESC: 사업장일 때만 사업장 관련 @wire가 돌도록 (고객사에서는 undefined → wire 대기)
  get siteRecordId() {
    return this.isSite ? this.recordId : undefined;
  }

  get siteObjectApiName() {
    return this.isSite ? SITE_OBJECT : undefined;
  }

  get hasSelected() {
    return !!this.selected;
  }

  get isSaveDisabled() {
    return !this.selected || this.isSaving;
  }

  get centerDisabled() {
    return !this.centerUpdateable;
  }

  get centerMessage() {
    if (!this.centerUpdateable) {
      const label =
        this.centerOptions.find((o) => o.value === this.mappedCenter)?.label ||
        "-";
      return MSG_CENTER_READONLY.replace("{0}", label);
    }
    return this.mappedCenter ? MSG_CENTER_AUTO : MSG_CENTER_MANUAL;
  }

  get previewAddress() {
    return this.isSite ? this.selected.roadAddress : this.accountStreet;
  }

  // DESC: 고객사 번지 = 도로명주소(참고항목 제외) + ", 상세주소" + " 참고항목"
  get accountStreet() {
    const { roadAddressPart1, roadAddressNote } = this.selected;
    const detail = this.detailAddress.trim();
    return [roadAddressPart1 + (detail ? `, ${detail}` : ""), roadAddressNote]
      .filter(Boolean)
      .join(" ");
  }

  handleAddressSelected(event) {
    this.selected = event.detail;
    this.mappedCenter = event.detail.serviceCenter;
    // DESC: 매핑이 있으면 미리 채움, 없으면 현재 값 유지 (사용자가 직접 선택)
    this.serviceCenter =
      this.mappedCenter ||
      getFieldValue(this.wiredSite?.data, SITE_CENTER_FIELD);
  }

  handleReselect() {
    this.selected = undefined;
  }

  handleDetailChange(event) {
    this.detailAddress = event.target.value || "";
  }

  handleCenterChange(event) {
    this.serviceCenter = event.detail.value;
  }

  handleCancel() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  async handleSave() {
    if (!this.selected) {
      return;
    }
    this.isSaving = true;
    try {
      await updateRecord({ fields: this.buildFields() });
      this.dispatchEvent(
        new ShowToastEvent({ title: MSG_ADDRESS_SAVED, variant: "success" })
      );
      this.dispatchEvent(new CloseActionScreenEvent());
    } catch (error) {
      // DESC: 검증 규칙·권한 오류도 그대로 보여 줌 (모달은 열어 둔 채 수정 가능)
      this.dispatchEvent(
        new ShowToastEvent({
          title: MSG_SAVE_ERROR,
          message: reduceErrors(error).join(", "),
          variant: "error"
        })
      );
    } finally {
      this.isSaving = false;
    }
  }

  buildFields() {
    const a = this.selected;
    const detail = this.detailAddress.trim();
    if (this.objectApiName === ACCOUNT) {
      return {
        Id: this.recordId,
        BillingCountryCode: COUNTRY_KOREA,
        BillingStateCode: null,
        BillingCity: a.sigungu,
        BillingStreet: this.accountStreet,
        BillingPostalCode: a.postalCode
      };
    }
    const fields = {
      Id: this.recordId,
      RoadAddress__c: a.roadAddressPart1,
      RoadAddressNote__c: a.roadAddressNote
        ? a.roadAddressNote.slice(0, NOTE_MAX_LENGTH)
        : null,
      DetailAddress__c: detail || null,
      PostalCode__c: a.postalCode,
      Sido__c: a.sido,
      Sigungu__c: a.sigungu,
      AdminDistrictCode__c: a.adminDistrictCode
    };
    // DESC: 서비스센터 수정 권한이 없는 사용자(상담원)는 주소만 저장 (센터는 센터장·관리자가 지정)
    if (this.centerUpdateable && this.serviceCenter) {
      fields.ServiceCenter__c = this.serviceCenter;
    }
    return fields;
  }
}
