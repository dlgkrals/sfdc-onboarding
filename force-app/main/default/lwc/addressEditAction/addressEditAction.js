/**
 * @description 빠른 작업 "주소 검색" (사업장 CustomerSite__c · 고객사 Account 공용)
 *              공통 addressSearch로 주소 선택 → 상세주소 입력 → (사업장) 서비스센터 확인 → 저장
 *              - 사업장: 도로명주소·참고항목·상세주소·우편번호·시도·시군구·행정구역 코드 + 서비스센터
 *                · 센터장·관리자: 매핑으로 미리 채운 센터를 바꿔서 저장 가능
 *                · 상담원: 센터는 고를 수 없고, 저장하면 서버가 주소 기준 매핑 센터를 시스템 모드로 반영
 *              - 고객사: 청구지 국가 KR, 시도 비움, 시 = 시군구, 번지 = 도로명주소(+상세주소), 우편번호
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 데이터 방식
 *   - 주소 검색: 자식 addressSearch (imperative Apex) → addressselected 이벤트로 받음 (자식→부모)
 *   - 현재 값·센터 수정 권한·센터 선택지: LDS @wire (getRecord · getObjectInfo · getPicklistValues)
 *     레코드·메타데이터 읽기는 Apex 불필요, 사용자 권한(FLS) 정보도 같이 옴
 *   - 저장
 *     · 사업장: imperative Apex saveSiteAddress — 상담원의 센터 반영은 시스템 모드가 필요해 LDS로는 불가
 *       저장 후 notifyRecordUpdateAvailable로 레코드 화면 갱신
 *     · 고객사: LDS updateRecord — 사용자 권한·검증 규칙 그대로, Apex 불필요
 * ----------------------------------------------------------------------------
 * @see addressSearch, AddressSearchController, CustomerSiteAddressService, ServiceCenterMappingService
 */
import { LightningElement, api, wire } from "lwc";
import {
  getRecord,
  getFieldValue,
  updateRecord,
  notifyRecordUpdateAvailable
} from "lightning/uiRecordApi";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import { CloseActionScreenEvent } from "lightning/actions";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import saveSiteAddress from "@salesforce/apex/AddressSearchController.saveSiteAddress";
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
import MSG_CENTER_READONLY_NONE from "@salesforce/label/c.MSG_CENTER_READONLY_NONE";
import MSG_SELECT_ADDRESS_FIRST from "@salesforce/label/c.MSG_SELECT_ADDRESS_FIRST";
import MSG_ADDRESS_SAVED from "@salesforce/label/c.MSG_ADDRESS_SAVED";
import MSG_SAVE_ERROR from "@salesforce/label/c.MSG_SAVE_ERROR";
import BTN_CANCEL from "@salesforce/label/c.BTN_CANCEL";
import BTN_SAVE from "@salesforce/label/c.BTN_SAVE";
import BTN_RESELECT from "@salesforce/label/c.BTN_RESELECT";

const SITE = "CustomerSite__c";
const ACCOUNT = "Account";
const COUNTRY_KOREA = "KR";

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
  siteRecordTypeId;
  isSaving = false;

  // DESC: 사업장의 현재 서비스센터 (매핑이 없을 때 기본값으로 표시)
  @wire(getRecord, { recordId: "$siteRecordId", fields: [SITE_CENTER_FIELD] })
  wiredSite;

  // DESC: 서비스센터 필드 수정 권한(센터장·관리자만) + picklist 조회용 레코드 유형
  @wire(getObjectInfo, { objectApiName: "$siteObjectApiName" })
  wiredSiteInfo({ data }) {
    if (data) {
      this.centerUpdateable = data.fields.ServiceCenter__c?.updateable === true;
      this.siteRecordTypeId = data.defaultRecordTypeId;
    }
  }

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
      if (!this.mappedCenter) {
        return MSG_CENTER_READONLY_NONE;
      }
      const label =
        this.centerOptions.find((o) => o.value === this.mappedCenter)?.label ||
        this.mappedCenter;
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
    // DESC: 매핑이 있으면 미리 채움, 없으면 현재 값 표시 (센터장·관리자는 바꿀 수 있음)
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
      if (this.isSite) {
        await saveSiteAddress({
          siteId: this.recordId,
          address: this.buildSiteAddress()
        });
        // DESC: Apex로 저장했으므로 LDS 캐시에 바뀌었다고 알려 레코드 화면을 갱신
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      } else if (this.objectApiName === ACCOUNT) {
        await updateRecord({ fields: this.buildAccountFields() });
      }
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

  // DESC: 센터 값은 센터장·관리자일 때만 서버가 사용. 상담원은 서버가 행정구역 코드로 다시 매핑
  buildSiteAddress() {
    const a = this.selected;
    return {
      roadAddress: a.roadAddressPart1,
      roadAddressNote: a.roadAddressNote,
      detailAddress: this.detailAddress,
      postalCode: a.postalCode,
      sido: a.sido,
      sigungu: a.sigungu,
      adminDistrictCode: a.adminDistrictCode,
      serviceCenter: this.centerUpdateable ? this.serviceCenter : null
    };
  }

  buildAccountFields() {
    const a = this.selected;
    return {
      Id: this.recordId,
      BillingCountryCode: COUNTRY_KOREA,
      BillingStateCode: null,
      BillingCity: a.sigungu,
      BillingStreet: this.accountStreet,
      BillingPostalCode: a.postalCode
    };
  }
}
