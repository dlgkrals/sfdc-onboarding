/**
 * @description 가상 착신 시뮬레이터 (유틸리티 바 "가상 착신") — 실제 CTI 대신 착신 정보를 상담원이 직접 넣음
 *              발신 번호 → IVR 증상 → 시리얼 뒤 4자리(키패드) 또는 # → [전화 연결]
 *              → 발신자 찾기 + 장비 확정 판정 → 접수 작성 팝업 → 저장하면 새 접수로 이동
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-15
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 1.0  2026-10-15  Edwin  최초 작성 (CTI 가상 착신 시뮬레이터)
 * ----------------------------------------------------------------------------
 * 데이터 방식
 *   - 사용 가능 여부: @wire Apex (CallIntakeController.canCreateCase). 클래스 접근이 없는 사용자(기사 등)는
 *     호출이 실패 → 오류도 "사용 불가"로 처리
 *   - 판정: imperative Apex (matchCaller) — [전화 연결]을 눌렀을 때만
 *   - 증상 선택지: LDS getPicklistValues (접수 증상 유형 값 그대로)
 *   - 실제 운영은 Service Cloud Voice·Open CTI가 발신 번호를 넘겨 줌. 이 패널은 그 입력을 흉내 낼 뿐
 * ----------------------------------------------------------------------------
 * @see CallIntakeController, CallerMatchService, caseIntakeModal
 */
