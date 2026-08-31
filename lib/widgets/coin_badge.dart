import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CoinBadge extends StatelessWidget {
  final double amount;
  final double fontSize;

  const CoinBadge({super.key, required this.amount, this.fontSize = 14});

  String get _formatted {
    // Whole numbers show clean ("120"), fractional amounts show up to
    // 2 decimals ("0.05") so small rewards don't look like errors.
    if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
    return amount.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.coin.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.coin.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => AppGradients.coin.createShader(bounds),
            child: Icon(Icons.monetization_on, color: Colors.white, size: fontSize + 4),
          ),
          const SizedBox(width: 4),
          Text(
            _formatted,
            style: TextStyle(
              color: AppColors.coin,
              fontWeight: FontWeight.bold,
              fontSize: fontSize,
            ),
          ),
        ],
      ),
    );
  }
}
