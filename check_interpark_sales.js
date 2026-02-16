
const { chromium } = require('playwright');
const path = require('path');

// --- 설정 ---
// 로그인 정보는 여기에 직접 입력하지 마세요!
// 아래 실행 방법 안내에 따라 환경 변수로 설정합니다.
const INTERPARK_ID = process.env.INTERPARK_ID;
const INTERPARK_PASSWORD = process.env.INTERPARK_PASSWORD;

if (!INTERPARK_ID || !INTERPARK_PASSWORD) {
  console.error('오류: 인터파크 아이디와 비밀번호를 환경 변수로 설정해야 합니다.');
  console.error('실행 예시:');
  console.error('export INTERPARK_ID="your_id"');
  console.error('export INTERPARK_PASSWORD="your_password"');
  console.error('node check_interpark_sales.js');
  process.exit(1);
}

// 오늘 날짜를 'YYYYMMDD' 형식으로 가져옵니다.
function getTodayString() {
  const today = new Date();
  const year = today.getFullYear();
  const month = String(today.getMonth() + 1).padStart(2, '0');
  const day = String(today.getDate()).padStart(2, '0');
  return `${year}${month}${day}`;
}


async function main() {
  console.log('📊 인터파크 판매 현황 확인을 시작합니다...');

  const browser = await chromium.launch({
    headless: false, // false로 설정하면 브라우저가 실제로 열려서 과정을 볼 수 있습니다. 자동화가 안정되면 true로 바꾸세요.
  });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    // 1. 로그인 페이지로 이동
    console.log('1. 로그인 페이지로 이동 중...');
    await page.goto('https://tadmin20.interpark.com/');

    // 팝업 자동 닫기 리스너 설정
    page.on('dialog', async dialog => {
      console.log(`'${dialog.message()}' 팝업이 나타나 자동으로 닫습니다.`);
      await dialog.dismiss();
    });

    // 2. 아이디와 비밀번호 입력 및 로그인
    console.log('2. 로그인 정보 입력 중...');

    // 로그인 페이지 팝업 닫기 시도 (오류가 나도 계속 진행)
    try {
      console.log('로그인 페이지 팝업 X 버튼을 찾아 닫기를 시도합니다...');
      // 팝업의 'X' 닫기 버튼을 찾아서 클릭 (aria-label이 '닫기' 또는 'close'인 경우 등)
      const closeButton = page.locator('[aria-label*="닫기" i], [aria-label*="close" i], button:has-text("X")').first();
      await closeButton.waitFor({ state: 'visible', timeout: 5000 }); // 5초간 기다림
      await closeButton.click();
      console.log('팝업 X 버튼을 클릭했습니다.');
    } catch (e) {
      console.log('처리할 팝업 X 버튼이 없거나 5초 안에 찾지 못했습니다. 로그인을 계속합니다.');
    }

    await page.waitForSelector('input[name="userId"]');
    await page.locator('input[name="userId"]').fill(INTERPARK_ID);
    await page.locator('input[name="userPwd"]').fill(INTERPARK_PASSWORD);
    await page.locator('button:has-text("로그인")').click();
    console.log('로그인 성공!');

    // 3. 일별판매현황 페이지로 이동
    console.log('3. 일별판매현황 페이지로 이동 중...');
    await page.waitForURL('**/Home/Index');
    await page.goto('https://tadmin20.interpark.com/stat/dailysalesinfo');
    
    console.log('4. 상품(공연) 목록 팝업 열기...');
    // '상품' 글자 옆에 있는 돋보기 버튼을 기다려서 클릭합니다.
    const searchButton = page.locator('span.search-label:has-text("상품") + div.input-group span.button');
    await searchButton.waitFor({ state: 'visible' });
    await searchButton.click();

    // 5. 팝업에서 오늘 이후 공연만 필터링
    console.log('5. 오늘 이후의 공연을 찾는 중...');
    // 팝업 안의 테이블 로드를 기다립니다.
    const popupFrame = page.frameLocator('iframe#ifrmPopup'); // 팝업이 iframe일 경우를 대비
    const performanceTable = popupFrame.locator('div#divSearchResult > table');
    await performanceTable.waitFor({ state: 'visible' });

    const rows = await performanceTable.locator('tbody tr').all();
    const futurePerformances = [];
    const today = getTodayString();

    for (const row of rows) {
      // 시작일이 7번째 컬럼(td)에 있다고 가정합니다. 실제 구조에 맞게 인덱스를 조정해야 할 수 있습니다.
      const startDate = await row.locator('td').nth(6).innerText();
      const performanceName = await row.locator('td').nth(1).innerText();

      if (parseInt(startDate, 10) >= parseInt(today, 10)) {
        futurePerformances.push({ name: performanceName, element: row });
      }
    }
    
    if (futurePerformances.length === 0) {
        console.log('오늘 이후의 공연이 없습니다.');
        await browser.close();
        return;
    }
    
    console.log(`확인할 공연: ${futurePerformances.map(p => p.name).join(', ')}`);

    // --- 이 아래 부분은 실제 페이지 구조에 따라 수정이 필요할 수 있습니다 ---
    const results = [];
    for (const perf of futurePerformances) {
        console.log(`- ${perf.name} 판매량 확인...`);
        
        // 공연 클릭
        await perf.element.locator('td').nth(1).click();
        
        // 팝업이 닫히고 메인 페이지로 돌아올 때까지 기다립니다.
        await page.waitForTimeout(1000); // 잠시 대기

        // 조회 버튼 클릭
        await page.locator('button:has-text("조회")').click();
        await page.waitForLoadState('networkidle'); // 네트워크 활동이 끝날 때까지 대기
        
        // TODO: 판매량이 표시되는 실제 요소를 찾아야 합니다.
        // 아래는 예시이며, 실제 클래스 이름이나 ID로 변경해야 합니다.
        const salesCountElement = page.locator('.daily-sales-count'); 
        let salesCount = '확인 불가';
        try {
            await salesCountElement.waitFor({ state: 'visible', timeout: 3000 });
            salesCount = await salesCountElement.innerText();
        } catch (e) {
            console.warn(`  - '${perf.name}'의 판매량을 찾을 수 없습니다. (페이지 구조 확인 필요)`);
        }
        
        results.push({ 공연명: perf.name, '오늘 판매량': salesCount });
        
        // 다음 공연을 위해 다시 팝업을 엽니다.
        await searchButton.click();
        await performanceTable.waitFor({ state: 'visible' });
    }

    // 최종 결과 출력
    console.log('\n--- 최종 결과 ---');
    console.table(results);


  } catch (error) {
    console.error('스크립트 실행 중 오류가 발생했습니다:', error);
    // 오류 발생 시 스크린샷을 저장하여 디버깅에 도움을 줍니다.
    const screenshotPath = path.join(__dirname, 'error_screenshot.png');
    await page.screenshot({ path: screenshotPath });
    console.log(`오류 발생 시점의 스크린샷이 ${screenshotPath} 에 저장되었습니다.`);

  } finally {
    await browser.close();
    console.log('✅ 작업 완료.');
  }
}

main();

