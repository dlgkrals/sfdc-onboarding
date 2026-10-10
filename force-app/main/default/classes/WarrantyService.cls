/**
 * @description 사용 부품(ProductConsumed) 유·무상 자동 판정 (BR-06, 판정 규칙: D5 설계 4-1)
 *              1) 판정 기준일 = 출동의 접수 생성일 (없으면 오늘)
 *              2) 부품 분류 = Product2.Family (Product2Id가 없으면 ProductItem.Product2Id로 찾음)
 *              3) 적용 만료일
 *                 - Compressor : 압축기 만료일과 (연장보증이면) 연장 만료일 중 늦은 날
 *                 - 그 외      : 연장보증이면 연장 만료일, 아니면 기본 만료일
 *              4) 기준일 <= 적용 만료일 → Free, 아니면 Paid. 만료일이 없으면(보증 미확정) Paid
 *              5) 최종 판정(ChargeType__c)은 비어 있을 때만 자동 판정 값으로 채움 (사람이 정한 값은 덮어쓰지 않음)
 * @layer       Service
 * @author      Edwin
 * @date        2026-10-08
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-08    Edwin     최초 작성 (D5 실습: 유·무상 자동 판정)
 * ----------------------------------------------------------------------------
 * @see ProductConsumedTriggerHandler, Asset.fmBasicWarrantyEndDate__c / fmCompressorWarrantyEndDate__c / fmExtendedWarrantyEndDate__c
 */
// DESC: 트리거에서 호출되면 호출 쪽 공유 규칙을 따름(트리거는 시스템 모드).
// WARN: 기사 화면 등 사용자 컨텍스트에서 직접 호출해 장비 보증 정보를 못 읽는 문제가 생기면 without sharing으로 바꾸고 이유를 남길 것
public inherited sharing class WarrantyService {
  public static final String CHARGE_FREE = 'Free';
  public static final String CHARGE_PAID = 'Paid';
  private static final String FAMILY_COMPRESSOR = 'Compressor';

  /**
   * @description 사용 부품의 자동 판정 값을 계산해 세팅 (DML 없음, before 트리거용)
   *              세팅 필드: AutoChargeType__c, WarrantyEndDateAtJudgment__c, PartCategoryAtUse__c, UnitPriceAtUse__c,
   *              ChargeType__c(비어 있을 때만)
   * @param parts 판정할 사용 부품 (WorkOrderId, ProductItemId 또는 Product2Id가 채워져 있어야 함)
   */
  public static void judgeChargeTypes(List<ProductConsumed> parts) {
    if (parts == null || parts.isEmpty()) {
      return;
    }

    Set<Id> workOrderIds = new Set<Id>();
    Set<Id> productItemIds = new Set<Id>();
    Set<Id> product2Ids = new Set<Id>();
    for (ProductConsumed part : parts) {
      if (part.WorkOrderId != null) {
        workOrderIds.add(part.WorkOrderId);
      }
      if (part.Product2Id != null) {
        product2Ids.add(part.Product2Id);
      } else if (part.ProductItemId != null) {
        productItemIds.add(part.ProductItemId);
      }
    }

    // PERF: 출동 + 접수 생성일 + 장비 보증 정보 조회 1회
    Map<Id, WorkOrder> workOrdersById = new Map<Id, WorkOrder>();
    if (!workOrderIds.isEmpty()) {
      workOrdersById = new Map<Id, WorkOrder>(
        [
          SELECT
            Id,
            CaseId,
            Case.CreatedDate,
            AssetId,
            Asset.HasExtendedWarranty__c,
            Asset.fmBasicWarrantyEndDate__c,
            Asset.fmCompressorWarrantyEndDate__c,
            Asset.fmExtendedWarrantyEndDate__c
          FROM WorkOrder
          WHERE Id IN :workOrderIds
        ]
      );
    }

    // PERF: 제품 항목 → 부품 조회 1회 (ProductItemId 방식으로 만든 사용 부품은 before insert 시점에 Product2Id가 비어 있음)
    Map<Id, Id> product2IdsByProductItem = new Map<Id, Id>();
    if (!productItemIds.isEmpty()) {
      for (ProductItem item : [
        SELECT Id, Product2Id
        FROM ProductItem
        WHERE Id IN :productItemIds
      ]) {
        product2IdsByProductItem.put(item.Id, item.Product2Id);
        product2Ids.add(item.Product2Id);
      }
    }

    // PERF: 부품 분류·ERP 단가 조회 1회
    Map<Id, Product2> productsById = new Map<Id, Product2>();
    if (!product2Ids.isEmpty()) {
      productsById = new Map<Id, Product2>(
        [
          SELECT Id, Family, ErpUnitPrice__c
          FROM Product2
          WHERE Id IN :product2Ids
        ]
      );
    }

    // DESC: 쿼리 결과 Map으로만 계산. 루프 안 SOQL/DML 없음
    for (ProductConsumed part : parts) {
      Id product2Id = (part.Product2Id != null)
        ? part.Product2Id
        : product2IdsByProductItem.get(part.ProductItemId);
      Product2 product = productsById.get(product2Id);
      WorkOrder workOrder = workOrdersById.get(part.WorkOrderId);

      String family = (product == null) ? null : product.Family;
      Date judgmentDate = getJudgmentDate(workOrder);
      Date endDate = getApplicableEndDate(workOrder, family);
      String autoChargeType = (endDate != null &&
        judgmentDate <= endDate)
        ? CHARGE_FREE
        : CHARGE_PAID;

      part.AutoChargeType__c = autoChargeType;
      part.WarrantyEndDateAtJudgment__c = endDate;
      part.PartCategoryAtUse__c = family;
      part.UnitPriceAtUse__c = (product == null)
        ? null
        : product.ErpUnitPrice__c;
      // WARN: 사람이 정한 최종 판정은 절대 덮어쓰지 않음 (예외 무상·판정 변경 사유 흐름 보호)
      if (String.isBlank(part.ChargeType__c)) {
        part.ChargeType__c = autoChargeType;
      }
    }
  }

  // DESC: 판정 기준일 = 출동의 접수 생성일. 출동·접수가 없으면 오늘
  @TestVisible
  private static Date getJudgmentDate(WorkOrder workOrder) {
    if (
      workOrder != null &&
      workOrder.CaseId != null &&
      workOrder.Case.CreatedDate != null
    ) {
      return workOrder.Case.CreatedDate.date();
    }
    return Date.today();
  }

  // DESC: 부품 분류별 적용 만료일. 장비가 없거나 보증 시작일이 미확정이면 null
  @TestVisible
  private static Date getApplicableEndDate(WorkOrder workOrder, String family) {
    if (workOrder == null || workOrder.AssetId == null) {
      return null;
    }
    Asset asset = workOrder.Asset;
    Boolean hasExtended = asset.HasExtendedWarranty__c == true;
    Date extendedEnd = hasExtended ? asset.fmExtendedWarrantyEndDate__c : null;

    if (family == FAMILY_COMPRESSOR) {
      return laterOf(asset.fmCompressorWarrantyEndDate__c, extendedEnd);
    }
    return hasExtended ? extendedEnd : asset.fmBasicWarrantyEndDate__c;
  }

  // DESC: 둘 중 늦은 날. 한쪽이 null이면 다른 쪽
  private static Date laterOf(Date a, Date b) {
    if (a == null) {
      return b;
    }
    if (b == null) {
      return a;
    }
    return (a > b) ? a : b;
  }
}
