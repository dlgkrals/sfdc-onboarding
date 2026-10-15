/**
 * @description 접수 작성 팝업 오른쪽 카드 — 고객사(유형·대표 번호·거래 상태·사업장·장비 수),
 *              사업장(주소·서비스센터·현장 담당자·보조 연락처·용도 긴급·장비 수·진행 중 접수 수)
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-15
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 1.0  2026-10-15  Edwin  최초 작성 (피드백 개선 ① 고객사·사업장 카드)
 * ----------------------------------------------------------------------------
 * 데이터 방식
 *   - imperative Apex(CallIntakeController.getContextCards, USER_MODE): 부모가 고객사·사업장을 바꿀 때마다
 *     같은 조합은 다시 부르지 않음(캐시). 늦게 온 이전 응답은 무시
 *   - 표시 전용, 저장 없음
 * ----------------------------------------------------------------------------
 * @see caseIntakeModal, CallIntakeController, IntakeContextService
 */
import { LightningElement, api } from "lwc";
import getContextCards from "@salesforce/apex/CallIntakeController.getContextCards";
import { reduceErrors } from "c/ldsUtils";

import LABEL_ACCOUNT_CARD from "@salesforce/label/c.LABEL_ACCOUNT_CARD";
import LABEL_SITE_CARD from "@salesforce/label/c.LABEL_SITE_CARD";
import LABEL_CUSTOMER_TYPE from "@salesforce/label/c.LABEL_CUSTOMER_TYPE";
import LABEL_MAIN_PHONE from "@salesforce/label/c.LABEL_MAIN_PHONE";
import LABEL_TRADE_STATUS from "@salesforce/label/c.LABEL_TRADE_STATUS";
import LABEL_SITE_COUNT from "@salesforce/label/c.LABEL_SITE_COUNT";
import LABEL_ASSET_COUNT from "@salesforce/label/c.LABEL_ASSET_COUNT";
import LABEL_ADDRESS from "@salesforce/label/c.LABEL_ADDRESS";
import LABEL_SERVICE_CENTER from "@salesforce/label/c.LABEL_SERVICE_CENTER";
import LABEL_ONSITE_CONTACT from "@salesforce/label/c.LABEL_ONSITE_CONTACT";
import LABEL_SECONDARY_PHONE from "@salesforce/label/c.LABEL_SECONDARY_PHONE";
import LABEL_USAGE from "@salesforce/label/c.LABEL_USAGE";
import LABEL_OPEN_CASE_COUNT from "@salesforce/label/c.LABEL_OPEN_CASE_COUNT";
import LABEL_URGENT_USAGE from "@salesforce/label/c.LABEL_URGENT_USAGE";
import LABEL_COUNT_SUFFIX from "@salesforce/label/c.LABEL_COUNT_SUFFIX";
import MSG_CARD_EMPTY from "@salesforce/label/c.MSG_CARD_EMPTY";
import MSG_LOAD_ERROR from "@salesforce/label/c.MSG_LOAD_ERROR";

// DESC: 거래 상태(AccountStatus__c API 이름) → 배지 색. 정상은 배지 없이 글자만
const STATUS_BADGE_CLASS = {
  PaymentWarning: "slds-theme_warning",
  Suspended: "slds-theme_error"
};

export default class IntakeContextCards extends LightningElement {
  labels = {
    LABEL_ACCOUNT_CARD,
    LABEL_SITE_CARD,
    LABEL_URGENT_USAGE,
    MSG_CARD_EMPTY
  };

  account;
  site;
  isLoading = false;
  errorMessage;

  _accountId;
  _siteId;
  cardsByKey = new Map();
  requestSeq = 0;
  loadScheduled = false;

  @api
  get accountId() {
    return this._accountId;
  }
  set accountId(value) {
    this._accountId = value;
    this.scheduleLoad();
  }

