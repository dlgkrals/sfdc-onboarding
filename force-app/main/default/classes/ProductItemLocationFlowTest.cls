/**
 * @description 저장 전 Flow ProductItem_BeforeSave_FillFromLocation 테스트
 *              재고의 서비스센터·창고 재고 = 위치의 서비스센터·유형(창고) — 재고 공유 규칙(조건 기준) 근거
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-16
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-16    Edwin     최초 작성 (창고 재고 공유 규칙 범위 결함 수정)
 * ----------------------------------------------------------------------------
 * @see ProductItem_BeforeSave_FillFromLocation, ProductItem.sharingRules HG_GyeonggiSouth_Warehouse_Stock_Tech
 */
@isTest
private class ProductItemLocationFlowTest {
  private static Schema.Location newLocation(String type, String center) {
    return new Schema.Location(
      Name = '테스트 ' + type + ' ' + center,
      LocationType = type,
      IsInventoryLocation = true,
      ServiceCenter__c = center
    );
  }

  // 정상: 창고 재고는 센터·창고 여부가 채워지고, 차량 재고는 창고 재고 아님
  @isTest
  static void normalCenterAndWarehouseCopied() {
    Product2 part = TestDataFactory.createProducts().get('General');
    Schema.Location warehouse = newLocation('Warehouse', 'GyeonggiSouth');
    Schema.Location van = newLocation('Van', 'Seoul');
    insert new List<Schema.Location>{ warehouse, van };

    Test.startTest();
    ProductItem whItem = new ProductItem(
      LocationId = warehouse.Id,
      Product2Id = part.Id,
      QuantityOnHand = 5
    );
    ProductItem vanItem = new ProductItem(
      LocationId = van.Id,
      Product2Id = part.Id,
      QuantityOnHand = 1
    );
    insert new List<ProductItem>{ whItem, vanItem };
    Test.stopTest();

    Map<Id, ProductItem> savedById = new Map<Id, ProductItem>(
      [
        SELECT Id, ServiceCenter__c, WarehouseStock__c
        FROM ProductItem
        WHERE Id IN (:whItem.Id, :vanItem.Id)
      ]
    );
    Assert.areEqual('GyeonggiSouth', savedById.get(whItem.Id).ServiceCenter__c);
    Assert.isTrue(savedById.get(whItem.Id).WarehouseStock__c, '창고 재고');
    Assert.areEqual('Seoul', savedById.get(vanItem.Id).ServiceCenter__c);
    Assert.isFalse(
      savedById.get(vanItem.Id).WarehouseStock__c,
      '차량 재고는 창고 재고 아님'
    );
  }

  // 불허(손으로 바꿔도 위치 기준으로 되돌림): 다른 센터로 고쳐 저장하면 위치의 센터로 다시 채움
  @isTest
  static void rejectManualCenterOverwritten() {
    Product2 part = TestDataFactory.createProducts().get('General');
    Schema.Location warehouse = newLocation('Warehouse', 'GyeonggiSouth');
    insert warehouse;
    ProductItem item = new ProductItem(
      LocationId = warehouse.Id,
      Product2Id = part.Id,
      QuantityOnHand = 5
    );
    insert item;

    Test.startTest();
    update new ProductItem(
      Id = item.Id,
      ServiceCenter__c = 'Seoul',
      WarehouseStock__c = false
    );
    Test.stopTest();

    ProductItem saved = [
      SELECT ServiceCenter__c, WarehouseStock__c
      FROM ProductItem
      WHERE Id = :item.Id
    ];
    Assert.areEqual(
      'GyeonggiSouth',
      saved.ServiceCenter__c,
      '위치 기준으로 되돌림'
    );
    Assert.isTrue(saved.WarehouseStock__c);
  }
}
