/**
 * @description 차량 재고 사용 검사 — 남은 수량보다 많이 쓰는 사용 부품을 거부
 *              - rejectOverStock : 사용 부품 before insert (모든 입력 경로: 부품 추가 화면·표준 새로 만들기·데이터 로더·Apex)
 *              - stockMessage    : 화면(WorkOrderPartsController)과 트리거가 같은 안내 문구를 쓰도록 한 곳에서 만듦
 *              정확히 남은 수량만큼은 허용(경계). 남은 수량이 0이면 "재고 없음" 문구
 * @layer       Service
 * @author      Edwin
 * @date        2026-10-14
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-14    Edwin     최초 작성 (D8 보안 점검 R1: 화면 경로에만 있던 초과 검사를 트리거로)
 * ----------------------------------------------------------------------------
 * @see ProductConsumedTriggerHandler, WorkOrderPartsController, docs/d8_security_review.md R1, docs/decision-log.md ERP 18
 */
// DESC: 재고 수량은 사용자가 고칠 수 없는 시스템 기준 값 → 조회는 SYSTEM_MODE (실행 사용자 공유와 상관없이 같은 판정)
public with sharing class VanStockService {
  private static final String UNIT_EACH = 'Each';
  private static final String UNIT_KG = 'kg';

  /**
   * @description 남은 수량을 넘는 사용 부품에 오류 표시 (저장 거부)
   *              같은 재고를 한 묶음에서 여러 건 쓰면 Trigger.new 순서대로 누적해서 판정
   *              (앞 건이 거부되면 그 수량은 누적하지 않음)
   * @param parts before insert의 사용 부품 (ProductItemId 없는 건은 건너뜀)
   */
  public static void rejectOverStock(List<ProductConsumed> parts) {
    Set<Id> itemIds = new Set<Id>();
    for (ProductConsumed pc : parts) {
      if (pc.ProductItemId != null && pc.QuantityConsumed != null) {
        itemIds.add(pc.ProductItemId);
      }
    }
    if (itemIds.isEmpty()) {
      return;
    }
    Map<Id, ProductItem> itemsById = new Map<Id, ProductItem>(
      [
        SELECT Id, QuantityOnHand, QuantityUnitOfMeasure
        FROM ProductItem
        WHERE Id IN :itemIds
        WITH SYSTEM_MODE
      ]
    );
    Map<Id, Decimal> usedByItem = new Map<Id, Decimal>();
    for (ProductConsumed pc : parts) {
      ProductItem item = itemsById.get(pc.ProductItemId);
      if (item == null || pc.QuantityConsumed == null) {
        continue;
      }
      Decimal used = usedByItem.containsKey(item.Id)
        ? usedByItem.get(item.Id)
        : 0;
      Decimal remaining =
        (item.QuantityOnHand == null ? 0 : item.QuantityOnHand) - used;
      if (pc.QuantityConsumed > remaining) {
        pc.addError(stockMessage(remaining, item.QuantityUnitOfMeasure));
      } else {
        usedByItem.put(item.Id, used + pc.QuantityConsumed);
      }
    }
  }

  /**
   * @description 재고 부족 안내 문구 — 남은 수량 0 이하 "재고 없음", 그 외 "차량 재고가 부족합니다(남은 n단위)…"
   * @param remaining 남은 수량
   * @param unit      재고 단위 값(Each, kg)
   */
  public static String stockMessage(Decimal remaining, String unit) {
    if (remaining == null || remaining <= 0) {
      return System.Label.MSG_STOCK_EMPTY;
    }
    return String.format(
      System.Label.MSG_STOCK_SHORT,
      new List<String>{
        remaining.stripTrailingZeros().toPlainString(),
        unitLabelOf(unit)
      }
    );
  }

  // DESC: 단위 값 → 화면 표기 (Custom Label 한 곳에서 관리, 수식 필드 fmErpRemainingQty__c와 같은 규칙)
  public static String unitLabelOf(String unit) {
    if (unit == UNIT_EACH) {
      return System.Label.MISC_UNIT_EACH;
    }
    if (unit == UNIT_KG) {
      return System.Label.MISC_UNIT_KG;
    }
    return unit == null ? '' : unit;
  }
}
