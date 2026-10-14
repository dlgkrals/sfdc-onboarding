/**
 * @description 고객사(Account) "새로 만들기" 재정의 화면 — 레코드 유형별 필드 + 청구지 도로명주소 검색
 *              Aura 래퍼 accountNewOverride가 감싸서 표준 New 버튼(데스크톱)을 대신함 (LWC는 직접 재정의 불가)
 *              - 표준 레코드 유형 선택 화면에서 고른 유형을 래퍼가 넘겨줌 (없으면 사용자 기본 유형)
 *              - 개인(Individual)은 사업자번호를 숨김. 형식·대리점 규칙 등은 기존 검증 규칙이 그대로 검사
 *              - 청구지: 국가 KR, 시도 비움, 시 = 시군구, 번지 = 도로명주소(+상세주소, 참고항목) — 빠른 작업 "주소 검색"과 같은 규칙
 *              - 저장 → 새 레코드로 이동, 취소 → 고객사 목록, 오류 → 토스트
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-14
 * ----------------------------------------------------------------------------
 * 데이터 방식
 *   - 입력·저장: lightning-record-edit-form (LDS) — 레코드 유형별 선택 목록 값·검증 규칙·권한 그대로
 *   - 기본 레코드 유형·유형 표시 이름: LDS @wire getObjectInfo
 *   - 유형 API 이름: @wire Apex AccountNewController.getRecordTypeDeveloperName (getObjectInfo에는 API 이름이 없음)
 *   - 주소 검색: 자식 addressSearch (addressselected 이벤트)
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 1.0  2026-10-14  Edwin  최초 작성 (D8 새로 만들기 재정의)
 * 1.1  2026-10-14  Edwin  저장·취소로 나갈 때 입력값·주소·고른 유형 초기화 (재정의 화면이 캐시돼 이전 값이 남던 결함)
 * ----------------------------------------------------------------------------
 * @see accountNewOverride (Aura), addressSearch, AccountNewController
 */
