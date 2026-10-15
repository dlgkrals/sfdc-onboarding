/**
 * @description 접수 작성 팝업 — 가상 착신(발신자 판정 결과) 또는 장비 요약의 "이 장비로 접수"에서 열림
 *              팝업 규칙: 1건 → 채움, 여러 건 → 후보 목록, 없음 → 검색(lightning-record-picker)
 *              자동 저장 없음: 상담원이 요약·장비를 확인하고 [접수 저장]
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-15
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 1.0  2026-10-15  Edwin  최초 작성 (CTI 가상 착신 시뮬레이터)
 * 1.2  2026-10-15  Edwin  넓은 팝업 + 오른쪽 고객사·사업장 카드(intakeContextCards), 고른 장비의 진행 중 접수 경고(BR-11, 저장은 막지 않음, 새 탭으로 열기) (피드백 개선 ①③)
 * 1.1  2026-10-15  Edwin  제목 기본값 "{증상} · {사업장} · {시리얼}", 장비·사업장이 바뀌면 다시 만듦 (피드백 개선 ②)
 * ----------------------------------------------------------------------------
 * 데이터 방식
 *   - 판정 결과(intake)는 연 쪽이 넘김. 장비 모드(assetId만)는 열릴 때 getIntakeForAsset으로 같은 모양을 받음
 *   - 고객사·사업장을 바꾸면 imperative Apex로 후보 갱신 (사용자 동작마다 호출 시점을 정해야 해서 wire 아님)
 *   - 증상 선택지: LDS getPicklistValues (접수 증상 유형 값 그대로)
 *   - 저장: CallIntakeController.createCase (USER_MODE). 고객사·사업장은 저장하지 않고 저장 전 Flow가 장비로 채움
 *   - 닫을 때 결과: { caseId } (저장) / undefined (취소·X). 완료 토스트·새 접수로 이동은 연 쪽이 처리
 *     (모달 안에서 띄운 토스트는 모달과 함께 사라질 수 있어서)
 * ----------------------------------------------------------------------------
 * @see CallIntakeController, CallerMatchService, callSimulator, assetSearch, assetSummary
 */
import { api, wire } from "lwc";
import LightningModal from "lightning/modal";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import CASE_OBJECT from "@salesforce/schema/Case";
import SYMPTOM_FIELD from "@salesforce/schema/Case.SymptomType__c";
import getIntakeForAsset from "@salesforce/apex/CallIntakeController.getIntakeForAsset";
import getSiteCandidates from "@salesforce/apex/CallIntakeController.getSiteCandidates";
import getAssetCandidates from "@salesforce/apex/CallIntakeController.getAssetCandidates";
import createCase from "@salesforce/apex/CallIntakeController.createCase";
import getOpenCases from "@salesforce/apex/CallIntakeController.getOpenCases";
import { reduceErrors } from "c/ldsUtils";

