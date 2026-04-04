import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'package:speak_dine/config/api_keys.dart';
import 'package:speak_dine/services/cart_service.dart';

import 'package:speak_dine/services/stripe_checkout_url_stub.dart'
    if (dart.library.html) 'package:speak_dine/services/stripe_checkout_url_web.dart'
    as stripe_checkout_url;

String? _getAppBaseUrl() {
  if (!kIsWeb) return null;
  try {
    return Uri.base.origin;
  } catch (_) {
    return null;
  }
}

class SavedCard {
  final String id;
  final String brand;
  final String last4;
  final int expMonth;
  final int expYear;

  const SavedCard({
    required this.id,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
  });
}

class PaymentService {
  static final _firestore = FirebaseFirestore.instance;

  /// After Stripe Checkout redirects back to the app (web), verify payment and
  /// mark Firestore orders as paid. Safe to call on every launch; no-ops if no
  /// `session_id` in the URL.
  static Future<void> handleStripeCheckoutReturnIfPresent() async {
    if (!kIsWeb) return;
    if (stripeServerUrl.trim().isEmpty) return;

    final uri = Uri.base;
    final sessionId = uri.queryParameters['session_id']?.trim();
    if (sessionId == null || sessionId.isEmpty) return;
    if (uri.queryParameters['stripe_checkout'] != '1') return;

    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      try {
        await FirebaseAuth.instance
            .authStateChanges()
            .where((u) => u != null)
            .first
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      user = FirebaseAuth.instance.currentUser;
    }
    if (user == null) {
      for (var i = 0; i < 40; i++) {
        user = FirebaseAuth.instance.currentUser;
        if (user != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    final userFinal = user;
    if (userFinal == null) {
      debugPrint('[PaymentService] Checkout return: no signed-in user');
      stripe_checkout_url.clearStripeCheckoutQueryFromBrowserUrl();
      return;
    }

    final result = await _post('/verify-checkout-session', {
      'sessionId': sessionId,
    });

    void clearCheckoutUrl() {
      stripe_checkout_url.clearStripeCheckoutQueryFromBrowserUrl();
    }

    if (result == null || result['paid'] != true) {
      debugPrint('[PaymentService] Checkout verify: not paid or failed');
      clearCheckoutUrl();
      return;
    }

    final orderId = result['orderId'] as String?;
    final metaUid = result['firebaseUid'] as String?;
    if (orderId == null || orderId.isEmpty) {
      debugPrint('[PaymentService] Checkout verify: missing orderId in session');
      clearCheckoutUrl();
      return;
    }

    if (metaUid != null && metaUid.isNotEmpty && metaUid != userFinal.uid) {
      debugPrint('[PaymentService] Checkout verify: order belongs to another user');
      clearCheckoutUrl();
      return;
    }

    final custRef = _firestore
        .collection('users')
        .doc(userFinal.uid)
        .collection('orders')
        .doc(orderId);
    final txRef =
        _firestore.collection('transactions').doc('checkout_$orderId');
    final existingTx = await txRef.get();
    if (existingTx.exists) {
      debugPrint('[PaymentService] Checkout already recorded for $orderId');
      clearCheckoutUrl();
      return;
    }

    final snap = await custRef.get();
    if (!snap.exists) {
      debugPrint('[PaymentService] Checkout verify: customer order not found');
      clearCheckoutUrl();
      return;
    }

    final data = snap.data()!;
    final rid = data['restaurantId'] as String?;
    final roid = data['restaurantOrderId'] as String?;

    final patch = <String, dynamic>{
      'paymentStatus': 'paid',
      'status': 'pending',
    };

    final checkoutKind = result['checkoutKind'] as String? ?? 'standard';
    final isConnect = checkoutKind == 'connect';
    final totalPkr = (data['total'] as num?)?.toDouble() ?? 0.0;
    final restaurantName = data['restaurantName'] as String? ?? 'Restaurant';

    var platformFeePkr = totalPkr * 0.05;
    var restaurantAmountPkr = totalPkr - platformFeePkr;
    var debtRecoveredPkr = 0.0;
    var debtRemaining = 0.0;

    if (isConnect) {
      final nfp = (result['normalFeePaisa'] as num?)?.toInt() ?? 0;
      final drp = (result['debtRecoveredPaisa'] as num?)?.toInt() ?? 0;
      final rap = (result['restaurantAmountPaisa'] as num?)?.toInt() ?? 0;
      platformFeePkr = nfp / 100.0;
      debtRecoveredPkr = drp / 100.0;
      restaurantAmountPkr = rap / 100.0;
      if (debtRecoveredPkr > 0 &&
          rid != null &&
          rid.isNotEmpty) {
        final debtSnap =
            await _firestore.collection('platformDebts').doc(rid).get();
        final currentDebt =
            (debtSnap.data()?['amount'] as num?)?.toDouble() ?? 0.0;
        debtRemaining = currentDebt - debtRecoveredPkr;
        if (debtRemaining < 0) debtRemaining = 0;
      }
    }

    var customerName = 'Customer';
    final dn = userFinal.displayName?.trim();
    if (dn != null && dn.isNotEmpty) {
      customerName = dn;
    } else {
      final em = userFinal.email?.trim();
      if (em != null && em.isNotEmpty) customerName = em;
    }

    final txData = <String, dynamic>{
      'customerId': userFinal.uid,
      'customerName': customerName,
      'restaurantId': rid ?? '',
      'restaurantName': restaurantName,
      'orderId': orderId,
      'amount': totalPkr,
      'platformFee': platformFeePkr,
      'restaurantAmount': restaurantAmountPkr,
      'paymentMethod': 'online',
      'createdAt': FieldValue.serverTimestamp(),
      'stripeCheckoutSessionId': sessionId,
    };
    if (debtRecoveredPkr > 0) {
      txData['debtRecovered'] = debtRecoveredPkr;
      txData['debtRemaining'] = debtRemaining;
    }

    final batch = _firestore.batch();
    batch.update(custRef, patch);
    if (rid != null && roid != null && rid.isNotEmpty && roid.isNotEmpty) {
      batch.update(
        _firestore
            .collection('restaurants')
            .doc(rid)
            .collection('orders')
            .doc(roid),
        patch,
      );
    }
    batch.set(txRef, txData);
    if (isConnect && debtRecoveredPkr > 0 && rid != null && rid.isNotEmpty) {
      batch.set(
        _firestore.collection('platformDebts').doc(rid),
        {'amount': FieldValue.increment(-debtRecoveredPkr)},
        SetOptions(merge: true),
      );
    }

    try {
      await batch.commit();
    } catch (e) {
      debugPrint('[PaymentService] Checkout finalize batch failed: $e');
      clearCheckoutUrl();
      return;
    }

    // Hosted Checkout uses `launchUrl` with `_self`, so the app unloads before
    // CartView can run `clearCart()`. Clear persisted cart on successful return.
    cartService.clearCart();

    clearCheckoutUrl();
    debugPrint(
      '[PaymentService] Checkout verified; orders + transaction for $orderId',
    );
  }

  static Future<Map<String, dynamic>?> _post(
      String path, Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse('$stripeServerUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        debugPrint(
          '[PaymentService] $path failed: HTTP ${response.statusCode} ${response.body}',
        );
        return null;
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[PaymentService] $path error: $e');
      return null;
    }
  }

  /// Ensures the user has a Stripe Customer ID.
  /// Creates one if it doesn't exist, stores it in Firestore.
  static Future<String?> ensureStripeCustomer({
    required String userId,
    required String email,
    String? name,
  }) async {
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final existingId = userDoc.data()?['stripeCustomerId'] as String?;

    if (existingId != null && existingId.isNotEmpty) return existingId;

    final result = await _post('/create-customer', {
      'userId': userId,
      'email': email,
      'name': name,
    });

    if (result == null) return null;

    final customerId = result['customerId'] as String?;
    if (customerId != null) {
      await _firestore.collection('users').doc(userId).update({
        'stripeCustomerId': customerId,
      });
    }

    return customerId;
  }

  /// Creates a Stripe Checkout Session and opens it in the browser.
  /// Returns the session ID if successful.
  static Future<String?> openCheckout({
    required String? stripeCustomerId,
    required List<Map<String, dynamic>> items,
    required String orderId,
    required String firebaseUid,
  }) async {
    final lineItems = items.map((item) => {
          'name': item['name'] as String? ?? 'Item',
          'quantity': item['quantity'] as int? ?? 1,
          'priceInPaisa': ((item['price'] as num? ?? 0) * 100).round(),
        }).toList();

    final body = <String, dynamic>{
      'customerId': stripeCustomerId,
      'items': lineItems,
      'orderId': orderId,
      'currency': 'pkr',
      'firebaseUid': firebaseUid,
    };
    final appUrl = _getAppBaseUrl();
    if (appUrl != null) body['appBaseUrl'] = appUrl;

    final result = await _post('/create-checkout-session', body);

    if (result == null) return null;

    final url = result['url'] as String?;
    final sessionId = result['sessionId'] as String?;

    if (url != null) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, webOnlyWindowName: '_self');
      }
    }

