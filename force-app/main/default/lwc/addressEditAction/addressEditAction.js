/**
 * @description 빠른 작업 "주소 검색" (사업장 CustomerSite__c · 고객사 Account 공용)
 *              공통 addressSearch로 주소 선택 → 상세주소 입력 → 저장
 *              - 사업장: 도로명주소·참고항목·상세주소·우편번호·시도·시군구·행정구역 코드
 *                · 서비스센터는 누구도 고르지 않음: 주소 매핑으로 자동 지정(트리거). 화면은 지정될 센터를 보여 주기만 함
 *                · 매핑 없는 주소는 저장 버튼을 막고 "관리자에게 매핑 추가 요청" 안내 (D8 결정)
 *              - 고객사: 청구지 국가 KR, 시도 비움, 시 = 시군구, 번지 = 도로명주소(+상세주소), 우편번호
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 1.0  2026-10-13  Edwin  최초 작성
 * 1.1  2026-10-14  Edwin  사업장 센터 선택 칸 삭제 → 자동 지정 표시만, 매핑 없으면 저장 막음 (D8 센터 완전 자동)
 * ----------------------------------------------------------------------------
 * 데이터 방식
 *   - 주소 검색: 자식 addressSearch (imperative Apex) → addressselected 이벤트로 받음 (자식→부모)
 *   - 센터 표시 이름: LDS @wire (getObjectInfo · getPicklistValues) — 매핑 결과(API 값)를 화면 이름으로
 *   - 저장
 *     · 사업장: imperative Apex saveSiteAddress — 주소는 사용자 권한으로 저장, 센터는 트리거가 매핑으로 채움
 *       저장 후 notifyRecordUpdateAvailable로 레코드 화면 갱신
 *     · 고객사: LDS updateRecord — 사용자 권한·검증 규칙 그대로, Apex 불필요
 * ----------------------------------------------------------------------------
 * @see addressSearch, AddressSearchController, CustomerSiteAddressService, CustomerSiteTriggerHandler
 */
import { LightningElement, api, wire } from "lwc";
import {
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
import MSG_CENTER_ASSIGNED from "@salesforce/label/c.MSG_CENTER_ASSIGNED";
import MSG_CENTER_NO_MAPPING from "@salesforce/label/c.MSG_CENTER_NO_MAPPING";
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
  mappedCenter;
  centerOptions = [];
  siteRecordTypeId;
  isSaving = false;

  // DESC: 센터 표시 이름(picklist 라벨) 조회용 레코드 유형
  @wire(getObjectInfo, { objectApiName: "$siteObjectApiName" })
  wiredSiteInfo({ data }) {
    if (data) {
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
  get siteObjectApiName() {
    return this.isSite ? SITE_OBJECT : undefined;
  }

  get hasSelected() {
    return !!this.selected;
  }

  // DESC: 사업장은 매핑 없는 주소면 저장 불가 (서버 트리거도 같은 규칙으로 거부)
  get isSaveDisabled() {
    return (
      !this.selected || this.isSaving || (this.isSite && !this.mappedCenter)
    );
  }

  get centerMessage() {
    if (!this.mappedCenter) {
      return MSG_CENTER_NO_MAPPING;
    }
    const label =
      this.centerOptions.find((o) => o.value === this.mappedCenter)?.label ||
      this.mappedCenter;
    return MSG_CENTER_ASSIGNED.replace("{0}", label);
  }

  get centerMessageClass() {
    return this.mappedCenter
      ? "slds-text-body_regular"
      : "slds-text-body_regular slds-text-color_error";
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
  }

  handleReselect() {
    this.selected = undefined;
    this.mappedCenter = undefined;
  }

  handleDetailChange(event) {
    this.detailAddress = event.target.value || "";
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

  // DESC: 센터는 보내지 않음 — 서버 트리거가 행정구역 코드로 매핑
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
      serviceCenter: null
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
