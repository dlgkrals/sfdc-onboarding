/**
 * @description ServiceCenterMappingService 테스트 (실제 ServiceCenterMapping__mdt 레코드 사용)
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성
 * ----------------------------------------------------------------------------
 * @see ServiceCenterMappingService
 */
@isTest
private class ServiceCenterMappingServiceTest {
  // 정상: 시군구 5자리 매핑이 시도 2자리보다 우선 (경기북부 vs 경기남부)
  @isTest
  static void normalSigunguBeforeSido() {
    Assert.areEqual(
      'GyeonggiNorth',
      ServiceCenterMappingService.resolveServiceCenter('4115010100'),
      '의정부 → 경기북부'
    );
    Assert.areEqual(
      'GyeonggiNorth',
      ServiceCenterMappingService.resolveServiceCenter('4128510100'),
      '고양 일산동구 → 경기북부'
    );
    Assert.areEqual(
      'GyeonggiNorth',
      ServiceCenterMappingService.resolveServiceCenter('4182025000'),
      '가평 → 경기북부'
    );
    Assert.areEqual(
      'GyeonggiSouth',
      ServiceCenterMappingService.resolveServiceCenter('4122010100'),
      '평택 → 경기 기본(남부)'
    );
    Assert.areEqual(
      'GyeonggiSouth',
      ServiceCenterMappingService.resolveServiceCenter('4111712230'),
      '수원 → 경기 기본(남부)'
    );
  }

  // 정상: 시도 2자리 매핑
  @isTest
  static void normalSidoMapping() {
    Assert.areEqual(
      'Seoul',
      ServiceCenterMappingService.resolveServiceCenter('1144012000'),
      '서울'
    );
    Assert.areEqual(
      'GyeonggiSouth',
      ServiceCenterMappingService.resolveServiceCenter('2818510600'),
      '인천'
    );
    Assert.areEqual(
      'Chungcheong',
      ServiceCenterMappingService.resolveServiceCenter('3611011000'),
      '세종'
    );
    Assert.areEqual(
      'Jeju',
      ServiceCenterMappingService.resolveServiceCenter('5011010100'),
      '제주'
    );
  }

  // 정상: 최신·옛 시도 코드 모두 (강원 51/42, 전북 52/45, 군위군 대구 27720/옛 경북 47720)
  @isTest
  static void normalNewAndOldSidoCodes() {
    Assert.areEqual(
      'Gangwon',
      ServiceCenterMappingService.resolveServiceCenter('5111010100'),
      '강원특별자치도 51'
    );
    Assert.areEqual(
      'Gangwon',
      ServiceCenterMappingService.resolveServiceCenter('4211010100'),
      '옛 강원도 42'
    );
    Assert.areEqual(
      'Honam',
      ServiceCenterMappingService.resolveServiceCenter('5211110100'),
      '전북특별자치도 52'
    );
    Assert.areEqual(
      'Honam',
      ServiceCenterMappingService.resolveServiceCenter('4511110100'),
      '옛 전라북도 45'
    );
    Assert.areEqual(
      'Yeongnam',
      ServiceCenterMappingService.resolveServiceCenter('2772025000'),
      '군위군(대구)'
    );
    Assert.areEqual(
      'Yeongnam',
      ServiceCenterMappingService.resolveServiceCenter('4772025000'),
      '옛 군위군(경북)'
    );
  }

  // 불허: 빈 값·너무 짧은 값·매핑 없는 코드 → null (사용자가 직접 선택)
  @isTest
  static void rejectUnknownCodesReturnNull() {
    Assert.isNull(
      ServiceCenterMappingService.resolveServiceCenter(null),
      'null'
    );
    Assert.isNull(
      ServiceCenterMappingService.resolveServiceCenter(''),
      '빈 값'
    );
    Assert.isNull(
      ServiceCenterMappingService.resolveServiceCenter('4'),
      '1자리'
    );
    Assert.isNull(
      ServiceCenterMappingService.resolveServiceCenter('9911010100'),
      '없는 시도'
    );
  }

  // 정상: 매핑의 센터 값은 모두 사업장 서비스센터 picklist에 있는 값 (오타로 저장 실패 방지)
  @isTest
  static void normalMappingValuesAreValidPicklistValues() {
    Set<String> valid = new Set<String>();
    for (
      Schema.PicklistEntry entry : CustomerSite__c.ServiceCenter__c.getDescribe()
        .getPicklistValues()
    ) {
      if (entry.isActive()) {
        valid.add(entry.getValue());
      }
    }
    for (
      ServiceCenterMapping__mdt row : ServiceCenterMapping__mdt.getAll()
        .values()
    ) {
      Assert.isTrue(
        valid.contains(row.ServiceCenter__c),
        row.MasterLabel + ' 센터 값: ' + row.ServiceCenter__c
      );
    }
  }
}
