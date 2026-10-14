/**
 * @description 사업장(CustomerSite__c) "새로 만들기" 재정의 화면 — 기본 정보 + 도로명주소 검색(필수) + 서비스센터 자동 지정
 *              Aura 래퍼 customerSiteNewOverride가 감싸서 표준 New 버튼(데스크톱)을 대신함 (LWC는 직접 재정의 불가)
 *              - 고객사 관련 목록에서 열면 주소 상태(inContextOfRef)의 부모 고객사를 자동 입력
 *              - 서비스센터는 누구도 고르지 않음: 주소를 고르면 지정될 센터를 보여 주고, 저장하면 트리거가 매핑으로 채움
 *              - 주소를 고르지 않거나 매핑 없는 주소면 저장 막음 (서버 트리거도 같은 규칙)
 *              - 저장 → 새 레코드로 이동, 취소 → 원래 화면(고객사 또는 사업장 목록), 오류 → 토스트
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-14
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 1.0  2026-10-14  Edwin  최초 작성 (D8 새로 만들기 재정의)
 * 1.1  2026-10-14  Edwin  센터 선택 칸 삭제 → 자동 지정 표시만, 주소 검색 필수, 저장 후 Apex 반영 단계 삭제 (D8 센터 완전 자동)
 * ----------------------------------------------------------------------------
 * 데이터 방식
 *   - 입력·저장: lightning-record-edit-form (LDS) — 사용자 권한·검증 규칙 그대로. onsubmit에서 주소 필드를 더해 submit(fields)
 *   - 센터 표시 이름: LDS @wire getObjectInfo · getPicklistValues
 *   - 주소 검색: 자식 addressSearch (addressselected 이벤트, 빠른 작업 "주소 검색"과 같은 부품)
 *   - 부모 고객사: CurrentPageReference (주소 상태를 직접 읽음)
 * ----------------------------------------------------------------------------
 * @see customerSiteNewOverride (Aura), addressSearch, CustomerSiteTriggerHandler, docs/decision-log.md
 */