import LABEL_CASE_INTAKE_TITLE from "@salesforce/label/c.LABEL_CASE_INTAKE_TITLE";
import LABEL_CALL_SUMMARY from "@salesforce/label/c.LABEL_CALL_SUMMARY";
import LABEL_CALLER_PHONE from "@salesforce/label/c.LABEL_CALLER_PHONE";
import LABEL_IVR_SYMPTOM from "@salesforce/label/c.LABEL_IVR_SYMPTOM";
import LABEL_SERIAL_SUFFIX from "@salesforce/label/c.LABEL_SERIAL_SUFFIX";
import LABEL_SERIAL_UNKNOWN from "@salesforce/label/c.LABEL_SERIAL_UNKNOWN";
import LABEL_COL_ACCOUNT from "@salesforce/label/c.LABEL_COL_ACCOUNT";
import LABEL_SITE from "@salesforce/label/c.LABEL_SITE";
import LABEL_ASSET from "@salesforce/label/c.LABEL_ASSET";
import LABEL_COL_SERIAL from "@salesforce/label/c.LABEL_COL_SERIAL";
import LABEL_COL_MODEL from "@salesforce/label/c.LABEL_COL_MODEL";
import LABEL_COL_SYMPTOM from "@salesforce/label/c.LABEL_COL_SYMPTOM";
import LABEL_SUBJECT from "@salesforce/label/c.LABEL_SUBJECT";
import LABEL_DESCRIPTION from "@salesforce/label/c.LABEL_DESCRIPTION";
import LABEL_SERIAL_MATCH from "@salesforce/label/c.LABEL_SERIAL_MATCH";
import LABEL_CALL_SUBJECT_PLAIN from "@salesforce/label/c.LABEL_CALL_SUBJECT_PLAIN";
import LABEL_CALL_DESCRIPTION from "@salesforce/label/c.LABEL_CALL_DESCRIPTION";
import BTN_ASSET_SUMMARY from "@salesforce/label/c.BTN_ASSET_SUMMARY";
import BTN_ASSET_SUMMARY_HIDE from "@salesforce/label/c.BTN_ASSET_SUMMARY_HIDE";
import BTN_SAVE_CASE from "@salesforce/label/c.BTN_SAVE_CASE";
import BTN_CANCEL from "@salesforce/label/c.BTN_CANCEL";
import MSG_MATCH_ONSITE from "@salesforce/label/c.MSG_MATCH_ONSITE";
import MSG_MATCH_SECONDARY from "@salesforce/label/c.MSG_MATCH_SECONDARY";
import MSG_MATCH_ACCOUNT from "@salesforce/label/c.MSG_MATCH_ACCOUNT";
import MSG_MATCH_NONE from "@salesforce/label/c.MSG_MATCH_NONE";
import MSG_OUTCOME_CONFIRMED from "@salesforce/label/c.MSG_OUTCOME_CONFIRMED";
import MSG_OUTCOME_SERIAL_CONFIRMED from "@salesforce/label/c.MSG_OUTCOME_SERIAL_CONFIRMED";
import MSG_OUTCOME_ASSET_CANDIDATES from "@salesforce/label/c.MSG_OUTCOME_ASSET_CANDIDATES";
import MSG_OUTCOME_SERIAL_CANDIDATES from "@salesforce/label/c.MSG_OUTCOME_SERIAL_CANDIDATES";
import MSG_OUTCOME_SITE_CANDIDATES from "@salesforce/label/c.MSG_OUTCOME_SITE_CANDIDATES";
import MSG_OUTCOME_ACCOUNT_CANDIDATES from "@salesforce/label/c.MSG_OUTCOME_ACCOUNT_CANDIDATES";
import MSG_SERIAL_NO_MATCH from "@salesforce/label/c.MSG_SERIAL_NO_MATCH";
import MSG_SELECT_PLACEHOLDER from "@salesforce/label/c.MSG_SELECT_PLACEHOLDER";
import MSG_SEARCH_RECORD from "@salesforce/label/c.MSG_SEARCH_RECORD";
import MSG_ASSET_SAVE_HINT from "@salesforce/label/c.MSG_ASSET_SAVE_HINT";
import MSG_LOAD_ERROR from "@salesforce/label/c.MSG_LOAD_ERROR";
import MSG_SAVE_ERROR from "@salesforce/label/c.MSG_SAVE_ERROR";
import MSG_OPEN_CASES_WARNING from "@salesforce/label/c.MSG_OPEN_CASES_WARNING";
import MSG_OPEN_CASES_MORE from "@salesforce/label/c.MSG_OPEN_CASES_MORE";
import BTN_OPEN_EXISTING_CASE from "@salesforce/label/c.BTN_OPEN_EXISTING_CASE";

