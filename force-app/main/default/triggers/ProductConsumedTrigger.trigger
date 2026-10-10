/**
 * @description 사용 부품(ProductConsumed) 트리거. 로직은 ProductConsumedTriggerHandler에만 둠 (1 오브젝트 1 트리거)
 * @layer       Trigger
 * @author      Edwin
 * @date        2026-10-08
 * @see ProductConsumedTriggerHandler
 */
trigger ProductConsumedTrigger on ProductConsumed (before insert, before update) {
    new ProductConsumedTriggerHandler().run();
}