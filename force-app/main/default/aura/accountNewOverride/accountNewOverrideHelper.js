/* eslint-disable no-unused-expressions */
({
  // DESC: LWC를 한 번 지우고(다음 렌더링에) 다시 만듦 → 컴포넌트 상태·record-edit-form 입력값이 모두 처음으로
  rerender: function (component) {
    component.set("v.showForm", false);
    window.setTimeout(
      $A.getCallback(function () {
        if (component.isValid()) {
          component.set("v.showForm", true);
        }
      }),
      0
    );
  }
});