import { LightningElement, api, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getRecordTypeDeveloperName from "@salesforce/apex/AccountNewController.getRecordTypeDeveloperName";

import ACCOUNT_OBJECT from "@salesforce/schema/Account";
import LABEL_ACCOUNT_NEW_TITLE from "@salesforce/label/c.LABEL_ACCOUNT_NEW_TITLE";
import LABEL_RECORD_TYPE from "@salesforce/label/c.LABEL_RECORD_TYPE";
import LABEL_ACCOUNT_INFO from "@salesforce/label/c.LABEL_ACCOUNT_INFO";
import LABEL_CONTACT_INFO from "@salesforce/label/c.LABEL_CONTACT_INFO";
import LABEL_BILLING_ADDRESS from "@salesforce/label/c.LABEL_BILLING_ADDRESS";
import LABEL_SELECTED_ADDRESS from "@salesforce/label/c.LABEL_SELECTED_ADDRESS";
import LABEL_DETAIL_ADDRESS from "@salesforce/label/c.LABEL_DETAIL_ADDRESS";
import LABEL_POSTAL_CODE from "@salesforce/label/c.LABEL_POSTAL_CODE";
import MSG_ADDRESS_LATER from "@salesforce/label/c.MSG_ADDRESS_LATER";
import MSG_ACCOUNT_CREATED from "@salesforce/label/c.MSG_ACCOUNT_CREATED";
import MSG_SAVE_ERROR from "@salesforce/label/c.MSG_SAVE_ERROR";
import BTN_CANCEL from "@salesforce/label/c.BTN_CANCEL";
import BTN_SAVE from "@salesforce/label/c.BTN_SAVE";
import BTN_RESELECT from "@salesforce/label/c.BTN_RESELECT";

const RT_INDIVIDUAL = "Individual";
const COUNTRY_KOREA = "KR";

export default class AccountNew extends NavigationMixin(LightningElement) {
  // DESC: 레코드 유형 Id — 표준 유형 선택 화면을 거치면 주소 상태(state.recordTypeId)로 들어옴
  //       래퍼가 넘기거나(@api) 이 컴포넌트가 CurrentPageReference로 직접 읽음.
  //       주소로 바로 열어 유형이 없으면 화면에서 먼저 고르게 함 (마스터 유형 고객사가 생기지 않게)
  @api recordTypeId;
  pageRecordTypeId;
  chosenRecordTypeId;
  typeOptions = [];

  labels = {
    LABEL_RECORD_TYPE,
    LABEL_ACCOUNT_INFO,
    LABEL_CONTACT_INFO,
    LABEL_BILLING_ADDRESS,
    LABEL_SELECTED_ADDRESS,
    LABEL_DETAIL_ADDRESS,
    LABEL_POSTAL_CODE,
    MSG_ADDRESS_LATER,
    BTN_CANCEL,
    BTN_SAVE,
    BTN_RESELECT
  };

  recordTypeLabelById = {};
  recordTypeDeveloperName;
  selected;
  detailAddress = "";
  isSaving = false;

  @wire(getObjectInfo, { objectApiName: ACCOUNT_OBJECT })
  wiredInfo({ data }) {
    if (data) {
      const labels = {};
      const options = [];
      Object.values(data.recordTypeInfos).forEach((info) => {
        labels[info.recordTypeId] = info.name;
        if (info.available && !info.master) {
          options.push({ label: info.name, value: info.recordTypeId });
        }
      });
      this.recordTypeLabelById = labels;
      this.typeOptions = options;
    }
  }

  @wire(getRecordTypeDeveloperName, { recordTypeId: "$effectiveRecordTypeId" })
  wiredDeveloperName({ data }) {
    this.recordTypeDeveloperName = data;
  }

  @wire(CurrentPageReference)
  setPageReference(pageRef) {
    this.pageRecordTypeId = pageRef?.state?.recordTypeId;
  }

  // DESC: 넘겨받은 유형 → 화면에서 고른 유형 → 고를 수 있는 유형이 하나뿐이면 그 유형
  get effectiveRecordTypeId() {
    return (
      this.recordTypeId ||
      this.pageRecordTypeId ||
      this.chosenRecordTypeId ||
      (this.typeOptions.length === 1 ? this.typeOptions[0].value : undefined)
    );
  }

  get hasRecordType() {
    return !!this.effectiveRecordTypeId;
  }

  get showTypeChoice() {
    return !this.hasRecordType && this.typeOptions.length > 1;
  }

  handleTypeChange(event) {
    this.chosenRecordTypeId = event.detail.value;
  }

  // DESC: 제목에 고른 유형 표시 ("고객사 등록 · 법인")
  get title() {
    const label = this.recordTypeLabelById[this.effectiveRecordTypeId];
    return label
      ? `${LABEL_ACCOUNT_NEW_TITLE} · ${label}`
      : LABEL_ACCOUNT_NEW_TITLE;
  }

  // DESC: 개인은 사업자번호 없음. 유형을 아직 모르면(조회 중) 보여 둠
  get showBusinessNumber() {
    return this.recordTypeDeveloperName !== RT_INDIVIDUAL;
  }

  get hasSelected() {
    return !!this.selected;
  }

  // DESC: 번지 = 도로명주소(참고항목 제외) + ", 상세주소" + " 참고항목" (빠른 작업과 같은 규칙)
  get billingStreet() {
    const { roadAddressPart1, roadAddressNote } = this.selected;
    const detail = this.detailAddress.trim();
    return [roadAddressPart1 + (detail ? `, ${detail}` : ""), roadAddressNote]
      .filter(Boolean)
      .join(" ");
  }

  handleAddressSelected(event) {
    this.selected = event.detail;
  }

  handleReselect() {
    this.selected = undefined;
  }

  handleDetailChange(event) {
    this.detailAddress = event.target.value || "";
  }

  handleSubmit(event) {
    event.preventDefault();
    const fields = { ...event.detail.fields };
    if (this.selected) {
      Object.assign(fields, {
        BillingCountryCode: COUNTRY_KOREA,
        BillingCity: this.selected.sigungu,
        BillingStreet: this.billingStreet,
        BillingPostalCode: this.selected.postalCode
      });
    }
    this.isSaving = true;
    this.template.querySelector("lightning-record-edit-form").submit(fields);
  }

  handleSuccess(event) {
    this.isSaving = false;
    this.toast(MSG_ACCOUNT_CREATED, "", "success");
    this.resetForm();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId: event.detail.id, actionName: "view" }
    });
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

  handleCancel() {
    this.resetForm();
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: { objectApiName: "Account", actionName: "home" }
    });
  }

  // DESC: 화면을 처음 상태로 — 재정의 화면은 나갔다 와도 컴포넌트가 재사용될 수 있음(Aura 래퍼도 다시 그림)
  resetForm() {
    this.selected = undefined;
    this.detailAddress = "";
    this.chosenRecordTypeId = undefined;
    this.isSaving = false;
    this.template
      .querySelectorAll("lightning-input-field")
      .forEach((field) => field.reset());
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
