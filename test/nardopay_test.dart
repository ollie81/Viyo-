import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/services/nardopay_service.dart';

/// Returns the given statuses in order (null = a failed request), then repeats the last.
class FakeNardopay extends NardopayApi {
  FakeNardopay(this.statuses);
  final List<String?> statuses;
  int calls = 0;

  @override
  Future<NardopayOrder> status(String orderId) async {
    final s = statuses[calls < statuses.length ? calls : statuses.length - 1];
    calls++;
    if (s == null) throw Exception('network');
    return NardopayOrder(orderId: orderId, status: s, coins: 100, rwfAmount: 1396);
  }
}

void main() {
  test('an order is read from the server response', () {
    final o = NardopayOrder.fromJson({
      'order_id': 'o1',
      'status': 'pending',
      'coins': 100,
      'rwf_amount': 1396,
      'payment_link': 'https://pay.example/x'
    });
    expect(o.coins, 100);
    expect(o.rwfAmount, 1396);
    expect(o.paymentLink, 'https://pay.example/x');
    expect(o.settled, isFalse);
    expect(const NardopayOrder(orderId: 'o', status: 'credited', coins: 1, rwfAmount: 1).settled, isTrue);
    expect(const NardopayOrder(orderId: 'o', status: 'expired', coins: 1, rwfAmount: 1).settled, isFalse);
  });

  test('waits until the server says the order is credited', () async {
    final api = FakeNardopay(['pending', 'crediting', 'credited']);
    expect(await waitForNardopayOrder(api, 'o1', every: Duration.zero), 'credited');
    expect(api.calls, 3);
  });

  test('a failed check is retried, never treated as paid', () async {
    final api = FakeNardopay([null, null, 'credited']);
    expect(await waitForNardopayOrder(api, 'o1', every: Duration.zero), 'credited');
  });

  test('stops at failed or mismatch', () async {
    expect(await waitForNardopayOrder(FakeNardopay(['pending', 'failed']), 'o', every: Duration.zero), 'failed');
    expect(await waitForNardopayOrder(FakeNardopay(['mismatch']), 'o', every: Duration.zero), 'mismatch');
  });

  test('gives up after the maximum number of checks and reports it still pending', () async {
    final api = FakeNardopay(['pending']);
    expect(await waitForNardopayOrder(api, 'o1', every: Duration.zero, maxTries: 5), 'pending');
    expect(api.calls, 5);
  });

  test('stops when the screen is closed', () async {
    final api = FakeNardopay(['pending']);
    var closed = false;
    final f = waitForNardopayOrder(api, 'o1', every: Duration.zero, maxTries: 1000, cancelled: () => closed);
    closed = true;
    expect(await f, 'pending');
    expect(api.calls, lessThan(1000));
  });
}
