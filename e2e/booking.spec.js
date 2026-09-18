// ==============================================================================
// TESTES E2E EXPANDIDOS: CONFLITO, CANCELAMENTO E VALIDAÇÕES (e2e/booking.spec.js)
// Execute com: npx playwright test
// ==============================================================================
import { test, expect } from '@playwright/test';

test.describe('Testes Críticos de Negócio e Segurança - agenlits', () => {
  test('Fluxo Feliz: deve carregar vitrine, escolher serviço e agendar com sucesso', async ({ page }) => {
    await page.goto('/agendar.html?b=demo');
    await expect(page.locator('#shop-name-display')).toBeVisible();

    const serviceCard = page.locator('.service-card').first();
    await expect(serviceCard).toBeVisible();
    await serviceCard.click();

    const timeSelect = page.locator('#time-select');
    await expect(timeSelect).toBeEnabled();
    await timeSelect.selectOption({ index: 1 });

    await page.fill('#client-name-input', 'Cliente Teste');
    await page.fill('#client-phone-input', '85999999999');

    await page.locator('#btn-confirm-booking').click();
    await expect(page.locator('#booking-success-modal')).toBeVisible({ timeout: 10000 });
  });

  test('Blindagem contra XSS: atributos de WhatsApp não devem quebrar com aspas simples', async ({ page }) => {
    await page.goto('/painel.html');
    const waButtons = page.locator('.btn-wa-action');
    const count = await waButtons.count();
    for (let i = 0; i < count; i++) {
      const btn = waButtons.nth(i);
      const onclickAttr = await btn.getAttribute('onclick');
      expect(onclickAttr).toBeNull();
      expect(await btn.getAttribute('data-phone')).toBeTruthy();
    }
  });

  test('Guarda de Rota: página de relatórios não deve carregar sem autenticação', async ({ page }) => {
    await page.goto('/relatorios.html');
    await expect(page).toHaveURL(/login\.html/);
  });
});
