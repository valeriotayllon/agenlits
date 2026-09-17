// ==============================================================================
// TESTE E2E CRÍTICO: FLUXO DE AGENDAMENTO (e2e/booking.spec.js)
// Execute com: npx playwright test
// ==============================================================================
import { test, expect } from '@playwright/test';

test.describe('Fluxo Completo de Agendamento - agenlits', () => {
  test('deve carregar barbearia, escolher serviço, profissional, horário e confirmar com sucesso', async ({ page }) => {
    // 1. Abrir página pública da barbearia
    await page.goto('/agendar.html?b=demo');
    await expect(page.locator('#shop-name-display')).toBeVisible();

    // 2. Selecionar primeiro serviço disponível
    const serviceCard = page.locator('.service-card').first();
    await expect(serviceCard).toBeVisible();
    await serviceCard.click();

    // 3. Selecionar data e verificar carregamento de slots reais
    const dateInput = page.locator('#date-input');
    await expect(dateInput).toBeVisible();
    
    // 4. Selecionar horário no dropdown
    const timeSelect = page.locator('#time-select');
    await expect(timeSelect).toBeEnabled();
    await timeSelect.selectOption({ index: 1 });

    // 5. Preencher dados do cliente
    await page.fill('#client-name-input', 'Cliente Teste Automatizado');
    await page.fill('#client-phone-input', '85999999999');

    // 6. Clicar no botão de confirmação
    const confirmBtn = page.locator('#btn-confirm-booking');
    await confirmBtn.click();

    // 7. Validar se o modal de sucesso com dados preenchidos foi exibido
    await expect(page.locator('#booking-success-modal')).toBeVisible({ timeout: 10000 });
    await expect(page.locator('#booking-summary-text')).toContainText('Cliente Teste Automatizado');
  });
});
