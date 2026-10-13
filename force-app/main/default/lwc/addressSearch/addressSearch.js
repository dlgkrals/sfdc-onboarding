/**
 * @description 공통 도로명주소 검색 — 검색어 입력 → 결과 목록 → "선택"하면 부모에게 addressselected 이벤트
 *              사업장·고객사 등 주소를 넣는 화면에 끼워 쓰는 재사용 컴포넌트 (레코드 저장은 부모가 담당)
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 데이터 방식: imperative Apex (AddressSearchController.searchAddresses, cacheable=true)
 *   - 검색어 입력(디바운스, 2글자 이상)과 "더 보기"가 모두 사용자 동작 → 호출 시점을 컴포넌트가 정함
 *   - 외부 API 호출이라 같은 검색어 재조회는 클라이언트 캐시로 줄임
 * 자식→부모 이벤트: addressselected  detail = { roadAddress, roadAddressPart1, roadAddressNote, jibunAddress,
 *   postalCode, sido, sigungu, eupMyeonDong, adminDistrictCode, buildingName }
 * ----------------------------------------------------------------------------
 * @see AddressSearchController
 */
import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import searchAddresses from "@salesforce/apex/AddressSearchController.searchAddresses";
import { reduceErrors } from "c/ldsUtils";

import LABEL_ADDRESS_SEARCH from "@salesforce/label/c.LABEL_ADDRESS_SEARCH";
import MSG_ADDRESS_PLACEHOLDER from "@salesforce/label/c.MSG_ADDRESS_PLACEHOLDER";
import MSG_ADDRESS_NOT_FOUND from "@salesforce/label/c.MSG_ADDRESS_NOT_FOUND";
import LABEL_ADDRESS_COUNT from "@salesforce/label/c.LABEL_ADDRESS_COUNT";
import LABEL_POSTAL_CODE from "@salesforce/label/c.LABEL_POSTAL_CODE";
import LABEL_JIBUN from "@salesforce/label/c.LABEL_JIBUN";
import BTN_SELECT from "@salesforce/label/c.BTN_SELECT";
import BTN_MORE from "@salesforce/label/c.BTN_MORE";
import MSG_LOAD_ERROR from "@salesforce/label/c.MSG_LOAD_ERROR";

const SEARCH_DELAY_MS = 400;
const MIN_KEYWORD_LENGTH = 2;

export default class AddressSearch extends LightningElement {
  /** 검색칸 라벨 (기본: 도로명주소 검색) */
  @api label = LABEL_ADDRESS_SEARCH;

  labels = {
    MSG_ADDRESS_PLACEHOLDER,
    MSG_ADDRESS_NOT_FOUND,
    LABEL_POSTAL_CODE,
    LABEL_JIBUN,
    BTN_SELECT,
    BTN_MORE
  };

  keyword = "";
  rows = [];
  totalCount = 0;
  pageNumber = 1;
  isLoading = false;
  hasSearched = false;
  errorMessage;

  searchTimer;
  // DESC: 늦게 도착한 이전 응답이 최신 결과를 덮지 않도록 요청 번호로 구분
  requestSeq = 0;

  disconnectedCallback() {
    clearTimeout(this.searchTimer);
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get isEmpty() {
    return (
      this.hasSearched &&
      !this.isLoading &&
      !this.errorMessage &&
      this.rows.length === 0
    );
  }

  get hasMore() {
    return !this.isLoading && this.rows.length < this.totalCount;
  }

  get countText() {
    return LABEL_ADDRESS_COUNT.replace("{0}", this.totalCount).replace(
      "{1}",
      this.rows.length
    );
  }

  handleKeywordChange(event) {
    const value = (event.target.value || "").trim();
    clearTimeout(this.searchTimer);
    if (value.length < MIN_KEYWORD_LENGTH) {
      this.rows = [];
      this.totalCount = 0;
      this.hasSearched = false;
      this.errorMessage = undefined;
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => {
      this.keyword = value;
      this.search(1);
    }, SEARCH_DELAY_MS);
  }

  handleMore() {
    this.search(this.pageNumber + 1);
  }

  // DESC: 선택한 주소를 부모에게 넘김. 부모가 레코드 필드에 반영·저장 (이 컴포넌트는 저장하지 않음)
  handleSelect(event) {
    const index = Number(event.currentTarget.dataset.index);
    const address = { ...this.rows[index] };
    delete address.key;
    this.dispatchEvent(new CustomEvent("addressselected", { detail: address }));
  }

  async search(page) {
    const seq = ++this.requestSeq;
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      const result = await searchAddresses({
        keyword: this.keyword,
        pageNumber: page
      });
      if (seq !== this.requestSeq) {
        return;
      }
      const offset = page === 1 ? 0 : this.rows.length;
      const newRows = result.rows.map((row, i) => ({
        ...row,
        key: `${page}-${offset + i}`
      }));
      this.rows = page === 1 ? newRows : [...this.rows, ...newRows];
      this.totalCount = result.totalCount;
      this.pageNumber = result.pageNumber;
    } catch (error) {
      if (seq === this.requestSeq) {
        // DESC: 모달 안에서도 보이도록 카드 안 문구 + 토스트
        this.errorMessage = reduceErrors(error).join(", ");
        this.dispatchEvent(
          new ShowToastEvent({
            title: MSG_LOAD_ERROR,
            message: this.errorMessage,
            variant: "error"
          })
        );
      }
    } finally {
      if (seq === this.requestSeq) {
        this.isLoading = false;
        this.hasSearched = true;
      }
    }
  }
}
