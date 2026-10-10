/**
 * @description 접수(Case) 트리거. 로직은 CaseTriggerHandler에만 둠 (1 오브젝트 1 트리거)
 * @layer       Trigger
 * @author      Edwin
 * @date        2026-10-08
 * @see CaseTriggerHandler
 */
trigger CaseTrigger on Case(
  before insert,
  after insert,
  after update,
  after delete,
  after undelete
) {
  new CaseTriggerHandler().run();
}