  @api
  get siteId() {
    return this._siteId;
  }
  set siteId(value) {
    this._siteId = value;
    this.scheduleLoad();
  }

  // DESC: 부모가 고객사·사업장을 한 번에 바꿔도 조회는 1번 (같은 마이크로태스크에서 모음)
  scheduleLoad() {
    if (this.loadScheduled) {
      return;
    }
    this.loadScheduled = true;
    Promise.resolve().then(() => {
      this.loadScheduled = false;
      this.load();
    });
  }

  async load() {
    const accountId = this._accountId || null;
    const siteId = this._siteId || null;
    if (!accountId && !siteId) {
      this.account = undefined;
      this.site = undefined;
      return;
    }
    const key = `${accountId}|${siteId}`;
    const seq = ++this.requestSeq;
    this.errorMessage = undefined;
    if (this.cardsByKey.has(key)) {
      this.applyCards(this.cardsByKey.get(key));
      return;
    }
    this.isLoading = true;
    try {
      const cards = await getContextCards({ accountId, siteId });
      this.cardsByKey.set(key, cards);
      if (seq === this.requestSeq) {
        this.applyCards(cards);
      }
    } catch (error) {
      if (seq === this.requestSeq) {
        this.errorMessage = `${MSG_LOAD_ERROR}: ${reduceErrors(error).join(", ")}`;
      }
    } finally {
      if (seq === this.requestSeq) {
        this.isLoading = false;
      }
    }
  }

  applyCards(cards) {
    this.account = cards?.account;
    this.site = cards?.site;
  }

  get isEmpty() {
    return !this.account && !this.site && !this.isLoading && !this.errorMessage;
  }

  get statusBadgeClass() {
    return STATUS_BADGE_CLASS[this.account?.status];
  }

  get accountFacts() {
    const a = this.account;
    return [
      { key: "type", label: LABEL_CUSTOMER_TYPE, value: a.customerType },
      { key: "phone", label: LABEL_MAIN_PHONE, value: a.phone },
      {
        key: "status",
        label: LABEL_TRADE_STATUS,
        value: this.statusBadgeClass ? null : a.statusLabel,
        badge: this.statusBadgeClass ? a.statusLabel : null
      },
      {
        key: "sites",
        label: LABEL_SITE_COUNT,
        value: `${a.siteCount ?? 0}${LABEL_COUNT_SUFFIX}`
      },
      {
        key: "assets",
        label: LABEL_ASSET_COUNT,
        value: `${a.assetCount ?? 0}${LABEL_COUNT_SUFFIX}`
      }
    ].map(this.withKeys);
  }

  get siteFacts() {
    const s = this.site;
    const contact = [s.onSiteContactName, s.onSiteContactPhone]
      .filter((v) => v)
      .join(" · ");
    return [
      { key: "address", label: LABEL_ADDRESS, value: s.address },
      { key: "center", label: LABEL_SERVICE_CENTER, value: s.serviceCenter },
      { key: "contact", label: LABEL_ONSITE_CONTACT, value: contact },
      {
        key: "secondary",
        label: LABEL_SECONDARY_PHONE,
        value: s.secondaryContactPhone
      },
      { key: "usage", label: LABEL_USAGE, value: s.usageLabel },
      {
        key: "assets",
        label: LABEL_ASSET_COUNT,
        value: `${s.assetCount ?? 0}${LABEL_COUNT_SUFFIX}`
      },
      {
        key: "open",
        label: LABEL_OPEN_CASE_COUNT,
        value: `${s.openCaseCount ?? 0}${LABEL_COUNT_SUFFIX}`
      }
    ].map(this.withKeys);
  }

  // DESC: dt·dd가 형제라 key를 따로 둠, 빈 값은 "-"
  withKeys(fact) {
    return {
      ...fact,
      value: fact.badge ? null : fact.value || "-",
      labelKey: `${fact.key}-label`,
      valueKey: `${fact.key}-value`
    };
  }
}
