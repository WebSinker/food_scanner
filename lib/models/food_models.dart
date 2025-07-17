class FoodResult {
  final String name;
  final double caloriesPer100g;
  final double confidence;
  final double weight;
  final double? totalCaloriesFromAI;
  final NutrientInfo? nutrients;

  FoodResult({
    required this.name,
    required double calories,
    required this.confidence,
    required this.weight,
    this.totalCaloriesFromAI,
    this.nutrients,
  }) : caloriesPer100g = calories;

  double get calculatedTotalCalories {
    if (totalCaloriesFromAI != null) {
      final originalWeight = 100.0;
      return (totalCaloriesFromAI! * weight) / originalWeight;
    }
    return (caloriesPer100g * weight) / 100;
  }

  FoodResult copyWith({
    String? name,
    double? calories,
    double? confidence,
    double? weight,
    double? totalCaloriesFromAI,
    NutrientInfo? nutrients,
  }) {
    return FoodResult(
      name: name ?? this.name,
      calories: calories ?? this.caloriesPer100g,
      confidence: confidence ?? this.confidence,
      weight: weight ?? this.weight,
      totalCaloriesFromAI: totalCaloriesFromAI ?? this.totalCaloriesFromAI,
      nutrients: nutrients ?? this.nutrients,
    );
  }
}

class NutrientInfo {
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;

  NutrientInfo({
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
  });

  factory NutrientInfo.fromJson(Map<String, dynamic> json) {
    return NutrientInfo(
      protein: (json['protein'] ?? 0).toDouble(),
      carbs: (json['carbs'] ?? 0).toDouble(),
      fat: (json['fat'] ?? 0).toDouble(),
      fiber: (json['fiber'] ?? 0).toDouble(),
    );
  }

  double adjustedProtein(double actualWeight) => (protein * actualWeight) / 100;
  double adjustedCarbs(double actualWeight) => (carbs * actualWeight) / 100;
  double adjustedFat(double actualWeight) => (fat * actualWeight) / 100;
  double adjustedFiber(double actualWeight) => (fiber * actualWeight) / 100;
}