import { LightningElement, api, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

import SITE_OBJECT from "@salesforce/schema/CustomerSite__c";
import SITE_CENTER_FIELD from "@salesforce/schema/CustomerSite__c.ServiceCenter__c";
import LABEL_SITE_NEW_TITLE from "@salesforce/label/c.LABEL_SITE_NEW_TITLE";
import LABEL_SITE_INFO from "@salesforce/label/c.LABEL_SITE_INFO";
import LABEL_ADDRESS from "@salesforce/label/c.LABEL_ADDRESS";
import LABEL_SELECTED_ADDRESS from "@salesforce/label/c.LABEL_SELECTED_ADDRESS";
import LABEL_DETAIL_ADDRESS from "@salesforce/label/c.LABEL_DETAIL_ADDRESS";
import LABEL_POSTAL_CODE from "@salesforce/label/c.LABEL_POSTAL_CODE";
import LABEL_SERVICE_CENTER from "@salesforce/label/c.LABEL_SERVICE_CENTER";
import MSG_ADDRESS_SEARCH_REQUIRED from "@salesforce/label/c.MSG_ADDRESS_SEARCH_REQUIRED";
import MSG_CENTER_ASSIGNED from "@salesforce/label/c.MSG_CENTER_ASSIGNED";
import MSG_CENTER_NO_MAPPING from "@salesforce/label/c.MSG_CENTER_NO_MAPPING";
import MSG_SITE_CREATED from "@salesforce/label/c.MSG_SITE_CREATED";
import MSG_SAVE_ERROR from "@salesforce/label/c.MSG_SAVE_ERROR";
import BTN_CANCEL from "@salesforce/label/c.BTN_CANCEL";
import BTN_SAVE from "@salesforce/label/c.BTN_SAVE";
import BTN_RESELECT from "@salesforce/label/c.BTN_RESELECT";

// DESC: 주소 상태에서 부모 고객사 Id ① inContextOfRef ② defaultFieldValues("Account__c=Id"). 고객사(001)만
function parentAccountIdFrom(state) {
  const context = state.inContextOfRef;
  if (context && context.startsWith("1.")) {
    try {
      const recordId = JSON.parse(atob(context.substring(2)))?.attributes
        ?.recordId;
      if (recordId && recordId.startsWith("001")) {
        return recordId;
      }
    } catch {
      // DESC: 형식이 다르면 부모 없이 (사용자가 고객사를 직접 고름)
      return undefined;
    }
  }
  const match = /Account__c=([a-zA-Z0-9]{15,18})/.exec(
    state.defaultFieldValues || ""
  );
  return match ? match[1] : undefined;
}

export default class CustomerSiteNew extends NavigationMixin(LightningElement) {
  // DESC: 부모 고객사 Id — 래퍼가 넘기거나(@api) 이 컴포넌트가 CurrentPageReference로 직접 읽음
  //       (2026-10-14 실제 org: 고객사 → 사업장 관련 목록 새로 만들기 → inContextOfRef에 부모 고객사 확인)
  @api parentAccountId;
  pageParentId;

  labels = {
    LABEL_SITE_NEW_TITLE,
    LABEL_SITE_INFO,
    LABEL_ADDRESS,
    LABEL_SELECTED_ADDRESS,
    LABEL_DETAIL_ADDRESS,
    LABEL_POSTAL_CODE,
    LABEL_SERVICE_CENTER,
    MSG_ADDRESS_SEARCH_REQUIRED,
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

  @wire(CurrentPageReference)
  setPageReference(pageRef) {
    this.pageParentId = parentAccountIdFrom(pageRef?.state || {});
  }

  @wire(getObjectInfo, { objectApiName: SITE_OBJECT })
  wiredInfo({ data }) {
    if (data) {
      this.siteRecordTypeId = data.defaultRecordTypeId;
    }
  }

  // DESC: 매핑 결과(API 값)를 화면 이름으로 보여 주기 위한 선택 목록
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

  get effectiveParentId() {
    return this.parentAccountId || this.pageParentId;
  }

  get hasSelected() {
    return !!this.selected;
  }

  get centerMessage() {
    if (!this.selected) {
      return MSG_ADDRESS_SEARCH_REQUIRED;
    }
    if (!this.mappedCenter) {
      return MSG_CENTER_NO_MAPPING;
    }
    const label =
      this.centerOptions.find((o) => o.value === this.mappedCenter)?.label ||
      this.mappedCenter;
    return MSG_CENTER_ASSIGNED.replace("{0}", label);
  }

  get centerMessageClass() {
    return this.selected && this.mappedCenter
      ? "slds-text-body_regular"
      : "slds-text-body_regular slds-text-color_error";
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

  // DESC: 표준 폼 값에 주소 필드를 더해 저장. 센터는 보내지 않음(트리거가 매핑으로 채움)
  //       주소 미선택·매핑 없음은 저장 전에 막음 (서버 트리거도 같은 규칙으로 거부)
  handleSubmit(event) {
    event.preventDefault();
    if (!this.selected || !this.mappedCenter) {
      this.toast(MSG_SAVE_ERROR, this.centerMessage, "error");
      return;
    }
    const a = this.selected;
    const fields = {
      ...event.detail.fields,
      RoadAddress__c: a.roadAddressPart1,
      RoadAddressNote__c: a.roadAddressNote,
      DetailAddress__c: this.detailAddress.trim(),
      PostalCode__c: a.postalCode,
      Sido__c: a.sido,
      Sigungu__c: a.sigungu,
      AdminDistrictCode__c: a.adminDistrictCode
    };
    delete fields.ServiceCenter__c;
    this.isSaving = true;
    this.template.querySelector("lightning-record-edit-form").submit(fields);
  }

  handleSuccess(event) {
    this.isSaving = false;
    this.toast(MSG_SITE_CREATED, "", "success");
    this.navigateToRecord(event.detail.id);
  }

  handleError(event) {
    this.isSaving = false;
    const detail = event.detail || {};
    this.toast(
      MSG_SAVE_ERROR,
      [detail.message, detail.detail].filter(Boolean).join(" "),
      "error"
    );
  }

  // DESC: 취소 → 관련 목록에서 열었으면 그 고객사로, 아니면 사업장 목록으로
  handleCancel() {
    if (this.effectiveParentId) {
      this.navigateToRecord(this.effectiveParentId);
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: { objectApiName: "CustomerSite__c", actionName: "home" }
    });
  }

  navigateToRecord(recordId) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId, actionName: "view" }
    });
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
