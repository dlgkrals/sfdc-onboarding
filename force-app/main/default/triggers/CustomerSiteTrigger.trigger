/**
 * @description 사업장(CustomerSite__c) 트리거. 로직은 CustomerSiteTriggerHandler에만 둠 (1 오브젝트 1 트리거)
 *              before insert·update(서비스센터 자동 지정)
 * @layer       Trigger
 * @author      Edwin
 * @date        2026-10-14
 * @see CustomerSiteTriggerHandler
 */
trigger CustomerSiteTrigger on CustomerSite__c(before insert, before update) {
  new CustomerSiteTriggerHandler().run();
}
