/**
 * @description 사용 부품(ProductConsumed) 트리거. 로직은 ProductConsumedTriggerHandler에만 둠 (1 오브젝트 1 트리거)
 *              before insert(유·무상 판정) · after insert(ERP 전송 예약) · before delete(삭제 규칙) · after delete(재고 되돌림) · after undelete(복원 거부)
 * @layer       Trigger
 * @author      Edwin
 * @date        2026-10-08
 * @see ProductConsumedTriggerHandler
 */
trigger ProductConsumedTrigger on ProductConsumed(
  before insert,
  after insert,
  before delete,
  after delete,
  after undelete
) {
  new ProductConsumedTriggerHandler().run();
}
