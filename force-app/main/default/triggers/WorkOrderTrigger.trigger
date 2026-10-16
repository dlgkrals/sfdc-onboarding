/**
 * @description 출동(WorkOrder) 트리거. 로직은 WorkOrderTriggerHandler에만 둠 (1 오브젝트 1 트리거)
 * @layer       Trigger
 * @author      Edwin
 * @date        2026-10-16
 * @see WorkOrderTriggerHandler
 */
trigger WorkOrderTrigger on WorkOrder(
  after insert,
  after update,
  after delete,
  after undelete
) {
  new WorkOrderTriggerHandler().run();
}