// DESC: CallerMatchService 상수와 같게
const MATCHED_BY_MESSAGE = {
  ONSITE: MSG_MATCH_ONSITE,
  SECONDARY: MSG_MATCH_SECONDARY,
  ACCOUNT: MSG_MATCH_ACCOUNT
};
const OUTCOME_CONFIRMED = "CONFIRMED";
const OUTCOME_ASSET_CANDIDATES = "ASSET_CANDIDATES";
const OUTCOME_SITE_CANDIDATES = "SITE_CANDIDATES";
const OUTCOME_ACCOUNT_CANDIDATES = "ACCOUNT_CANDIDATES";
// DESC: CallIntakeController.SUBJECT_SEPARATOR와 같게
const SUBJECT_SEPARATOR = " · ";

const ASSET_COLUMNS = [
  {
    label: LABEL_COL_SERIAL,
    fieldName: "serialKey",
    cellAttributes: {
      iconName: { fieldName: "matchIcon" },
      iconAlternativeText: LABEL_SERIAL_MATCH,
      iconPosition: "right"
    }
  },
  { label: LABEL_COL_MODEL, fieldName: "model" },
  { label: LABEL_SITE, fieldName: "siteName" }
];

// DESC: 라벨의 {0}, {1} 자리 채우기
function format(template, ...values) {
  return values.reduce(
    (text, value, index) => text.replace(`{${index}}`, value ?? ""),
    template
  );
}

export default class CaseIntakeModal extends LightningModal {
  // DESC: 착신 모드 — CallerMatchService.MatchResult + 패널에서 고른 증상
  @api intake;
  @api symptomType;
  // DESC: 장비 모드 — 장비만 넘기면 열릴 때 판정 결과 모양으로 채움
  @api assetId;

  labels = {
    LABEL_CASE_INTAKE_TITLE,
    LABEL_CALL_SUMMARY,
    LABEL_CALLER_PHONE,
    LABEL_COL_ACCOUNT,
    LABEL_SITE,
    LABEL_ASSET,
    LABEL_COL_SYMPTOM,
    LABEL_SUBJECT,
    LABEL_DESCRIPTION,
    BTN_SAVE_CASE,
    BTN_CANCEL,
    MSG_SELECT_PLACEHOLDER,
    MSG_SEARCH_RECORD,
    MSG_ASSET_SAVE_HINT,
    BTN_OPEN_EXISTING_CASE
  };
  assetColumns = ASSET_COLUMNS;

  isCallMode = false;
  result = {};
  callerPhone = "";
  serialSuffix;
  accountId;
  siteId;
  selectedAssetId;
  accountOptions = [];
  siteOptions = [];
  assetRows = [];
  symptom;
  subject = "";
  subjectEdited = false;
  description = "";
  descriptionEdited = false;
  showSummary = false;
  isLoading = false;
  isSaving = false;
  errorMessage;
  // DESC: 고른 장비의 진행 중 접수 (BR-11 경고). 같은 장비면 다시 조회하지 않음
  openCases = { totalCount: 0, cases: [] };
  openCasesAssetId;
  openCasesSeq = 0;