import { LightningElement, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import CASE_OBJECT from "@salesforce/schema/Case";
import SYMPTOM_FIELD from "@salesforce/schema/Case.SymptomType__c";
import canCreateCase from "@salesforce/apex/CallIntakeController.canCreateCase";
import matchCaller from "@salesforce/apex/CallIntakeController.matchCaller";
import CaseIntakeModal from "c/caseIntakeModal";
import { reduceErrors } from "c/ldsUtils";

import LABEL_CALLER_PHONE from "@salesforce/label/c.LABEL_CALLER_PHONE";
import MSG_CALLER_PHONE_PLACEHOLDER from "@salesforce/label/c.MSG_CALLER_PHONE_PLACEHOLDER";
import LABEL_IVR_SYMPTOM from "@salesforce/label/c.LABEL_IVR_SYMPTOM";
import LABEL_SERIAL_SUFFIX from "@salesforce/label/c.LABEL_SERIAL_SUFFIX";
import LABEL_SERIAL_UNKNOWN from "@salesforce/label/c.LABEL_SERIAL_UNKNOWN";
import LABEL_CASE_INTAKE_TITLE from "@salesforce/label/c.LABEL_CASE_INTAKE_TITLE";
import MSG_SERIAL_SUFFIX_HINT from "@salesforce/label/c.MSG_SERIAL_SUFFIX_HINT";
import MSG_SERIAL_INCOMPLETE from "@salesforce/label/c.MSG_SERIAL_INCOMPLETE";
import MSG_CALLER_PHONE_REQUIRED from "@salesforce/label/c.MSG_CALLER_PHONE_REQUIRED";
import MSG_CALL_NO_ACCESS from "@salesforce/label/c.MSG_CALL_NO_ACCESS";
import MSG_SELECT_PLACEHOLDER from "@salesforce/label/c.MSG_SELECT_PLACEHOLDER";
import MSG_CASE_CREATED from "@salesforce/label/c.MSG_CASE_CREATED";
import MSG_LOAD_ERROR from "@salesforce/label/c.MSG_LOAD_ERROR";
import BTN_CALL_CONNECT from "@salesforce/label/c.BTN_CALL_CONNECT";
import BTN_KEYPAD_BACK from "@salesforce/label/c.BTN_KEYPAD_BACK";

const SERIAL_LENGTH = 4;
const KEY_UNKNOWN = "#";
const KEY_BACK = "back";
// DESC: 전화 키패드 배열. 왼쪽 아래 ⌫(한 자리 지우기), 오른쪽 아래 #(시리얼 모름)
const KEYPAD_ROWS = [
  ["1", "2", "3"],
  ["4", "5", "6"],
  ["7", "8", "9"],
  [KEY_BACK, "0", KEY_UNKNOWN]
];

export default class CallSimulator extends NavigationMixin(LightningElement) {
  labels = {
    LABEL_CALLER_PHONE,
    MSG_CALLER_PHONE_PLACEHOLDER,
    LABEL_IVR_SYMPTOM,
    LABEL_SERIAL_SUFFIX,
    MSG_SERIAL_SUFFIX_HINT,
    MSG_CALL_NO_ACCESS,
    MSG_SELECT_PLACEHOLDER,
    BTN_CALL_CONNECT
  };

  accessChecked = false;
  hasAccess = false;
  callerPhone = "";
  symptom;
  symptomOptions = [];
  // DESC: 누른 숫자들, 또는 "#"(모름)
  serialInput = "";
  isConnecting = false;
  errorMessage;

  @wire(canCreateCase)
  wiredAccess({ data, error }) {
    if (data !== undefined) {
      this.hasAccess = data === true;
      this.accessChecked = true;
    } else if (error) {
      this.hasAccess = false;
      this.accessChecked = true;
    }
  }

  @wire(getObjectInfo, { objectApiName: CASE_OBJECT })
  caseInfo;

  @wire(getPicklistValues, {
    recordTypeId: "$caseInfo.data.defaultRecordTypeId",
    fieldApiName: SYMPTOM_FIELD
  })
  wiredSymptoms({ data }) {
    if (data) {
      this.symptomOptions = data.values.map((v) => ({
        label: v.label,
        value: v.value
      }));
    }
  }

  get showNoAccess() {
    return this.accessChecked && !this.hasAccess;
  }

  get showPanel() {
    return this.accessChecked && this.hasAccess;
  }

  get keypadRows() {
    return KEYPAD_ROWS.map((keys, rowIndex) => ({
      key: `row-${rowIndex}`,
      keys: keys.map((value) => ({
        value,
        label: value === KEY_BACK ? "⌫" : value,
        title: value === KEY_BACK ? BTN_KEYPAD_BACK : value
      }))
    }));
  }

  // DESC: "1 2 _ _" 처럼 남은 자리를 보여 줌. #이면 "모름 (#)"
  get serialDisplay() {
    if (this.serialInput === KEY_UNKNOWN) {
      return LABEL_SERIAL_UNKNOWN;
    }
    const digits = this.serialInput.split("");
    while (digits.length < SERIAL_LENGTH) {
      digits.push("_");
    }
    return digits.join(" ");
  }

  get isConnectDisabled() {
    return this.isConnecting;
  }

  handlePhoneChange(event) {
    this.callerPhone = event.detail.value;
  }

  handleSymptomChange(event) {
    this.symptom = event.detail.value;
  }

  handleKey(event) {
    const value = event.currentTarget.dataset.value;
    this.errorMessage = undefined;
    if (value === KEY_BACK) {
      this.serialInput =
        this.serialInput === KEY_UNKNOWN ? "" : this.serialInput.slice(0, -1);
    } else if (value === KEY_UNKNOWN) {
      this.serialInput = KEY_UNKNOWN;
    } else if (this.serialInput === KEY_UNKNOWN) {
      this.serialInput = value;
    } else if (this.serialInput.length < SERIAL_LENGTH) {
      this.serialInput += value;
    }
  }

  async handleConnect() {
    const phoneInput = this.template.querySelector(".caller-phone");
    if (!this.callerPhone || !this.callerPhone.trim()) {
      phoneInput.setCustomValidity(MSG_CALLER_PHONE_REQUIRED);
      phoneInput.reportValidity();
      return;
    }
    phoneInput.setCustomValidity("");
    phoneInput.reportValidity();
    // DESC: 4자리를 다 누르거나 #(모름). 아무것도 안 눌렀으면 모름으로 봄
    if (
      this.serialInput !== KEY_UNKNOWN &&
      this.serialInput.length > 0 &&
      this.serialInput.length < SERIAL_LENGTH
    ) {
      this.errorMessage = MSG_SERIAL_INCOMPLETE;
      return;
    }

    this.isConnecting = true;
    this.errorMessage = undefined;
    try {
      const intake = await matchCaller({
        callerPhone: this.callerPhone,
        serialSuffix: this.serialInput || KEY_UNKNOWN
      });
      const result = await CaseIntakeModal.open({
        size: "medium",
        label: LABEL_CASE_INTAKE_TITLE,
        intake,
        symptomType: this.symptom
      });
      if (result?.caseId) {
        this.dispatchEvent(
          new ShowToastEvent({ title: MSG_CASE_CREATED, variant: "success" })
        );
        this.resetCall();
        this[NavigationMixin.Navigate]({
          type: "standard__recordPage",
          attributes: {
            recordId: result.caseId,
            objectApiName: "Case",
            actionName: "view"
          }
        });
      }
    } catch (error) {
      this.errorMessage = `${MSG_LOAD_ERROR}: ${reduceErrors(error).join(", ")}`;
    } finally {
      this.isConnecting = false;
    }
  }

  // DESC: 저장한 통화만 비움. 팝업을 취소하면 입력을 남겨 다시 연결할 수 있게 (취소한 통화는 기록 없음)
  resetCall() {
    this.callerPhone = "";
    this.symptom = undefined;
    this.serialInput = "";
  }
}
