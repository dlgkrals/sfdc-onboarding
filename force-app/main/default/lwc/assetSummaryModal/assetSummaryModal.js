/**
 * @description 장비 요약 팝업 — 장비 검색에서 시리얼을 누르면 이동하지 않고 먼저 요약을 보여 줌
 *              [장비 열기] / [이 장비로 접수](접수 생성 권한 있는 사람만) / [닫기]
 * @layer       LWC
 * @author      Edwin
 * @date        2026-10-15
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 1.0  2026-10-15  Edwin  최초 작성 (CTI 가상 착신 시뮬레이터)
 * ----------------------------------------------------------------------------
 * 닫을 때 결과: "open"(장비 열기) / "intake"(이 장비로 접수) / undefined(닫기·X)
 * 이동·다음 팝업은 연 쪽(assetSearch)이 처리 (모달 안에서 모달을 열지 않음)
 * ----------------------------------------------------------------------------
 * @see assetSummary, assetSearch, caseIntakeModal
 */
import { api } from "lwc";
import LightningModal from "lightning/modal";

import LABEL_ASSET_SUMMARY_TITLE from "@salesforce/label/c.LABEL_ASSET_SUMMARY_TITLE";
import BTN_OPEN_ASSET from "@salesforce/label/c.BTN_OPEN_ASSET";
import BTN_INTAKE_WITH_ASSET from "@salesforce/label/c.BTN_INTAKE_WITH_ASSET";
import BTN_CLOSE from "@salesforce/label/c.BTN_CLOSE";

// DESC: 닫기 결과 값 — assetSearch와 같게 유지
const RESULT_OPEN = "open";
const RESULT_INTAKE = "intake";

export default class AssetSummaryModal extends LightningModal {
  @api assetId;
  // DESC: 연 쪽이 CallIntakeController.canCreateCase 결과를 넘김 (상담원·관리자만 true)
  @api canIntake = false;

  labels = {
    LABEL_ASSET_SUMMARY_TITLE,
    BTN_OPEN_ASSET,
    BTN_INTAKE_WITH_ASSET,
    BTN_CLOSE
  };

  handleClose() {
    this.close();
  }

  handleOpen() {
    this.close(RESULT_OPEN);
  }

  handleIntake() {
    this.close(RESULT_INTAKE);
  }
}
