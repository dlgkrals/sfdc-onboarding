/* eslint-disable no-unused-expressions */
({
  // DESC: 부모 고객사 Id 찾기 ① inContextOfRef("1." + base64 JSON 페이지 참조) ② defaultFieldValues("Account__c=Id")
  //       그다음 LWC를 지웠다가 다시 그려 이전 입력이 남지 않게 함 (재정의 화면 캐시 대응)
  readState: function (component, event, helper) {
    var state = (component.get("v.pageReference") || {}).state || {};
    var parentId = null;
    var context = state.inContextOfRef;
    var ref;
    var match;
    if (context && context.indexOf("1.") === 0) {
      try {
        ref = JSON.parse(window.atob(context.substring(2)));
        if (
          ref &&
          ref.attributes &&
          String(ref.attributes.recordId || "").indexOf("001") === 0
        ) {
          parentId = ref.attributes.recordId;
        }
      } catch (error) {
        // DESC: 형식이 다르면 부모 없이 빈 화면으로 (사용자가 고객사를 직접 고름)
        parentId = error ? null : parentId;
      }
    }
    if (!parentId && state.defaultFieldValues) {
      match = /Account__c=([a-zA-Z0-9]{15,18})/.exec(state.defaultFieldValues);
      parentId = match ? match[1] : null;
    }
    component.set("v.parentAccountId", parentId);
    helper.rerender(component);
  }
});
