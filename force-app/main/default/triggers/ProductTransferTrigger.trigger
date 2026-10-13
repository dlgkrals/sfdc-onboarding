/**
 * @description 재고 이동(ProductTransfer) 트리거. 로직은 ProductTransferTriggerHandler에만 둠 (1 오브젝트 1 트리거)
 *              before insert·update(수령 건 대기 표시) · after insert·update(ERP 전송 예약, IF-06)
 * @layer       Trigger
 * @author      Edwin
 * @date        2026-10-13
 * @see ProductTransferTriggerHandler
 */
trigger ProductTransferTrigger on ProductTransfer(
  before insert,
  before update,
  after insert,
  after update
) {
  new ProductTransferTriggerHandler().run();
}