    return sessionId;
  }

  /// Opens Stripe Checkout in setup mode to save a card.
  static Future<bool> openCardSetup({
    required String stripeCustomerId,
  }) async {
    final body = <String, dynamic>{
      'customerId': stripeCustomerId,
    };
    final appUrl = _getAppBaseUrl();
    if (appUrl != null) body['appBaseUrl'] = appUrl;

    final result = await _post('/create-setup-session', body);

    if (result == null) return false;

    final url = result['url'] as String?;
    if (url != null) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, webOnlyWindowName: '_self');
        return true;
      }
    }

    return false;
  }

  /// Retrieves saved cards for a Stripe Customer.
  static Future<List<SavedCard>> getSavedCards({
    required String stripeCustomerId,
  }) async {
    final result = await _post('/get-saved-cards', {
      'customerId': stripeCustomerId,
    });

    if (result == null) return [];

    final cardsJson = result['cards'] as List<dynamic>? ?? [];
    return cardsJson
        .map((c) => SavedCard(
              id: c['id'] as String,
              brand: c['brand'] as String,
              last4: c['last4'] as String,
              expMonth: c['expMonth'] as int,
              expYear: c['expYear'] as int,
            ))
        .toList();
  }

  /// Deletes a saved card.
  static Future<bool> deleteSavedCard({
    required String paymentMethodId,
  }) async {
    final result = await _post('/delete-saved-card', {
      'paymentMethodId': paymentMethodId,
    });

    return result?['success'] == true;
  }

  /// Charges a saved card directly (for voice-command payments).
  static Future<bool> chargeWithSavedCard({
    required String stripeCustomerId,
    required String paymentMethodId,
    required double amount,
    required String orderId,
  }) async {
    final result = await _post('/charge-saved-card', {
      'customerId': stripeCustomerId,
      'paymentMethodId': paymentMethodId,
      'amountInPaisa': (amount * 100).round(),
      'orderId': orderId,
      'currency': 'pkr',
    });

    return result?['success'] == true;
  }

  // ─── Stripe Connect ───

  /// Creates a Stripe Connect Express account for a restaurant and returns an onboarding URL.
  static Future<Map<String, String>?> createConnectAccount({
    required String restaurantId,
    required String email,
    String? businessName,
  }) async {
    final body = <String, dynamic>{
      'restaurantId': restaurantId,
      'email': email,
      'businessName': businessName,
    };
    final appUrl = _getAppBaseUrl();
    if (appUrl != null) body['appBaseUrl'] = appUrl;

    final result = await _post('/create-connect-account', body);
    if (result == null) return null;

    final accountId = result['accountId'] as String?;
    final onboardingUrl = result['onboardingUrl'] as String?;
    if (accountId == null || onboardingUrl == null) return null;

    await _firestore.collection('restaurants').doc(restaurantId).update({
      'stripeConnectId': accountId,
      'stripeConnectOnboarded': false,
    });

    return {'accountId': accountId, 'onboardingUrl': onboardingUrl};
  }

  /// Generates a fresh onboarding link for an existing Connect account.
  static Future<String?> getOnboardingLink({
    required String accountId,
  }) async {
    final body = <String, dynamic>{'accountId': accountId};
    final appUrl = _getAppBaseUrl();
    if (appUrl != null) body['appBaseUrl'] = appUrl;

    final result = await _post('/connect-onboarding-link', body);
    return result?['onboardingUrl'] as String?;
  }

  /// Checks if a Connect account has completed onboarding.
  static Future<bool> checkConnectStatus({
    required String accountId,
    required String restaurantId,
  }) async {
    final result = await _post('/connect-account-status', {
      'accountId': accountId,
    });
    if (result == null) return false;

    final chargesEnabled = result['chargesEnabled'] == true;
    final detailsSubmitted = result['detailsSubmitted'] == true;
    final isReady = chargesEnabled && detailsSubmitted;

    if (isReady) {
      await _firestore.collection('restaurants').doc(restaurantId).update({
        'stripeConnectOnboarded': true,
      });
    }

    return isReady;
  }

  /// Creates a checkout session with split payment (5% platform fee + COD debt recovery).
  /// Returns a [ConnectedPaymentResult] with session ID and debt recovery breakdown, or null on failure.
  static Future<ConnectedPaymentResult?> openConnectedCheckout({
    required String? stripeCustomerId,
    required List<Map<String, dynamic>> items,
    required String orderId,
    required String connectedAccountId,
    required String firebaseUid,
    int platformDebtPaisa = 0,
  }) async {
    final lineItems = items.map((item) => {
          'name': item['name'] as String? ?? 'Item',
          'quantity': item['quantity'] as int? ?? 1,
          'priceInPaisa': ((item['price'] as num? ?? 0) * 100).round(),
        }).toList();

    final body = <String, dynamic>{
      'customerId': stripeCustomerId,
      'items': lineItems,
      'orderId': orderId,
      'currency': 'pkr',
      'connectedAccountId': connectedAccountId,
      'platformDebtPaisa': platformDebtPaisa,
      'firebaseUid': firebaseUid,
    };
    final appUrl = _getAppBaseUrl();
    if (appUrl != null) body['appBaseUrl'] = appUrl;

    final result = await _post('/create-connected-checkout', body);
    if (result == null) return null;

    final url = result['url'] as String?;
    final sessionId = result['sessionId'] as String?;

    if (url != null) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, webOnlyWindowName: '_self');
      }
    }

    return ConnectedPaymentResult(
      sessionId: sessionId,
      success: sessionId != null,
      normalFeePaisa: (result['normalFeePaisa'] as num?)?.toInt() ?? 0,
      debtRecoveredPaisa: (result['debtRecoveredPaisa'] as num?)?.toInt() ?? 0,
      totalApplicationFeePaisa: (result['totalApplicationFeePaisa'] as num?)?.toInt() ?? 0,
      restaurantAmountPaisa: (result['restaurantAmountPaisa'] as num?)?.toInt() ?? 0,
    );
  }

  /// Charges a saved card with split payment (5% platform fee + COD debt recovery).
  /// Returns a [ConnectedPaymentResult] with success status and debt recovery breakdown.
  static Future<ConnectedPaymentResult> chargeWithSavedCardConnected({
    required String stripeCustomerId,
    required String paymentMethodId,
    required double amount,
    required String orderId,
    required String connectedAccountId,
    int platformDebtPaisa = 0,
  }) async {
    final result = await _post('/charge-saved-card-connected', {
      'customerId': stripeCustomerId,
      'paymentMethodId': paymentMethodId,
      'amountInPaisa': (amount * 100).round(),
      'orderId': orderId,
      'currency': 'pkr',
      'connectedAccountId': connectedAccountId,
      'platformDebtPaisa': platformDebtPaisa,
    });

    if (result == null) {
      return ConnectedPaymentResult(success: false);
    }

    return ConnectedPaymentResult(
      success: result['success'] == true,
      normalFeePaisa: (result['normalFeePaisa'] as num?)?.toInt() ?? 0,
      debtRecoveredPaisa: (result['debtRecoveredPaisa'] as num?)?.toInt() ?? 0,
      totalApplicationFeePaisa: (result['totalApplicationFeePaisa'] as num?)?.toInt() ?? 0,
      restaurantAmountPaisa: (result['restaurantAmountPaisa'] as num?)?.toInt() ?? 0,
    );
  }

  /// Gets a Stripe Express dashboard link for a restaurant.
  static Future<String?> getConnectDashboardLink({
    required String accountId,
  }) async {
    final result = await _post('/connect-dashboard-link', {
      'accountId': accountId,
    });
    return result?['url'] as String?;
  }
}

class ConnectedPaymentResult {
  final String? sessionId;
  final bool success;
  final int normalFeePaisa;
  final int debtRecoveredPaisa;
  final int totalApplicationFeePaisa;
  final int restaurantAmountPaisa;

  const ConnectedPaymentResult({
    this.sessionId,
    this.success = false,
    this.normalFeePaisa = 0,
    this.debtRecoveredPaisa = 0,
    this.totalApplicationFeePaisa = 0,
    this.restaurantAmountPaisa = 0,
  });

  double get normalFeePkr => normalFeePaisa / 100;
  double get debtRecoveredPkr => debtRecoveredPaisa / 100;
  double get totalApplicationFeePkr => totalApplicationFeePaisa / 100;
  double get restaurantAmountPkr => restaurantAmountPaisa / 100;
}
