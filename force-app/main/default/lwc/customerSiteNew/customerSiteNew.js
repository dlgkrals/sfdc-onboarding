/**
 * @description 사업장(CustomerSite__c) "새로 만들기" 재정의 화면 — 기본 정보 + 도로명주소 검색 + 서비스센터 자동 지정
 *              Aura 래퍼 customerSiteNewOverride가 감싸서 표준 New 버튼(데스크톱)을 대신함 (LWC는 직접 재정의 불가)
 *              - 고객사 관련 목록에서 열면 래퍼가 부모 고객사 Id를 넘겨 자동 입력
 *              - 주소 선택 → 매핑 센터를 미리 채움. 센터장·관리자는 바꿀 수 있음
 *              - 상담원은 센터 필드 수정 권한이 없어, 저장 직후 기존 Apex(saveSiteAddress)가 매핑 센터를 시스템 모드로 반영
 *              - 저장 → 새 레코드로 이동, 취소 → 원래 화면(고객사 또는 사업장 목록), 오류 → 토스트
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-14
 * ----------------------------------------------------------------------------
 * 데이터 방식
 *   - 입력·저장: lightning-record-edit-form (LDS) — 사용자 권한·검증 규칙 그대로, 필수·형식 검사도 표준
 *     onsubmit에서 주소 필드를 더해 submit(fields)
 *   - 센터 수정 권한: LDS @wire getObjectInfo (필드 createable)
 *   - 주소 검색: 자식 addressSearch (addressselected 이벤트, D7 빠른 작업과 같은 부품)
 * ----------------------------------------------------------------------------
 * @see customerSiteNewOverride (Aura), addressSearch, CustomerSiteAddressService, docs/decision-log.md
 */
import { LightningElement, api, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import saveSiteAddress from "@salesforce/apex/AddressSearchController.saveSiteAddress";
import { reduceErrors } from "c/ldsUtils";

import SITE_OBJECT from "@salesforce/schema/CustomerSite__c";
import LABEL_SITE_NEW_TITLE from "@salesforce/label/c.LABEL_SITE_NEW_TITLE";
import LABEL_SITE_INFO from "@salesforce/label/c.LABEL_SITE_INFO";
import LABEL_ADDRESS from "@salesforce/label/c.LABEL_ADDRESS";
import LABEL_SELECTED_ADDRESS from "@salesforce/label/c.LABEL_SELECTED_ADDRESS";
import LABEL_DETAIL_ADDRESS from "@salesforce/label/c.LABEL_DETAIL_ADDRESS";
import LABEL_POSTAL_CODE from "@salesforce/label/c.LABEL_POSTAL_CODE";
import MSG_ADDRESS_LATER from "@salesforce/label/c.MSG_ADDRESS_LATER";
import MSG_CENTER_AUTO from "@salesforce/label/c.MSG_CENTER_AUTO";
import MSG_CENTER_MANUAL from "@salesforce/label/c.MSG_CENTER_MANUAL";
import MSG_CENTER_AFTER_SAVE from "@salesforce/label/c.MSG_CENTER_AFTER_SAVE";
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
  // DESC: 부모 고객사 Id — 고객사 관련 목록에서 열면 주소 상태 inContextOfRef("1." + base64 JSON 페이지 참조)에 들어옴
  //       래퍼가 넘기거나(@api) 이 컴포넌트가 CurrentPageReference로 직접 읽음 (2026-10-14 실제 org: 관련 목록 → inContextOfRef 확인)
  @api parentAccountId;
  pageParentId;

  labels = {
    LABEL_SITE_NEW_TITLE,
    LABEL_SITE_INFO,
    LABEL_ADDRESS,
    LABEL_SELECTED_ADDRESS,
    LABEL_DETAIL_ADDRESS,
    LABEL_POSTAL_CODE,
    MSG_ADDRESS_LATER,
    BTN_CANCEL,
    BTN_SAVE,
    BTN_RESELECT
  };

  selected;
  detailAddress = "";
  serviceCenter;
  mappedCenter;
  centerCreateable = false;
  isSaving = false;

  @wire(CurrentPageReference)
  setPageReference(pageRef) {
    this.pageParentId = parentAccountIdFrom(pageRef?.state || {});
  }

  get effectiveParentId() {
    return this.parentAccountId || this.pageParentId;
  }

  @wire(getObjectInfo, { objectApiName: SITE_OBJECT })
  wiredInfo({ data }) {
    if (data) {
      this.centerCreateable = data.fields.ServiceCenter__c?.createable === true;
    }
  }

  get hasSelected() {
    return !!this.selected;
  }

  get centerMessage() {
    if (!this.centerCreateable) {
      return MSG_CENTER_AFTER_SAVE;
    }
    if (!this.selected) {
      return "";
    }
    return this.mappedCenter ? MSG_CENTER_AUTO : MSG_CENTER_MANUAL;
  }

  handleAddressSelected(event) {
    this.selected = event.detail;
    this.mappedCenter = event.detail.serviceCenter;
    // DESC: 매핑 센터를 미리 채움 (센터장·관리자는 저장 전에 바꿀 수 있음)
    if (this.mappedCenter) {
      this.serviceCenter = this.mappedCenter;
    }
  }

  handleReselect() {
    this.selected = undefined;
    this.mappedCenter = undefined;
  }

  handleDetailChange(event) {
    this.detailAddress = event.target.value || "";
  }

  handleCenterChange(event) {
    this.serviceCenter = event.detail.value;
  }

  // DESC: 표준 폼 값에 주소 필드를 더해 저장. 센터 권한이 없으면 센터는 빼고 저장 후 서버가 반영
  handleSubmit(event) {
    event.preventDefault();
    const fields = { ...event.detail.fields };
    if (this.selected) {
      const a = this.selected;
      Object.assign(fields, {
        RoadAddress__c: a.roadAddressPart1,
        RoadAddressNote__c: a.roadAddressNote,
        DetailAddress__c: this.detailAddress.trim(),
        PostalCode__c: a.postalCode,
        Sido__c: a.sido,
        Sigungu__c: a.sigungu,
        AdminDistrictCode__c: a.adminDistrictCode
      });
    }
    if (!this.centerCreateable) {
      delete fields.ServiceCenter__c;
    }
    this.isSaving = true;
    this.template.querySelector("lightning-record-edit-form").submit(fields);
  }

  async handleSuccess(event) {
    const siteId = event.detail.id;
    try {
      // DESC: 상담원 — 주소를 골랐으면 기존 규칙대로 서버가 매핑 센터를 시스템 모드로 반영
      if (this.selected && !this.centerCreateable) {
        await saveSiteAddress({ siteId, address: this.buildSiteAddress() });
      }
      this.toast(MSG_SITE_CREATED, "", "success");
    } catch (error) {
      // WARN: 사업장은 이미 저장됨. 센터 반영만 실패 → 알리고 새 레코드로 이동 (빠른 작업 "주소 검색"으로 다시 가능)
      this.toast(MSG_SAVE_ERROR, reduceErrors(error).join(", "), "warning");
    } finally {
      this.isSaving = false;
    }
    this.navigateToRecord(siteId);
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

  buildSiteAddress() {
    const a = this.selected;
    return {
      roadAddress: a.roadAddressPart1,
      roadAddressNote: a.roadAddressNote,
      detailAddress: this.detailAddress.trim(),
      postalCode: a.postalCode,
      sido: a.sido,
      sigungu: a.sigungu,
      adminDistrictCode: a.adminDistrictCode,
      serviceCenter: null
    };
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
