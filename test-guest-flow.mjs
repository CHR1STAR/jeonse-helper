import assert from 'node:assert/strict';
import { test } from 'node:test';

const { chromium } = await import(process.env.JEONSE_PLAYWRIGHT_MODULE || 'playwright');
const base = process.env.JEONSE_TEST_URL || 'http://127.0.0.1:8080';

test('guest registration, per-listing checks and resumption survive reload', async () => {
  const browser = await chromium.launch({
    executablePath: process.env.JEONSE_TEST_BROWSER || undefined,
  });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    // The guest test is deterministic without Supabase, OCR or CDN traffic.
    await page.route('**/*', route => new URL(route.request().url()).origin === new URL(base).origin
      ? route.continue() : route.abort());
    const click = name => page.getByRole('button', { name, exact: true }).click();
    const skip = () => click('아직 몰라요');
    const enterGuests = async () => {
      await click('비회원으로 계속하기');
      await click('확인');
      await click('집을 알아보고 있어요');
    };
    const add = async (name, kind) => {
      await click('+ 매물 등록');
      await page.getByRole('textbox', { name: '매물 이름' }).fill(name);
      await click('다음');
      await skip();
      await click(kind);
      await skip();
      if (kind === '월세') await skip();
      await click('사진은 나중에 등록할게요');
      await click('후보 매물 등록하기');
      await page.getByRole('button', { name: new RegExp(name) }).waitFor();
    };
    const open = name => page.locator('.listing-grid').getByRole('button', { name: new RegExp(name) }).click();
    const water = result => page.locator('input[data-visit-check][name="water"]').and(
      page.locator('input[value="' + result + '"]')
    );
    await page.goto(base);
    await enterGuests();
    await add('테스트 전세', '전세');
    await add('테스트 월세', '월세');
    await open('테스트 전세');
    await page.locator('.visit-option').filter({ has: water('문제 있음') }).click();
    await click('← 후보 목록');
    await open('테스트 월세');
    assert.equal(await water('미확인').isChecked(), true);
    await click('← 후보 목록');
    await open('테스트 전세');
    assert.equal(await water('문제 있음').isChecked(), true);
    await click('이 집으로 계약할게요');
    await click('계약 준비 시작');
    await click('확인했어요');
    await click('아직 확인하지 못했어요');
    await click('확인하고 나중에 이어하기');

    await page.reload();
    await enterGuests();
    await open('테스트 전세');
    assert.equal(await water('문제 있음').isChecked(), true);
    await click('← 후보 목록');
    await click('테스트 전세 계약 준비 이어하기');
    await page.getByRole('heading', { name: '집주인에게 하자에 대해 물어봤나요?' }).waitFor();
  } finally {
    await browser.close();
  }
});
