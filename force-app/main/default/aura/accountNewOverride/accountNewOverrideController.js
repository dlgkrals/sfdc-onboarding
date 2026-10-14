/* eslint-disable no-unused-expressions */
({
  // DESC: 표준 레코드 유형 선택 화면에서 고른 유형 (선택 화면이 없으면 비어 있음 → LWC가 유형부터 고르게 함)
  //       그다음 LWC를 지웠다가 다시 그려 이전 입력이 남지 않게 함 (재정의 화면 캐시 대응)
  readState: function (component, event, helper) {
    var state = (component.get("v.pageReference") || {}).state || {};
    component.set("v.recordTypeId", state.recordTypeId || null);
    helper.rerender(component);
  }
});
