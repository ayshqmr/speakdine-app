import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speak_dine/models/menu_item.dart';

enum OrderStatus { pending, preparing, ready, delivered, cancelled }

class OrderModel {
  String? id;
  String userId;
  String userName;
  List<MenuItemModel> items;
  double totalAmount;
  OrderStatus status;
  DateTime createdAt;

  OrderModel({
    this.id,
    required this.userId,
    required this.userName,
    required this.items,
    required this.totalAmount,
    this.status = OrderStatus.pending,
    required this.createdAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      id: json['id'],
      userId: json['user_id'] ?? '',
      userName: json['user_name'] ?? 'Unknown',
      items: (json['items'] as List<dynamic>?)
              ?.map((item) => MenuItemModel.fromJson(item))
              .toList() ??
          [],
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      status: OrderStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => OrderStatus.pending,
      ),
      createdAt: (json['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'user_name': userName,
      'items': items.map((item) => item.toJson()).toList(),
      'total_amount': totalAmount,
      'status': status.toString().split('.').last,
      'created_at': Timestamp.fromDate(createdAt),
    };
  }
}
