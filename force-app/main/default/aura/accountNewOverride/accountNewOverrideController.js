/* eslint-disable no-unused-expressions */
({
  // DESC: 표준 레코드 유형 선택 화면에서 고른 유형 (선택 화면이 없으면 비어 있음 → LWC가 기본 유형 사용)
  readState: function (component) {
    var state = (component.get("v.pageReference") || {}).state || {};
    component.set("v.recordTypeId", state.recordTypeId || null);
  }
});