  symptomOptions = [];
  symptomLabelsByValue = {};
  // DESC: 후보 조회가 겹칠 때 늦게 온 이전 응답 무시
  requestSeq = 0;

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
      this.symptomLabelsByValue = Object.fromEntries(
        data.values.map((v) => [v.value, v.label])
      );
      this.refreshDefaultText();
    }
  }

  connectedCallback() {
    this.symptom = this.symptomType;
    if (this.intake) {
      this.isCallMode = true;
      this.applyResult(this.intake);
      this.refreshForSelection();
    } else if (this.assetId) {
      this.loadForAsset(this.assetId);
    }
  }

  // ---------- 표시 ----------

  get summaryLines() {
    if (!this.isCallMode) {
      return [];
    }
    const r = this.result;
    const lines = [MATCHED_BY_MESSAGE[r.matchedBy] || MSG_MATCH_NONE];
    const suffix = r.serialSuffix;
    if (r.outcome === OUTCOME_CONFIRMED) {
      lines.push(
        r.serialMatchCount === 1
          ? format(MSG_OUTCOME_SERIAL_CONFIRMED, suffix)
          : MSG_OUTCOME_CONFIRMED
      );
    } else if (r.outcome === OUTCOME_ASSET_CANDIDATES) {
      lines.push(
        r.serialMatchCount > 1
          ? format(MSG_OUTCOME_SERIAL_CANDIDATES, suffix, r.assets.length)
          : format(MSG_OUTCOME_ASSET_CANDIDATES, r.assets.length)
      );
    } else if (r.outcome === OUTCOME_SITE_CANDIDATES) {
      lines.push(format(MSG_OUTCOME_SITE_CANDIDATES, r.sites.length));
    } else if (r.outcome === OUTCOME_ACCOUNT_CANDIDATES) {
      lines.push(format(MSG_OUTCOME_ACCOUNT_CANDIDATES, r.accounts.length));
    }
    if (suffix && r.serialMatchCount === 0 && r.matchedBy !== "NONE") {
      lines.push(format(MSG_SERIAL_NO_MATCH, suffix));
    }
    return lines.map((text, index) => ({ key: String(index), text }));
  }

  get callFacts() {
    // DESC: dt·dd가 형제라 key를 따로 둠
    return [
      { key: "phone", label: LABEL_CALLER_PHONE, value: this.callerPhone },
      {
        key: "symptom",
        label: LABEL_IVR_SYMPTOM,
        value: this.symptomLabelsByValue[this.symptomType] || "-"
      },
      {
        key: "serial",
        label: LABEL_SERIAL_SUFFIX,
        value: this.serialSuffix || LABEL_SERIAL_UNKNOWN
      }
    ].map((fact) => ({
      ...fact,
      labelKey: `${fact.key}-label`,
      valueKey: `${fact.key}-value`
    }));
  }

  get hasAccountCandidates() {
    return this.accountOptions.length > 1;
  }

  get accountComboOptions() {
    return this.accountOptions.map((o) => ({ label: o.label, value: o.id }));
  }

  get siteComboOptions() {
    return this.siteOptions.map((o) => ({
      label: this.hasAccountCandidates
        ? `${o.label} (${o.accountName})`
        : o.label,
      value: o.id
    }));
  }

  get isSiteDisabled() {
    return this.siteOptions.length === 0;
  }

  get hasAssetCandidates() {
    return this.assetRows.length > 0;
  }

  get selectedAssetRows() {
    return this.selectedAssetId ? [this.selectedAssetId] : [];
  }

  // DESC: 장비 검색은 고른 고객사 안으로 좁힘 (고객사 없으면 전체 — "없음 → 검색")
  get assetFilter() {
    return this.accountId
      ? {
          criteria: [
            { fieldPath: "AccountId", operator: "eq", value: this.accountId }
          ]
        }
      : undefined;
  }

  assetDisplayInfo = { additionalFields: ["SerialKey__c"] };
  assetMatchingInfo = {
    primaryField: { fieldPath: "Name" },
    additionalFields: [{ fieldPath: "SerialKey__c" }]
  };

  get summaryButtonLabel() {
    return this.showSummary ? BTN_ASSET_SUMMARY_HIDE : BTN_ASSET_SUMMARY;
  }

  get isSummaryDisabled() {
    return !this.selectedAssetId;
  }

  get isSaveDisabled() {
    return this.isSaving || this.isLoading;
  }

  // ---------- 값 반영 ----------

  applyResult(r) {
    this.result = r;
    this.callerPhone = r.callerPhone || this.callerPhone;
    this.serialSuffix = r.serialSuffix;
    this.accountId = r.accountId;
    this.siteId = r.siteId;
    this.selectedAssetId = r.assetId;
    this.accountOptions = r.accounts || [];
    this.siteOptions = r.sites || [];
    this.setAssetRows(r.assets || []);
  }

  setAssetRows(assets) {
    this.assetRows = assets.map((a) => ({
      ...a,
      matchIcon: a.serialMatched ? "utility:check" : null
    }));
  }

  get selectedAssetRow() {
    return this.assetRows.find((row) => row.id === this.selectedAssetId);
  }

  // DESC: 제목 기본값 "{증상} · {사업장} · {시리얼}" — 빈 값은 건너뜀, 모두 비면 "전화 접수"
  //       사업장은 고른 장비의 사업장 우선, 장비가 없으면 고른 사업장
  buildDefaultSubject() {
    const asset = this.selectedAssetRow;
    const site = this.siteOptions.find((o) => o.id === this.siteId);
    const parts = [
      this.symptomLabelsByValue[this.symptom],
      asset?.siteName || site?.label,
      asset?.serialKey
    ].filter((part) => part);
    return parts.length
      ? parts.join(SUBJECT_SEPARATOR)
      : LABEL_CALL_SUBJECT_PLAIN;
  }

  // DESC: 제목·설명 기본값. 상담원이 제목을 직접 고쳤으면 증상·장비를 바꿔도 덮어쓰지 않음
  refreshDefaultText() {
    if (!this.subjectEdited) {
      this.subject = this.buildDefaultSubject();
    }
    if (this.isCallMode && !this.descriptionEdited && !this.description) {
      const ivrLabel = this.symptomLabelsByValue[this.symptomType];
      if (ivrLabel || !this.symptomType) {
        this.description = format(
          LABEL_CALL_DESCRIPTION,
          this.callerPhone,
          ivrLabel || "-",
          this.serialSuffix || LABEL_SERIAL_UNKNOWN
        );
      }
    }
  }

  // DESC: 고객사·사업장·장비가 바뀐 뒤 — 제목 기본값 + 진행 중 접수
  refreshForSelection() {
    this.refreshDefaultText();
    this.syncOpenCases();
  }

  async syncOpenCases() {
    const assetId = this.selectedAssetId || null;
    if (assetId === this.openCasesAssetId) {
      return;
    }
    this.openCasesAssetId = assetId;
    this.openCases = { totalCount: 0, cases: [] };
    if (!assetId) {
      return;
    }
    const seq = ++this.openCasesSeq;
    try {
      const result = await getOpenCases({ assetId });
      if (seq === this.openCasesSeq) {
        this.openCases = result;
      }
    } catch (error) {
      // DESC: 경고 조회 실패는 접수 작성을 막지 않음 — 오류 문구만
      if (seq === this.openCasesSeq) {
        this.errorMessage = `${MSG_LOAD_ERROR}: ${reduceErrors(error).join(", ")}`;
      }
    }
  }

  get hasOpenCases() {
    return this.openCases.totalCount > 0;
  }

  get openCasesMessage() {
    return format(MSG_OPEN_CASES_WARNING, this.openCases.totalCount);
  }

  get openCasesMoreMessage() {
    return this.openCases.totalCount > this.openCases.cases.length
      ? format(MSG_OPEN_CASES_MORE, this.openCases.cases.length)
      : null;
  }

  // DESC: 새 탭으로 열어 입력 중인 팝업은 그대로 (Edwin 결정)
  handleOpenCase(event) {
    const caseId = event.currentTarget.dataset.id;
    window.open(`/lightning/r/Case/${caseId}/view`, "_blank");
  }

  // ---------- 사용자 동작 ----------

  handleAccountPick(event) {
    this.changeAccount(event.detail.recordId);
  }

  handleAccountSelect(event) {
    this.changeAccount(event.detail.value);
  }

  async changeAccount(accountId) {
    this.accountId = accountId;
    this.siteId = null;
    this.selectedAssetId = null;
    this.siteOptions = [];
    this.assetRows = [];
    this.showSummary = false;
    this.refreshForSelection();
    if (!accountId) {
      return;
    }
    const seq = ++this.requestSeq;
    await this.run(async () => {
      const sites = await getSiteCandidates({ accountId });
      if (seq !== this.requestSeq) {
        return;
      }
      this.siteOptions = sites;
      // DESC: 사업장 1곳이면 바로 그 사업장 (1건 → 채움), 없으면 고객사 장비로
      if (sites.length === 1) {
        this.siteId = sites[0].id;
      }
      await this.loadAssets(seq);
    });
  }

  async handleSiteSelect(event) {
    this.siteId = event.detail.value;
    const site = this.siteOptions.find((o) => o.id === this.siteId);
    if (site) {
      this.accountId = site.accountId;
    }
    this.selectedAssetId = null;
    this.showSummary = false;
    this.refreshForSelection();
    const seq = ++this.requestSeq;
    await this.run(() => this.loadAssets(seq));
  }

  async loadAssets(seq) {
    const choice = await getAssetCandidates({
      accountId: this.accountId,
      siteId: this.siteId,
      serialSuffix: this.serialSuffix
    });
    if (seq !== this.requestSeq) {
      return;
    }
    this.setAssetRows(choice.assets);
    this.selectedAssetId = choice.selectedAssetId;
    this.refreshForSelection();
  }

  handleAssetRowSelect(event) {
    const rows = event.detail.selectedRows;
    this.selectedAssetId = rows.length ? rows[0].id : null;
    if (!this.selectedAssetId) {
      this.showSummary = false;
    }
    this.refreshForSelection();
  }

  // DESC: 검색으로 고른 장비는 그 장비 기준으로 고객사·사업장·후보를 다시 채움 (통화 요약은 유지)
  async handleAssetPick(event) {
    const assetId = event.detail.recordId;
    if (!assetId) {
      return;
    }
    const seq = ++this.requestSeq;
    await this.run(async () => {
      const r = await getIntakeForAsset({ assetId });
      if (seq !== this.requestSeq) {
        return;
      }
      this.accountId = r.accountId;
      this.siteId = r.siteId;
      this.selectedAssetId = r.assetId;
      this.accountOptions = r.accounts || [];
      this.siteOptions = r.sites || [];
      this.setAssetRows(r.assets || []);
      this.refreshForSelection();
    });
  }

  async loadForAsset(assetId) {
    await this.run(async () => {
      this.applyResult(await getIntakeForAsset({ assetId }));
      this.refreshForSelection();
    });
  }

  handleSymptomChange(event) {
    this.symptom = event.detail.value;
    this.refreshDefaultText();
  }

  handleSubjectChange(event) {
    this.subject = event.detail.value;
    this.subjectEdited = true;
  }

  handleDescriptionChange(event) {
    this.description = event.detail.value;
    this.descriptionEdited = true;
  }

  handleToggleSummary() {
    this.showSummary = !this.showSummary;
  }

  handleCancel() {
    this.close();
  }

  async handleSave() {
    this.isSaving = true;
    this.disableClose = true;
    this.errorMessage = undefined;
    try {
      const caseId = await createCase({
        draft: {
          assetId: this.selectedAssetId,
          symptomType: this.symptom,
          subject: this.subject,
          description: this.description,
          callerPhone: this.callerPhone
        }
      });
      this.disableClose = false;
      this.close({ caseId });
    } catch (error) {
      // DESC: 검증 규칙(장비 없음 등) 메시지는 팝업 안에 — 입력한 값은 그대로 두고 고쳐서 다시 저장
      this.errorMessage = `${MSG_SAVE_ERROR}: ${reduceErrors(error).join(", ")}`;
    } finally {
      this.isSaving = false;
      this.disableClose = false;
    }
  }

  async run(work) {
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      await work();
    } catch (error) {
      this.errorMessage = `${MSG_LOAD_ERROR}: ${reduceErrors(error).join(", ")}`;
    } finally {
      this.isLoading = false;
    }
  }
}
