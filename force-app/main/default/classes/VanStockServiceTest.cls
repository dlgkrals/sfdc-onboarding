/**
 * @description VanStockService 테스트 — 트리거 경로(표준 insert)의 차량 재고 초과 거부·경계·묶음 누적
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-14
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-14    Edwin     최초 작성 (D8 보안 점검 R1: 화면 밖 경로 초과 거부)
 * ----------------------------------------------------------------------------
 * @see VanStockService, ProductConsumedTriggerHandler, WorkOrderPartsControllerTest(화면 경로)
 */
@isTest
private class VanStockServiceTest {
  private static final Decimal VAN_QUANTITY = 300;

  @TestSetup
  static void setupData() {
    Account account = TestDataFactory.createAccount();
    CustomerSite__c site = TestDataFactory.createSite(account.Id);
    List<Asset> assets = TestDataFactory.createAssets(
      account.Id,
      site.Id,
      'TEST-VSS-',
      1
    );
    TestDataFactory.createWorkOrders(TestDataFactory.createCases(assets, 1));
    Map<String, ProductItem> itemsByFamily = TestDataFactory.createVanStock(
      TestDataFactory.createProducts(),
      VAN_QUANTITY
    );
    update new ProductItem(
      Id = itemsByFamily.get('General').Id,
      QuantityUnitOfMeasure = 'kg'
    );
  }

  private static Id getWorkOrderId() {
    return [SELECT Id FROM WorkOrder LIMIT 1].Id;
  }

  private static ProductItem getItem(String family) {
    return [
      SELECT Id, QuantityOnHand
      FROM ProductItem
      WHERE
        Product2.Family = :family
        AND Location.Name = :TestDataFactory.VAN_NAME
      LIMIT 1
    ];
  }

  private static ProductConsumed buildPart(Id itemId, Decimal quantity) {
    return buildPart(getWorkOrderId(), itemId, quantity);
  }

  private static ProductConsumed buildPart(
    Id workOrderId,
    Id itemId,
    Decimal quantity
  ) {
    ProductConsumed part = TestDataFactory.buildPart(workOrderId, itemId);
    part.QuantityConsumed = quantity;
    return part;
  }

  // 불허: 화면을 거치지 않고(표준 새로 만들기·데이터 로더와 같은 insert) 남은 수량보다 많이 쓰면 트리거가 거부, 문구는 화면과 같음
  @isTest
  static void rejectOverRemainingViaTrigger() {
    ProductItem general = getItem('General');
    String message;

    Test.startTest();
    try {
      insert buildPart(general.Id, VAN_QUANTITY + 0.5);
    } catch (DmlException e) {
      message = e.getDmlMessage(0);
    }
    Test.stopTest();

    Assert.areEqual(
      String.format(
        System.Label.MSG_STOCK_SHORT,
        new List<String>{
          String.valueOf(VAN_QUANTITY.intValue()),
          System.Label.MISC_UNIT_KG
        }
      ),
      message,
      '부품 추가 화면과 같은 문구 (남은 300kg)'
    );
    Assert.areEqual(0, [SELECT COUNT() FROM ProductConsumed], '저장 안 됨');
    Assert.areEqual(
      VAN_QUANTITY,
      getItem('General').QuantityOnHand,
      '재고 그대로'
    );
  }

  // 정상(경계): 트리거 경로에서도 정확히 남은 수량만큼은 허용 → 차량 재고 0
  @isTest
  static void normalExactRemainingViaTrigger() {
    Test.startTest();
    insert buildPart(getItem('General').Id, VAN_QUANTITY);
    Test.stopTest();

    Assert.areEqual(1, [SELECT COUNT() FROM ProductConsumed], '저장됨');
    Assert.areEqual(0, getItem('General').QuantityOnHand, '남은 수량 0');
  }

  // 불허: 남은 수량 0인 재고 → "재고 없음" 문구 (화면과 같음)
  @isTest
  static void rejectEmptyStockViaTrigger() {
    ProductItem compressor = getItem('Compressor');
    update new ProductItem(Id = compressor.Id, QuantityOnHand = 0);
    String message;

    Test.startTest();
    try {
      insert buildPart(compressor.Id, 1);
    } catch (DmlException e) {
      message = e.getDmlMessage(0);
    }
    Test.stopTest();

    Assert.areEqual(System.Label.MSG_STOCK_EMPTY, message, '재고 없음 문구');
  }

  // 벌크: 같은 재고 200건(1.5kg씩 = 정확히 300kg) + 1건 → 순서대로 누적, 200건 저장·마지막 1건만 거부(남은 0)
  @isTest
  static void bulkSameItemCumulativeInOrder() {
    Id itemId = getItem('General').Id;
    Id workOrderId = getWorkOrderId();
    List<ProductConsumed> parts = new List<ProductConsumed>();
    for (Integer i = 0; i < 201; i++) {
      parts.add(buildPart(workOrderId, itemId, 1.5));
    }

    Test.startTest();
    List<Database.SaveResult> results = Database.insert(parts, false);
    Test.stopTest();

    Integer saved = 0;
    for (Database.SaveResult result : results) {
      if (result.isSuccess()) {
        saved++;
      }
    }
    Assert.areEqual(200, saved, '남은 수량까지 200건 저장');
    Assert.isFalse(results[200].isSuccess(), '201번째 거부');
    Assert.areEqual(
      System.Label.MSG_STOCK_EMPTY,
      results[200].getErrors()[0].getMessage(),
      '남은 0 → 재고 없음 문구'
    );
    Assert.areEqual(0, getItem('General').QuantityOnHand, '남은 수량 0');
  }

  // 정상: 단위 표기 (Each → 개, kg, 없음 → 빈 값, 그 외 값 그대로)
  @isTest
  static void normalUnitLabels() {
    Assert.areEqual(
      System.Label.MISC_UNIT_EACH,
      VanStockService.unitLabelOf('Each'),
      'Each'
    );
    Assert.areEqual('', VanStockService.unitLabelOf(null), '없음');
    Assert.areEqual('L', VanStockService.unitLabelOf('L'), '그 외');
    Assert.areEqual(
      System.Label.MSG_STOCK_EMPTY,
      VanStockService.stockMessage(null, 'kg'),
      '수량 없음 → 재고 없음'
    );
  }
}
