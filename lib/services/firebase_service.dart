import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:io';
import '../models/food_models.dart';

class FirebaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Collection names
  static const String SCANS_COLLECTION = 'food_scans';
  static const String USERS_COLLECTION = 'users';
  
  // Get current user ID (create anonymous user if needed)
  static Future<String> getCurrentUserId() async {
    try {
      print('🔐 Getting current user...');
      User? user = _auth.currentUser;
      
      if (user == null) {
        print('🔐 No current user, creating anonymous user...');
        UserCredential userCredential = await _auth.signInAnonymously()
            .timeout(Duration(seconds: 15));
        user = userCredential.user;
        print('✅ Anonymous user created: ${user?.uid}');
        print('✅ User is anonymous: ${user?.isAnonymous}');
      } else {
        print('✅ Current user found: ${user.uid}');
        print('✅ User is anonymous: ${user.isAnonymous}');
      }
      
      return user!.uid;
    } catch (e) {
      print('❌ Auth error: $e');
      
      if (e.toString().contains('network')) {
        throw Exception('Network error during authentication. Please check your connection.');
      } else if (e.toString().contains('operation-not-allowed')) {
        throw Exception('Anonymous authentication not enabled. Please enable it in Firebase Console.');
      } else {
        throw Exception('Authentication failed: $e');
      }
    }
  }
  
  // Test Firebase connection with comprehensive checks
  static Future<bool> testFirebaseConnection() async {
    try {
      print('🔥 Testing Firebase connection...');
      
      // Test 1: Check if Firebase is initialized
      print('🔥 Firebase apps: ${Firebase.apps.length}');
      
      // Test 2: Test authentication
      print('🔐 Testing anonymous auth...');
      User? user = _auth.currentUser;
      if (user == null) {
        UserCredential userCredential = await _auth.signInAnonymously()
            .timeout(Duration(seconds: 10));
        user = userCredential.user;
        print('✅ Anonymous auth successful: ${user?.uid}');
      } else {
        print('✅ User already authenticated: ${user.uid}');
      }
      
      // Test 3: Test Firestore with a simple write
      print('📄 Testing Firestore write...');
      await _firestore.collection('connection_test').add({
        'test': true,
        'timestamp': FieldValue.serverTimestamp(),
        'userId': user?.uid,
        'platform': Platform.operatingSystem,
        'enhanced_analysis': true,
      }).timeout(Duration(seconds: 15));
      
      print('✅ Firebase connection test successful');
      return true;
    } catch (e) {
      print('❌ Firebase connection test failed: $e');
      
      // More specific error logging
      if (e.toString().contains('PERMISSION_DENIED')) {
        print('❌ Permission denied - check Firestore security rules');
      } else if (e.toString().contains('UNAUTHENTICATED')) {
        print('❌ Authentication failed - check anonymous auth setup');
      } else if (e.toString().contains('UNAVAILABLE')) {
        print('❌ Firebase service unavailable');
      } else if (e.toString().contains('NOT_FOUND')) {
        print('❌ Database not found - check project configuration');
      } else if (e.toString().contains('network') || e.toString().contains('timeout')) {
        print('❌ Network/timeout error');
      }
      
      return false;
    }
  }
  
  // Enhanced save scan result with USDA data logging
  static Future<String> saveScanResult({
    required List<FoodResult> results,
    required String imagePath,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      print('💾 Starting enhanced save scan process...');
      print('📊 Results count: ${results.length}');
      
      // Log USDA data being saved
      print('🗃️ USDA DATA BEING SAVED:');
      for (int i = 0; i < results.length; i++) {
        final result = results[i];
        print('   ${i + 1}. ${result.name}');
        print('      🗃️ Database: ${result.databaseType}');
        print('      🔢 FDC ID: ${result.fdcId ?? 'N/A'}');
        print('      🏷️ NDB Number: ${result.ndbNumber ?? 'N/A'}');
        print('      📊 Confidence: ${(result.confidence * 100).toInt()}%');
        print('      🔍 USDA Results: ${result.usdaSearchResults ?? 0}');
      }
      
      // Step 1: Detailed connection test
      print('🔥 Step 1: Testing Firebase connection...');
      bool isConnected = await testFirebaseConnection();
      if (!isConnected) {
        throw Exception('Firebase connection test failed. Please check your Firebase configuration.');
      }
      
      // Step 2: Get authenticated user
      print('🔐 Step 2: Getting authenticated user...');
      String userId = await getCurrentUserId();
      print('👤 User ID: $userId');
      
      // Step 3: Prepare enhanced data
      print('📝 Step 3: Preparing enhanced data...');
      double totalCalories = results.fold(0.0, (sum, result) => sum + result.calculatedTotalCalories);
      print('🔥 Total calories: $totalCalories');
      
      // Count database sources
      Map<String, int> databaseCounts = {};
      int totalUsdaResults = 0;
      List<String> allDatabasesSearched = [];
      
      for (final result in results) {
        databaseCounts[result.databaseType] = (databaseCounts[result.databaseType] ?? 0) + 1;
        totalUsdaResults += result.usdaSearchResults ?? 0;
        if (result.databasesSearched != null) {
          allDatabasesSearched.addAll(result.databasesSearched!);
        }
      }
      
      Map<String, dynamic> scanData = {
        'userId': userId,
        'timestamp': FieldValue.serverTimestamp(),
        'totalCalories': totalCalories,
        'foodItems': results.map((result) {
          Map<String, dynamic> item = {
            'name': result.name,
            'caloriesPer100g': result.caloriesPer100g,
            'weight': result.weight,
            'confidence': result.confidence,
            'totalCalories': result.calculatedTotalCalories,
            // Enhanced USDA data
            'fdcId': result.fdcId,
            'ndbNumber': result.ndbNumber,
            'dataSource': result.dataSource,
            'databaseMatch': result.databaseMatch,
            'databaseType': result.databaseType,
            'foodCategory': result.foodCategory,
            'preparationMethod': result.preparationMethod,
            'usdaSearchResults': result.usdaSearchResults,
            'databasesSearched': result.databasesSearched,
            'confidenceLevel': result.confidenceLevel,
          };
          
          if (result.nutrients != null) {
            item['nutrients'] = {
              'protein': result.nutrients!.protein,
              'carbs': result.nutrients!.carbs,
              'fat': result.nutrients!.fat,
              'fiber': result.nutrients!.fiber,
            };
          }
          
          return item;
        }).toList(),
        'imagePath': imagePath,
        'metadata': metadata ?? {},
        'createdAt': DateTime.now().toIso8601String(),
        'platform': Platform.operatingSystem,
        // Enhanced metadata
        'enhancedAnalysis': true,
        'analysisVersion': '2.0.0',
        'databaseCounts': databaseCounts,
        'totalUsdaResults': totalUsdaResults,
        'uniqueDatabasesSearched': allDatabasesSearched.toSet().toList(),
        'usdaDataQuality': {
          'foundationCount': databaseCounts['Foundation'] ?? 0,
          'srLegacyCount': databaseCounts['SR Legacy'] ?? 0,
          'surveyCount': databaseCounts['Survey (FNDDS)'] ?? 0,
          'brandedCount': databaseCounts['Branded'] ?? 0,
          'estimatedCount': databaseCounts['Estimated'] ?? 0,
          'averageConfidence': results.isNotEmpty 
              ? results.map((r) => r.confidence).reduce((a, b) => a + b) / results.length
              : 0.0,
        }
      };
      
      print('📄 Step 4: Saving enhanced data to Firestore collection: $SCANS_COLLECTION');
      
      // Step 4: Save to Firestore with retry logic
      DocumentReference? docRef;
      int attempts = 0;
      const maxAttempts = 3;
      
      while (attempts < maxAttempts) {
        try {
          attempts++;
          print('💫 Save attempt $attempts of $maxAttempts...');
          
          docRef = await _firestore
              .collection(SCANS_COLLECTION)
              .add(scanData)
              .timeout(Duration(seconds: 20));
          
          print('✅ Enhanced save successful on attempt $attempts');
          break; // Success, exit retry loop
          
        } catch (e) {
          print('❌ Save attempt $attempts failed: $e');
          
          if (attempts >= maxAttempts) {
            rethrow; // Final attempt failed
          }
          
          // Wait before retry
          print('⏳ Waiting 2 seconds before retry...');
          await Future.delayed(Duration(seconds: 2));
        }
      }
      
      if (docRef == null) {
        throw Exception('Failed to save after $maxAttempts attempts');
      }
      
      print('✅ Enhanced scan saved successfully with ID: ${docRef.id}');
      print('📊 Saved data includes:');
      print('   🗃️ Database distribution: $databaseCounts');
      print('   🔍 Total USDA results: $totalUsdaResults');
      print('   📚 Databases searched: ${allDatabasesSearched.toSet().toList()}');
      
      return docRef.id;
      
    } catch (e) {
      print('❌ Enhanced save error details: $e');
      print('❌ Error type: ${e.runtimeType}');
      
      // Enhanced error messages
      if (e.toString().contains('TimeoutException') || e.toString().contains('timeout')) {
        throw Exception('Save operation timed out. Please check your internet connection and try again.');
      } else if (e.toString().contains('PERMISSION_DENIED')) {
        throw Exception('Permission denied. Please update Firestore security rules to allow authenticated users.');
      } else if (e.toString().contains('UNAUTHENTICATED')) {
        throw Exception('Authentication failed. Please restart the app and try again.');
      } else if (e.toString().contains('UNAVAILABLE')) {
        throw Exception('Firebase service is currently unavailable. Please try again later.');
      } else if (e.toString().contains('NOT_FOUND')) {
        throw Exception('Firebase database not found. Please check your project configuration.');
      } else if (e.toString().contains('network') || e.toString().contains('connection')) {
        throw Exception('Network connection error. Please check your internet connection.');
      } else {
        throw Exception('Failed to save enhanced scan: ${e.toString()}');
      }
    }
  }
  
  // Enhanced get user scan history with USDA data
  static Future<List<Map<String, dynamic>>> getUserScanHistory({
    int limit = 20,
    DateTime? startAfter,
  }) async {
    try {
      print('📚 Loading enhanced scan history...');
      String userId = await getCurrentUserId();
      
      Query query = _firestore
          .collection(SCANS_COLLECTION)
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .orderBy(FieldPath.documentId);
      
      if (startAfter != null) {
        query = query.startAfter([Timestamp.fromDate(startAfter)]);
      }
      
      QuerySnapshot snapshot = await query.limit(limit).get()
          .timeout(Duration(seconds: 15));
      
      List<Map<String, dynamic>> history = snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        
        // Log enhanced data for debugging
        if (data['enhancedAnalysis'] == true) {
          print('📊 Enhanced scan loaded: ${doc.id}');
          if (data['databaseCounts'] != null) {
            print('   🗃️ Database counts: ${data['databaseCounts']}');
          }
          if (data['totalUsdaResults'] != null) {
            print('   🔍 Total USDA results: ${data['totalUsdaResults']}');
          }
        }
        
        return data;
      }).toList();
      
      print('✅ Loaded ${history.length} scan records');
      
      // Count enhanced vs legacy scans
      int enhancedScans = history.where((scan) => scan['enhancedAnalysis'] == true).length;
      int legacyScans = history.length - enhancedScans;
      print('📈 Enhanced scans: $enhancedScans, Legacy scans: $legacyScans');
      
      return history;
      
    } catch (e) {
      print('❌ Error getting scan history: $e');
      throw Exception('Failed to get scan history: $e');
    }
  }
  
  // Enhanced get scan by ID
  static Future<Map<String, dynamic>?> getScanById(String scanId) async {
    try {
      print('🔍 Loading scan: $scanId');
      
      DocumentSnapshot doc = await _firestore
          .collection(SCANS_COLLECTION)
          .doc(scanId)
          .get()
          .timeout(Duration(seconds: 15));
      
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        
        // Log enhanced data details
        if (data['enhancedAnalysis'] == true) {
          print('📊 Enhanced scan details:');
          print('   🗃️ Database counts: ${data['databaseCounts']}');
          print('   🔍 Total USDA results: ${data['totalUsdaResults']}');
          print('   📚 Databases searched: ${data['uniqueDatabasesSearched']}');
          
          if (data['foodItems'] != null) {
            List<dynamic> foodItems = data['foodItems'];
            print('   🍽️ Food items with USDA data:');
            for (int i = 0; i < foodItems.length; i++) {
              var item = foodItems[i];
              print('      ${i + 1}. ${item['name']}');
              print('         🔢 FDC ID: ${item['fdcId'] ?? 'N/A'}');
              print('         🏷️ NDB: ${item['ndbNumber'] ?? 'N/A'}');
              print('         🗃️ DB: ${item['databaseType'] ?? 'Unknown'}');
            }
          }
        }
        
        return data;
      }
      
      return null;
      
    } catch (e) {
      print('❌ Error getting scan: $e');
      throw Exception('Failed to get scan: $e');
    }
  }
  
  // Delete scan (unchanged)
  static Future<void> deleteScan(String scanId) async {
    try {
      await _firestore
          .collection(SCANS_COLLECTION)
          .doc(scanId)
          .delete()
          .timeout(Duration(seconds: 15));
      
      print('✅ Scan deleted successfully');
      
    } catch (e) {
      print('❌ Error deleting scan: $e');
      throw Exception('Failed to delete scan: $e');
    }
  }
  
  // Enhanced daily calories summary
  static Future<Map<String, dynamic>> getDailyCaloriesSummary(DateTime date) async {
    try {
      print('📊 Loading enhanced daily summary for: $date');
      String userId = await getCurrentUserId();
      
      DateTime startOfDay = DateTime(date.year, date.month, date.day);
      DateTime endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);
      
      QuerySnapshot snapshot = await _firestore
          .collection(SCANS_COLLECTION)
          .where('userId', isEqualTo: userId)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('timestamp', descending: true)
          .orderBy(FieldPath.documentId)
          .get()
          .timeout(Duration(seconds: 15));
      
      double totalCalories = 0;
      int scanCount = 0;
      double totalProtein = 0;
      double totalCarbs = 0;
      double totalFat = 0;
      double totalFiber = 0;
      
      // Enhanced tracking
      Map<String, int> databaseCounts = {};
      int enhancedScans = 0;
      int totalUsdaResults = 0;
      Set<String> allDatabasesUsed = {};
      
      for (var doc in snapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        totalCalories += (data['totalCalories'] ?? 0).toDouble();
        scanCount++;
        
        // Track enhanced analysis data
        if (data['enhancedAnalysis'] == true) {
          enhancedScans++;
          
          if (data['databaseCounts'] != null) {
            Map<String, dynamic> counts = Map<String, dynamic>.from(data['databaseCounts']);
            counts.forEach((db, count) {
              databaseCounts[db] = (databaseCounts[db] ?? 0) + (count as int);
            });
          }
          
          if (data['totalUsdaResults'] != null) {
            totalUsdaResults += (data['totalUsdaResults'] as int);
          }
          
          if (data['uniqueDatabasesSearched'] != null) {
            allDatabasesUsed.addAll(List<String>.from(data['uniqueDatabasesSearched']));
          }
        }
        
        // Sum nutrients
        List<dynamic> foodItems = data['foodItems'] ?? [];
        for (var item in foodItems) {
          Map<String, dynamic>? nutrients = item['nutrients'];
          if (nutrients != null) {
            double weight = (item['weight'] ?? 100).toDouble();
            totalProtein += (nutrients['protein'] ?? 0).toDouble() * weight / 100;
            totalCarbs += (nutrients['carbs'] ?? 0).toDouble() * weight / 100;
            totalFat += (nutrients['fat'] ?? 0).toDouble() * weight / 100;
            totalFiber += (nutrients['fiber'] ?? 0).toDouble() * weight / 100;
          }
        }
      }
      
      print('✅ Enhanced daily summary loaded:');
      print('   📊 ${scanCount} scans, ${totalCalories.toInt()} calories');
      print('   🔬 Enhanced scans: $enhancedScans');
      print('   🗃️ Database distribution: $databaseCounts');
      print('   🔍 Total USDA results: $totalUsdaResults');
      print('   📚 Databases used: ${allDatabasesUsed.toList()}');
      
      return {
        'date': date,
        'totalCalories': totalCalories,
        'scanCount': scanCount,
        'nutrients': {
          'protein': totalProtein,
          'carbs': totalCarbs,
          'fat': totalFat,
          'fiber': totalFiber,
        },
        // Enhanced summary data
        'enhancedScans': enhancedScans,
        'legacyScans': scanCount - enhancedScans,
        'databaseCounts': databaseCounts,
        'totalUsdaResults': totalUsdaResults,
        'databasesUsed': allDatabasesUsed.toList(),
        'dataQuality': {
          'enhancedPercentage': scanCount > 0 ? (enhancedScans / scanCount * 100) : 0,
          'avgUsdaResultsPerScan': enhancedScans > 0 ? (totalUsdaResults / enhancedScans) : 0,
        }
      };
      
    } catch (e) {
      print('❌ Error getting enhanced daily summary: $e');
      throw Exception('Failed to get daily summary: $e');
    }
  }
  
  // New method: Get USDA statistics
  static Future<Map<String, dynamic>> getUsdaStatistics() async {
    try {
      print('📈 Loading USDA statistics...');
      String userId = await getCurrentUserId();
      
      QuerySnapshot snapshot = await _firestore
          .collection(SCANS_COLLECTION)
          .where('userId', isEqualTo: userId)
          .where('enhancedAnalysis', isEqualTo: true)
          .orderBy('timestamp', descending: true)
          .limit(100) // Last 100 enhanced scans
          .get()
          .timeout(Duration(seconds: 15));
      
      Map<String, int> totalDatabaseCounts = {};
      int totalUsdaResults = 0;
      Set<String> allDatabasesUsed = {};
      List<double> confidenceScores = [];
      
      for (var doc in snapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        
        if (data['databaseCounts'] != null) {
          Map<String, dynamic> counts = Map<String, dynamic>.from(data['databaseCounts']);
          counts.forEach((db, count) {
            totalDatabaseCounts[db] = (totalDatabaseCounts[db] ?? 0) + (count as int);
          });
        }
        
        if (data['totalUsdaResults'] != null) {
          totalUsdaResults += (data['totalUsdaResults'] as int);
        }
        
        if (data['uniqueDatabasesSearched'] != null) {
          allDatabasesUsed.addAll(List<String>.from(data['uniqueDatabasesSearched']));
        }
        
        if (data['usdaDataQuality'] != null && data['usdaDataQuality']['averageConfidence'] != null) {
          confidenceScores.add((data['usdaDataQuality']['averageConfidence'] as num).toDouble());
        }
      }
      
      print('✅ USDA statistics loaded:');
      print('   📊 Total database usage: $totalDatabaseCounts');
      print('   🔍 Total USDA results: $totalUsdaResults');
      print('   📚 Databases used: ${allDatabasesUsed.toList()}');
      
      return {
        'totalEnhancedScans': snapshot.docs.length,
        'databaseCounts': totalDatabaseCounts,
        'totalUsdaResults': totalUsdaResults,
        'databasesUsed': allDatabasesUsed.toList(),
        'averageConfidence': confidenceScores.isNotEmpty 
            ? confidenceScores.reduce((a, b) => a + b) / confidenceScores.length
            : 0.0,
        'mostUsedDatabase': totalDatabaseCounts.isNotEmpty 
            ? totalDatabaseCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key
            : 'None',
      };
      
    } catch (e) {
      print('❌ Error getting USDA statistics: $e');
      throw Exception('Failed to get USDA statistics: $e');
    }
  }
}