/**
 * SpeakDine Stripe Payment Server
 *
 * Lightweight Express server handling Stripe operations.
 * Deploy on Render (free tier) with environment variables:
 *   STRIPE_SECRET_KEY, APP_BASE_URL, PORT
 */

require('dotenv').config();
const express = require('express');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY;
const APP_BASE_URL = process.env.APP_BASE_URL || 'http://localhost:5000';
const PORT = process.env.PORT || 3001;

if (!STRIPE_SECRET_KEY) {
  console.error('STRIPE_SECRET_KEY environment variable is required');
  process.exit(1);
}

const stripe = require('stripe')(STRIPE_SECRET_KEY);

app.get('/health', (_req, res) => {
  res.json({ status: 'ok' });
});

/**
 * Create a Stripe Customer for a user.
 * Body: { email, name, userId }
 * Returns: { customerId }
 */
app.post('/create-customer', async (req, res) => {
  try {
    const { email, name, userId } = req.body;

    if (!email || !userId) {
      return res.status(400).json({ error: 'email and userId are required' });
    }

    const customer = await stripe.customers.create({
      email,
      name: name || undefined,
      metadata: { firebaseUid: userId },
    });

    res.json({ customerId: customer.id });
  } catch (err) {
    console.error('[create-customer]', err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * Create a Stripe Checkout Session for payment.
 * Body: { customerId, items: [{ name, quantity, priceInPaisa }], orderId, currency }
 * Returns: { url, sessionId }
 */
app.post('/create-checkout-session', async (req, res) => {
  try {
    const { customerId, items, orderId, currency, appBaseUrl } = req.body;
    const baseUrl = appBaseUrl || APP_BASE_URL;

    if (!items || !items.length || !orderId) {
      return res.status(400).json({ error: 'items and orderId are required' });
    }

    const lineItems = items.map((item) => ({
      price_data: {
        currency: currency || 'pkr',
        product_data: { name: item.name },
        unit_amount: item.priceInPaisa,
      },
      quantity: item.quantity,
    }));

    const sessionParams = {
      mode: 'payment',
      line_items: lineItems,
      success_url: `${baseUrl}/`,
      cancel_url: `${baseUrl}/`,
      metadata: { orderId },
    };

    if (customerId) {
      sessionParams.customer = customerId;
    }

    const session = await stripe.checkout.sessions.create(sessionParams);

    res.json({ url: session.url, sessionId: session.id });
  } catch (err) {
    console.error('[create-checkout-session]', err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * Create a Stripe Checkout Session in setup mode (save card only).
 * Body: { customerId }
 * Returns: { url, sessionId }
 */
app.post('/create-setup-session', async (req, res) => {
  try {
    const { customerId, appBaseUrl } = req.body;
    const baseUrl = appBaseUrl || APP_BASE_URL;

    if (!customerId) {
      return res.status(400).json({ error: 'customerId is required' });
    }

    const session = await stripe.checkout.sessions.create({
      mode: 'setup',
      customer: customerId,
      success_url: `${baseUrl}/`,
      cancel_url: `${baseUrl}/`,
      payment_method_types: ['card'],
    });

    res.json({ url: session.url, sessionId: session.id });
  } catch (err) {
    console.error('[create-setup-session]', err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * Get saved payment methods for a customer.
 * Body: { customerId }
 * Returns: { cards: [{ id, brand, last4, expMonth, expYear }] }
 */
app.post('/get-saved-cards', async (req, res) => {
  try {
    const { customerId } = req.body;

    if (!customerId) {
      return res.status(400).json({ error: 'customerId is required' });
    }

    const paymentMethods = await stripe.paymentMethods.list({
      customer: customerId,
      type: 'card',
    });

    const cards = paymentMethods.data.map((pm) => ({
      id: pm.id,
      brand: pm.card.brand,
      last4: pm.card.last4,
      expMonth: pm.card.exp_month,
      expYear: pm.card.exp_year,
    }));

    res.json({ cards });
  } catch (err) {
    console.error('[get-saved-cards]', err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * Delete (detach) a saved payment method.
 * Body: { paymentMethodId }
 * Returns: { success: true }
 */
app.post('/delete-saved-card', async (req, res) => {
  try {
    const { paymentMethodId } = req.body;

    if (!paymentMethodId) {
      return res.status(400).json({ error: 'paymentMethodId is required' });
    }

    await stripe.paymentMethods.detach(paymentMethodId);

    res.json({ success: true });
  } catch (err) {
    console.error('[delete-saved-card]', err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * Charge a saved card (for voice-command payments).
 * Body: { customerId, paymentMethodId, amountInPaisa, orderId, currency }
 * Returns: { success, paymentIntentId }
 */
app.post('/charge-saved-card', async (req, res) => {
  try {
    const { customerId, paymentMethodId, amountInPaisa, orderId, currency } =
      req.body;

    if (!customerId || !paymentMethodId || !amountInPaisa || !orderId) {
      return res.status(400).json({
        error:
          'customerId, paymentMethodId, amountInPaisa, and orderId are required',
      });
    }

    const paymentIntent = await stripe.paymentIntents.create({
      amount: amountInPaisa,
      currency: currency || 'pkr',
      customer: customerId,
      payment_method: paymentMethodId,
      off_session: true,
      confirm: true,
      metadata: { orderId },
    });

    res.json({
      success: paymentIntent.status === 'succeeded',
      paymentIntentId: paymentIntent.id,
      status: paymentIntent.status,
    });
  } catch (err) {
    console.error('[charge-saved-card]', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── Stripe Connect ───

const PLATFORM_FEE_PERCENT = 5;

/**
 * Create a Stripe Connect account for a restaurant and return an onboarding link.
 * Body: { restaurantId, email, businessName, appBaseUrl }
 * Returns: { accountId, onboardingUrl }
 */
app.post('/create-connect-account', async (req, res) => {
  try {
    const { restaurantId, email, businessName, appBaseUrl } = req.body;
    const baseUrl = appBaseUrl || APP_BASE_URL;

    if (!restaurantId || !email) {
      return res.status(400).json({ error: 'restaurantId and email are required' });
    }

    const account = await stripe.accounts.create({
      type: 'express',
      email,
      business_profile: { name: businessName || undefined },
      metadata: { firebaseRestaurantId: restaurantId },
    });

    const accountLink = await stripe.accountLinks.create({
      account: account.id,
      refresh_url: `${baseUrl}/`,
      return_url: `${baseUrl}/`,
      type: 'account_onboarding',
    });

    res.json({ accountId: account.id, onboardingUrl: accountLink.url });
  } catch (err) {
    console.error('[create-connect-account]', err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * Generate a fresh onboarding link for an existing Connect account.
 * Body: { accountId, appBaseUrl }
 * Returns: { onboardingUrl }
 */
app.post('/connect-onboarding-link', async (req, res) => {
  try {
    const { accountId, appBaseUrl } = req.body;
    const baseUrl = appBaseUrl || APP_BASE_URL;

    if (!accountId) {
      return res.status(400).json({ error: 'accountId is required' });
    }

    const accountLink = await stripe.accountLinks.create({
      account: accountId,
      refresh_url: `${baseUrl}/`,
      return_url: `${baseUrl}/`,
      type: 'account_onboarding',
    });

    res.json({ onboardingUrl: accountLink.url });
  } catch (err) {
    console.error('[connect-onboarding-link]', err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * Check if a Connect account has completed onboarding.
 * Body: { accountId }
 * Returns: { chargesEnabled, payoutsEnabled, detailsSubmitted }
 */
app.post('/connect-account-status', async (req, res) => {
  try {
    const { accountId } = req.body;

    if (!accountId) {
      return res.status(400).json({ error: 'accountId is required' });
    }

    const account = await stripe.accounts.retrieve(accountId);

    res.json({
      chargesEnabled: account.charges_enabled,
      payoutsEnabled: account.payouts_enabled,
      detailsSubmitted: account.details_submitted,
    });
  } catch (err) {
    console.error('[connect-account-status]', err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * Create a Checkout Session with split payment (platform keeps 5% + COD debt recovery).
 * Body: { customerId, items, orderId, currency, connectedAccountId, appBaseUrl, platformDebtPaisa }
 * Returns: { url, sessionId, normalFeePaisa, debtRecoveredPaisa, totalApplicationFeePaisa, restaurantAmountPaisa }
 */
app.post('/create-connected-checkout', async (req, res) => {
  try {
    const { customerId, items, orderId, currency, connectedAccountId, appBaseUrl, platformDebtPaisa } = req.body;
    const baseUrl = appBaseUrl || APP_BASE_URL;
    const debt = Math.max(0, Math.round(platformDebtPaisa || 0));

    if (!items || !items.length || !orderId || !connectedAccountId) {
      return res.status(400).json({
        error: 'items, orderId, and connectedAccountId are required',
      });
    }

    const lineItems = items.map((item) => ({
      price_data: {
        currency: currency || 'pkr',
        product_data: { name: item.name },
        unit_amount: item.priceInPaisa,
      },
      quantity: item.quantity,
    }));

    const totalAmountPaisa = items.reduce(
      (sum, item) => sum + item.priceInPaisa * item.quantity,
      0
    );
    const normalFeePaisa = Math.round(totalAmountPaisa * PLATFORM_FEE_PERCENT / 100);
    const debtRecoveredPaisa = Math.min(debt, totalAmountPaisa - normalFeePaisa);
    const totalApplicationFeePaisa = normalFeePaisa + Math.max(0, debtRecoveredPaisa);

    const sessionParams = {
      mode: 'payment',
      line_items: lineItems,
      success_url: `${baseUrl}/`,
      cancel_url: `${baseUrl}/`,
      metadata: { orderId },
      payment_intent_data: {
        application_fee_amount: totalApplicationFeePaisa,
        transfer_data: { destination: connectedAccountId },
      },
    };

    if (customerId) {
      sessionParams.customer = customerId;
    }

    const session = await stripe.checkout.sessions.create(sessionParams);

    res.json({
      url: session.url,
      sessionId: session.id,
      normalFeePaisa,
      debtRecoveredPaisa: Math.max(0, debtRecoveredPaisa),
      totalApplicationFeePaisa,
      restaurantAmountPaisa: totalAmountPaisa - totalApplicationFeePaisa,
    });
  } catch (err) {
    console.error('[create-connected-checkout]', err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * Charge a saved card with split payment (platform keeps 5% + COD debt recovery).
 * Body: { customerId, paymentMethodId, amountInPaisa, orderId, currency, connectedAccountId, platformDebtPaisa }
 * Returns: { success, paymentIntentId, normalFeePaisa, debtRecoveredPaisa, totalApplicationFeePaisa, restaurantAmountPaisa }
 */
app.post('/charge-saved-card-connected', async (req, res) => {
  try {
    const { customerId, paymentMethodId, amountInPaisa, orderId, currency, connectedAccountId, platformDebtPaisa } = req.body;
    const debt = Math.max(0, Math.round(platformDebtPaisa || 0));

    if (!customerId || !paymentMethodId || !amountInPaisa || !orderId || !connectedAccountId) {
      return res.status(400).json({
        error: 'customerId, paymentMethodId, amountInPaisa, orderId, and connectedAccountId are required',
      });
    }

    const normalFeePaisa = Math.round(amountInPaisa * PLATFORM_FEE_PERCENT / 100);
    const debtRecoveredPaisa = Math.min(debt, amountInPaisa - normalFeePaisa);
    const totalApplicationFeePaisa = normalFeePaisa + Math.max(0, debtRecoveredPaisa);

    const paymentIntent = await stripe.paymentIntents.create({
      amount: amountInPaisa,
      currency: currency || 'pkr',
      customer: customerId,
      payment_method: paymentMethodId,
      off_session: true,
      confirm: true,
      application_fee_amount: totalApplicationFeePaisa,
      transfer_data: { destination: connectedAccountId },
      metadata: { orderId },
    });

    res.json({
      success: paymentIntent.status === 'succeeded',
      paymentIntentId: paymentIntent.id,
      status: paymentIntent.status,
      normalFeePaisa,
      debtRecoveredPaisa: Math.max(0, debtRecoveredPaisa),
      totalApplicationFeePaisa,
      restaurantAmountPaisa: amountInPaisa - totalApplicationFeePaisa,
    });
  } catch (err) {
    console.error('[charge-saved-card-connected]', err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * Get a Stripe Connect Express dashboard login link.
 * Body: { accountId }
 * Returns: { url }
 */
app.post('/connect-dashboard-link', async (req, res) => {
  try {
    const { accountId } = req.body;

    if (!accountId) {
      return res.status(400).json({ error: 'accountId is required' });
    }

    const loginLink = await stripe.accounts.createLoginLink(accountId);
    res.json({ url: loginLink.url });
  } catch (err) {
    console.error('[connect-dashboard-link]', err.message);
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`SpeakDine Stripe server running on port ${PORT}`);
});
