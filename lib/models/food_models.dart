class FoodResult {
  final String name;
  final double caloriesPer100g;
  final double confidence;
  final double weight;
  final double? totalCaloriesFromAI;
  final NutrientInfo? nutrients;
  final String? ndbNumber; // NDB number from USDA
  final String? fdcId; // FDC ID from USDA
  final String? dataSource; // Data source (USDA_Foundation, USDA_SR_Legacy, etc.)
  final String? databaseMatch; // Full description from USDA
  final String? foodCategory; // Food category from AI analysis
  final String? preparationMethod; // Preparation method from AI
  final int? usdaSearchResults; // Number of USDA results found
  final List<String>? databasesSearched; // Which databases were searched

  FoodResult({
    required this.name,
    required double calories,
    required this.confidence,
    required this.weight,
    this.totalCaloriesFromAI,
    this.nutrients,
    this.ndbNumber,
    this.fdcId,
    this.dataSource,
    this.databaseMatch,
    this.foodCategory,
    this.preparationMethod,
    this.usdaSearchResults,
    this.databasesSearched,
  }) : caloriesPer100g = calories;

  double get calculatedTotalCalories {
    // Calculate based on current weight
    return (caloriesPer100g * weight) / 100;
  }

  FoodResult copyWith({
    String? name,
    double? calories,
    double? confidence,
    double? weight,
    double? totalCaloriesFromAI,
    NutrientInfo? nutrients,
    String? ndbNumber,
    String? fdcId,
    String? dataSource,
    String? databaseMatch,
    String? foodCategory,
    String? preparationMethod,
    int? usdaSearchResults,
    List<String>? databasesSearched,
  }) {
    return FoodResult(
      name: name ?? this.name,
      calories: calories ?? this.caloriesPer100g,
      confidence: confidence ?? this.confidence,
      weight: weight ?? this.weight,
      totalCaloriesFromAI: totalCaloriesFromAI ?? this.totalCaloriesFromAI,
      nutrients: nutrients ?? this.nutrients,
      ndbNumber: ndbNumber ?? this.ndbNumber,
      fdcId: fdcId ?? this.fdcId,
      dataSource: dataSource ?? this.dataSource,
      databaseMatch: databaseMatch ?? this.databaseMatch,
      foodCategory: foodCategory ?? this.foodCategory,
      preparationMethod: preparationMethod ?? this.preparationMethod,
      usdaSearchResults: usdaSearchResults ?? this.usdaSearchResults,
      databasesSearched: databasesSearched ?? this.databasesSearched,
    );
  }

  // Helper method to get formatted data source info for logging
  String get dataSourceInfo {
    List<String> infoParts = [];
    
    if (dataSource != null) {
      infoParts.add(dataSource!);
    }
    
    if (fdcId != null) {
      infoParts.add('FDC: $fdcId');
    }
    
    if (ndbNumber != null && ndbNumber != 'N/A') {
      infoParts.add('NDB: $ndbNumber');
    }
    
    if (usdaSearchResults != null) {
      infoParts.add('${usdaSearchResults} results');
    }
    
    return infoParts.isNotEmpty ? infoParts.join(' • ') : 'Unknown source';
  }

  // Helper method to get database type for UI display
  String get databaseType {
    if (dataSource == null) return 'Unknown';
    
    if (dataSource!.contains('Foundation')) return 'Foundation';
    if (dataSource!.contains('SR_Legacy')) return 'SR Legacy';
    if (dataSource!.contains('Survey')) return 'Survey (FNDDS)';
    if (dataSource!.contains('Branded')) return 'Branded';
    if (dataSource!.contains('Estimated')) return 'Estimated';
    if (dataSource!.contains('Fallback')) return 'Fallback';
    
    return dataSource!;
  }

  // Helper method to get confidence color based on data source and confidence
  String get confidenceLevel {
    if (dataSource?.contains('Foundation') == true && confidence > 0.7) {
      return 'High';
    } else if (dataSource?.contains('SR_Legacy') == true && confidence > 0.6) {
      return 'High';
    } else if (confidence > 0.8) {
      return 'High';
    } else if (confidence > 0.6) {
      return 'Medium';
    } else {
      return 'Low';
    }
  }

  // Helper method for detailed logging
  Map<String, dynamic> toDetailedLog() {
    return {
      'name': name,
      'weight': weight,
      'calories_per_100g': caloriesPer100g,
      'total_calories': calculatedTotalCalories,
      'confidence': confidence,
      'confidence_level': confidenceLevel,
      'data_source': dataSource,
      'database_type': databaseType,
      'fdc_id': fdcId,
      'ndb_number': ndbNumber,
      'database_match': databaseMatch,
      'food_category': foodCategory,
      'preparation_method': preparationMethod,
      'usda_search_results': usdaSearchResults,
      'databases_searched': databasesSearched,
      'has_nutrients': nutrients != null,
    };
  }

  // Factory method to create from enhanced API response
  factory FoodResult.fromEnhancedApi(Map<String, dynamic> json) {
    return FoodResult(
      name: json['name'] ?? 'Unknown Food',
      calories: (json['calories_per_100g'] ?? 200).toDouble(),
      confidence: (json['confidence'] ?? 0.5).toDouble(),
      weight: (json['estimated_weight_grams'] ?? 100).toDouble(),
      totalCaloriesFromAI: json['total_calories']?.toDouble(),
      nutrients: json['nutrients'] != null 
          ? NutrientInfo.fromJson(json['nutrients']) 
          : null,
      ndbNumber: json['ndb_number']?.toString(),
      fdcId: json['fdc_id']?.toString(),
      dataSource: json['data_source']?.toString(),
      databaseMatch: json['database_match']?.toString(),
      foodCategory: json['food_category']?.toString(),
      preparationMethod: json['preparation_method']?.toString(),
      usdaSearchResults: json['usda_search_results']?.toInt(),
      databasesSearched: json['databases_searched'] != null 
          ? List<String>.from(json['databases_searched']) 
          : null,
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

  Map<String, dynamic> toJson() {
    return {
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'fiber': fiber,
    };
  }

  double adjustedProtein(double actualWeight) => (protein * actualWeight) / 100;
  double adjustedCarbs(double actualWeight) => (carbs * actualWeight) / 100;
  double adjustedFat(double actualWeight) => (fat * actualWeight) / 100;
  double adjustedFiber(double actualWeight) => (fiber * actualWeight) / 100;

  // Calculate total macronutrient calories
  double totalMacroCalories(double actualWeight) {
    return (adjustedProtein(actualWeight) * 4) + // 4 cal/g protein
           (adjustedCarbs(actualWeight) * 4) + // 4 cal/g carbs
           (adjustedFat(actualWeight) * 9); // 9 cal/g fat
  }

  // Get macro distribution percentages
  Map<String, double> getMacroPercentages(double actualWeight) {
    double totalCals = totalMacroCalories(actualWeight);
    if (totalCals == 0) return {'protein': 0, 'carbs': 0, 'fat': 0};
    
    return {
      'protein': (adjustedProtein(actualWeight) * 4 / totalCals * 100),
      'carbs': (adjustedCarbs(actualWeight) * 4 / totalCals * 100),
      'fat': (adjustedFat(actualWeight) * 9 / totalCals * 100),
    };
  }
}

// Enhanced logging utility for debugging USDA data
class FoodAnalysisLogger {
  static void logDetailedResults(List<FoodResult> results) {
    print('\n=== DETAILED FOOD ANALYSIS RESULTS ===');
    print('📊 Total items analyzed: ${results.length}');
    
    double totalCalories = 0;
    Map<String, int> databaseCounts = {};
    Map<String, int> confidenceLevels = {};
    
    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      print('\n🍽️ ITEM ${i + 1}: ${result.name}');
      print('   ⚖️ Weight: ${result.weight.toInt()}g');
      print('   🔥 Calories: ${result.calculatedTotalCalories.toInt()} (${result.caloriesPer100g.toInt()}/100g)');
      print('   📊 Confidence: ${(result.confidence * 100).toInt()}% (${result.confidenceLevel})');
      print('   🗃️ Database: ${result.databaseType}');
      
      if (result.fdcId != null) {
        print('   🔢 FDC ID: ${result.fdcId}');
      }
      
      if (result.ndbNumber != null && result.ndbNumber != 'N/A') {
        print('   🏷️ NDB Number: ${result.ndbNumber}');
      }
      
      if (result.databaseMatch != null) {
        print('   📋 Match: ${result.databaseMatch}');
      }
      
      if (result.usdaSearchResults != null) {
        print('   🔍 Search Results: ${result.usdaSearchResults}');
      }
      
      if (result.databasesSearched != null && result.databasesSearched!.isNotEmpty) {
        print('   🗄️ Databases Searched: ${result.databasesSearched!.join(', ')}');
      }
      
      if (result.nutrients != null) {
        final nutrients = result.nutrients!;
        print('   🥗 Nutrients (for ${result.weight.toInt()}g):');
        print('      • Protein: ${nutrients.adjustedProtein(result.weight).toInt()}g');
        print('      • Carbs: ${nutrients.adjustedCarbs(result.weight).toInt()}g');
        print('      • Fat: ${nutrients.adjustedFat(result.weight).toInt()}g');
        print('      • Fiber: ${nutrients.adjustedFiber(result.weight).toInt()}g');
        
        final macroPercentages = nutrients.getMacroPercentages(result.weight);
        print('   📊 Macro Distribution:');
        print('      • ${macroPercentages['protein']!.toInt()}% Protein');
        print('      • ${macroPercentages['carbs']!.toInt()}% Carbs');
        print('      • ${macroPercentages['fat']!.toInt()}% Fat');
      }
      
      // Collect statistics
      totalCalories += result.calculatedTotalCalories;
      databaseCounts[result.databaseType] = (databaseCounts[result.databaseType] ?? 0) + 1;
      confidenceLevels[result.confidenceLevel] = (confidenceLevels[result.confidenceLevel] ?? 0) + 1;
    }
    
    print('\n📈 ANALYSIS SUMMARY:');
    print('   🔥 Total Calories: ${totalCalories.toInt()}');
    print('   🗃️ Database Distribution:');
    databaseCounts.forEach((db, count) {
      print('      • $db: $count items');
    });
    print('   📊 Confidence Distribution:');
    confidenceLevels.forEach((level, count) {
      print('      • $level: $count items');
    });
    
    // Highlight any potential issues
    final lowConfidenceItems = results.where((r) => r.confidence < 0.5).length;
    final estimatedItems = results.where((r) => r.dataSource?.contains('Estimated') == true).length;
    
    if (lowConfidenceItems > 0) {
      print('   ⚠️ Low confidence items: $lowConfidenceItems');
    }
    if (estimatedItems > 0) {
      print('   ⚠️ Estimated (no USDA match): $estimatedItems');
    }
    
    print('=== END DETAILED ANALYSIS ===\n');
  }
  
  static void logNdbNumbers(List<FoodResult> results) {
    print('\n=== NDB NUMBER TRACKING ===');
    for (final result in results) {
      if (result.ndbNumber != null && result.ndbNumber != 'N/A') {
        print('🏷️ ${result.name}: NDB ${result.ndbNumber} (FDC: ${result.fdcId})');
      } else {
        print('❌ ${result.name}: No NDB number available');
      }
    }
    print('=== END NDB TRACKING ===\n');
  }
}