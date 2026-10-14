/**
 * @description 출동 사용 부품 화면(workOrderParts · partAddForm) 컨트롤러
 *              - getParts    : 출동의 사용 부품 목록(유·무상 판정·ERP 전송 상태·단위) + 유상 부품비·총 청구액·승인 필요
 *              - getVanStock : 출동 담당 기사 차량의 재고 — 부품 추가 선택지 (남은 수량 0도 포함, 화면에서 비활성)
 *              - addPart     : 사용 부품 1건 저장 (판정은 트리거, ERP 전송은 Queueable)
 * @layer       Controller
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 LWC: 자식 → 부모 이벤트 화면)
 * 1.1    2026-10-14    Edwin     차량 재고 선택지에 남은 수량 0 포함(available), 0인 재고로 저장 거부 (D8 화면 개선)
 * 1.2    2026-10-14    Edwin     남은 수량보다 많이 쓰는 입력 거부 (D8 결정, 정확히 남은 수량은 허용)
 * ----------------------------------------------------------------------------
 * @see workOrderParts, partAddForm (LWC), ProductConsumedTriggerHandler, docs/d7_lwc_memo.md 3절
 */
// DESC: 화면은 실행 사용자 권한대로 → with sharing + 조회·저장 USER_MODE (기사는 자기 출동·자기 차량 재고만)
public with sharing class WorkOrderPartsController {
  // DESC: 출동 한 건의 사용 부품은 많아야 수십 건. 화면 보호용 상한
  private static final Integer MAX_ROWS = 200;
  private static final String LOCATION_TYPE_VAN = 'Van';
  private static final String UNIT_EACH = 'Each';
  private static final String UNIT_KG = 'kg';

  /**
   * @description 출동의 사용 부품 목록과 합계
   * @param workOrderId 출동 Id
   * @return 목록 + 유상 부품비·총 청구액·승인 필요·추가 가능 여부
   */
  @AuraEnabled(cacheable=true)
  public static PartsView getParts(Id workOrderId) {
    PartsView view = new PartsView();
    if (workOrderId == null) {
      return view;
    }
    try {
      List<WorkOrder> workOrders = [
        SELECT
          Id,
          WorkOrderNumber,
          ruPaidPartsTotal__c,
          fmTotalCharge__c,
          fmNeedsApproval__c
        FROM WorkOrder
        WHERE Id = :workOrderId
        WITH USER_MODE
      ];
      if (workOrders.isEmpty()) {
        return view;
      }
      view.workOrderNumber = workOrders[0].WorkOrderNumber;
      view.paidTotal = workOrders[0].ruPaidPartsTotal__c;
      view.totalCharge = workOrders[0].fmTotalCharge__c;
      view.needsApproval = workOrders[0].fmNeedsApproval__c;
      view.canAdd = Schema.SObjectType.ProductConsumed.isCreateable();

      // PERF: 선택 목록 표시 이름은 describe 1회로 Map을 만들어 사용 (toLabel은 원래 값을 함께 못 가져옴)
      Map<String, String> chargeLabelByValue = labelsOf(
        ProductConsumed.ChargeType__c.getDescribe()
      );
      Map<String, String> erpLabelByValue = labelsOf(
        ProductConsumed.ErpSyncStatus__c.getDescribe()
      );
      for (ProductConsumed pc : [
        SELECT
          Id,
          ProductConsumedNumber,
          QuantityConsumed,
          Product2.Name,
          Product2.ErpPartCode__c,
          ProductItem.QuantityUnitOfMeasure,
          AutoChargeType__c,
          ChargeType__c,
          fmAmount__c,
          ErpSyncStatus__c,
          ErpSyncMessage__c,
          fmErpRemainingQty__c,
          InventoryMismatch__c
        FROM ProductConsumed
        WHERE WorkOrderId = :workOrderId
        WITH USER_MODE
        ORDER BY CreatedDate DESC
        LIMIT :MAX_ROWS
      ]) {
        view.rows.add(new PartRow(pc, chargeLabelByValue, erpLabelByValue));
      }
      return view;
    } catch (Exception e) {
      throw toAuraException(e.getMessage());
    }
  }

  /**
   * @description 출동 담당 기사 차량의 재고 (부품 이름·위치순). 남은 수량 0도 돌려주고 available=false로 표시
   *              (빈 재고를 목록에서 숨기면 "왜 안 보이지?"가 되므로 보이되 고를 수 없게)
   * @param workOrderId 출동 Id
   * @return 재고 선택지
   */
  @AuraEnabled(cacheable=true)
  public static List<StockOption> getVanStock(Id workOrderId) {
    List<StockOption> options = new List<StockOption>();
    if (workOrderId == null) {
      return options;
    }
    try {
      List<WorkOrder> workOrders = [
        SELECT OwnerId
        FROM WorkOrder
        WHERE Id = :workOrderId
        WITH USER_MODE
      ];
      if (workOrders.isEmpty()) {
        return options;
      }
      for (ProductItem item : [
        SELECT
          Id,
          QuantityOnHand,
          QuantityUnitOfMeasure,
          Product2.Name,
          Product2.ErpPartCode__c,
          Location.Name
        FROM ProductItem
        WHERE
          OwnerId = :workOrders[0].OwnerId
          AND Location.LocationType = :LOCATION_TYPE_VAN
        WITH USER_MODE
        ORDER BY Product2.Name, Location.Name
        LIMIT :MAX_ROWS
      ]) {
        options.add(new StockOption(item));
      }
      return options;
    } catch (Exception e) {
      throw toAuraException(e.getMessage());
    }
  }

  /**
   * @description 사용 부품 1건 저장. 유·무상 판정은 트리거(before insert), ERP 전송은 트리거가 예약
   * @param workOrderId   출동 Id
   * @param productItemId 사용한 재고(차량 재고) Id
   * @param quantity      사용 수량 (0보다 커야 함)
   * @return 새 사용 부품 Id (화면이 이 Id로 판정 결과를 다시 읽음)
   */
  @AuraEnabled
  public static Id addPart(Id workOrderId, Id productItemId, Decimal quantity) {
    if (workOrderId == null || productItemId == null) {
      throw toAuraException(System.Label.MSG_PART_SELECT_REQUIRED);
    }
    if (quantity == null || quantity <= 0) {
      throw toAuraException(System.Label.MSG_QUANTITY_INVALID);
    }
    // DESC: 화면에서 비활성이어도 서버에서 한 번 더 (화면 검사는 우회할 수 있음). 사용자 권한으로 보이는 재고만
    List<ProductItem> items = [
      SELECT QuantityOnHand, QuantityUnitOfMeasure
      FROM ProductItem
      WHERE Id = :productItemId
      WITH USER_MODE
    ];
    if (items.isEmpty()) {
      throw toAuraException(System.Label.MSG_PART_SELECT_REQUIRED);
    }
    if (items[0].QuantityOnHand == null || items[0].QuantityOnHand <= 0) {
      throw toAuraException(System.Label.MSG_STOCK_EMPTY);
    }
    // WARN: 차량 재고보다 많이 쓰면 거부. ERP 입고는 역방향 동기화(15분) 뒤에 반영되므로 그 사이엔 적게 보일 수 있음 (decision-log 18)
    if (quantity > items[0].QuantityOnHand) {
      throw toAuraException(
        String.format(
          System.Label.MSG_STOCK_SHORT,
          new List<String>{
            items[0].QuantityOnHand.stripTrailingZeros().toPlainString(),
            unitLabelOf(items[0].QuantityUnitOfMeasure)
          }
        )
      );
    }
    ProductConsumed part = new ProductConsumed(
      WorkOrderId = workOrderId,
      ProductItemId = productItemId,
      QuantityConsumed = quantity
    );
    try {
      Database.insert(part, true, AccessLevel.USER_MODE);
      return part.Id;
    } catch (DmlException e) {
      // DESC: 검증 규칙·트리거 오류 문구를 그대로 화면에 (스택 없이 첫 메시지만)
      throw toAuraException(e.getDmlMessage(0));
    } catch (Exception e) {
      throw toAuraException(e.getMessage());
    }
  }

  // DESC: 단위 값 → 화면 표기 (Custom Label 한 곳에서 관리, 수식 필드 fmErpRemainingQty__c와 같은 규칙)
  @TestVisible
  private static String unitLabelOf(String unit) {
    if (unit == UNIT_EACH) {
      return System.Label.MISC_UNIT_EACH;
    }
    if (unit == UNIT_KG) {
      return System.Label.MISC_UNIT_KG;
    }
    return unit == null ? '' : unit;
  }

  private static Map<String, String> labelsOf(
    Schema.DescribeFieldResult field
  ) {
    Map<String, String> labelByValue = new Map<String, String>();
    for (Schema.PicklistEntry entry : field.getPicklistValues()) {
      labelByValue.put(entry.getValue(), entry.getLabel());
    }
    return labelByValue;
  }

  private static AuraHandledException toAuraException(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }

  /**
   * @description 화면 전체: 사용 부품 목록 + 출동 합계
   */
  public class PartsView {
    @AuraEnabled
    public String workOrderNumber;
    @AuraEnabled
    public List<PartRow> rows = new List<PartRow>();
    @AuraEnabled
    public Decimal paidTotal;
    @AuraEnabled
    public Decimal totalCharge;
    @AuraEnabled
    public Boolean needsApproval = false;
    @AuraEnabled
    public Boolean canAdd = false;
  }

  /**
   * @description 사용 부품 한 줄
   */
  public class PartRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String partNumber;
    @AuraEnabled
    public String partName;
    @AuraEnabled
    public String partCode;
    @AuraEnabled
    public Decimal quantity;
    @AuraEnabled
    public String unitLabel;
    @AuraEnabled
    public String autoChargeType;
    @AuraEnabled
    public String chargeType;
    @AuraEnabled
    public String chargeTypeLabel;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String erpStatus;
    @AuraEnabled
    public String erpStatusLabel;
    @AuraEnabled
    public String erpMessage;
    @AuraEnabled
    public String erpRemaining;
    @AuraEnabled
    public Boolean inventoryMismatch;

    public PartRow(
      ProductConsumed pc,
      Map<String, String> chargeLabelByValue,
      Map<String, String> erpLabelByValue
    ) {
      id = pc.Id;
      partNumber = pc.ProductConsumedNumber;
      partName = pc.Product2?.Name;
      partCode = pc.Product2?.ErpPartCode__c;
      quantity = pc.QuantityConsumed;
      unitLabel = unitLabelOf(pc.ProductItem?.QuantityUnitOfMeasure);
      autoChargeType = pc.AutoChargeType__c;
      chargeType = pc.ChargeType__c;
      chargeTypeLabel = chargeLabelByValue.get(pc.ChargeType__c);
      amount = pc.fmAmount__c;
      erpStatus = pc.ErpSyncStatus__c;
      erpStatusLabel = erpLabelByValue.get(pc.ErpSyncStatus__c);
      erpMessage = pc.ErpSyncMessage__c;
      erpRemaining = pc.fmErpRemainingQty__c;
      inventoryMismatch = pc.InventoryMismatch__c;
    }
  }

  /**
   * @description 부품 추가 선택지 (차량 재고 한 줄)
   */
  public class StockOption {
    @AuraEnabled
    public Id productItemId;
    @AuraEnabled
    public String partName;
    @AuraEnabled
    public String partCode;
    @AuraEnabled
    public String locationName;
    @AuraEnabled
    public Decimal quantityOnHand;
    @AuraEnabled
    public Boolean available;
    @AuraEnabled
    public String unitLabel;

    public StockOption(ProductItem item) {
      productItemId = item.Id;
      partName = item.Product2?.Name;
      partCode = item.Product2?.ErpPartCode__c;
      locationName = item.Location?.Name;
      quantityOnHand = item.QuantityOnHand;
      unitLabel = unitLabelOf(item.QuantityUnitOfMeasure);
      available = item.QuantityOnHand != null && item.QuantityOnHand > 0;
    }
  }
}
