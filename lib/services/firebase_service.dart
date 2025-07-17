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
        // Create anonymous user with timeout
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
      
      // More specific auth error handling
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
  
  // Save scan result with enhanced error handling
  static Future<String> saveScanResult({
    required List<FoodResult> results,
    required String imagePath,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      print('💾 Starting save scan process...');
      print('📊 Results count: ${results.length}');
      
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
      
      // Step 3: Prepare data
      print('📝 Step 3: Preparing data...');
      double totalCalories = results.fold(0.0, (sum, result) => sum + result.calculatedTotalCalories);
      print('🔥 Total calories: $totalCalories');
      
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
      };
      
      print('📄 Step 4: Saving to Firestore collection: $SCANS_COLLECTION');
      
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
          
          print('✅ Save successful on attempt $attempts');
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
      
      print('✅ Scan saved successfully with ID: ${docRef.id}');
      return docRef.id;
      
    } catch (e) {
      print('❌ Save error details: $e');
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
        throw Exception('Failed to save scan: ${e.toString()}');
      }
    }
  }
  
  // Rest of your methods remain the same...
  static Future<List<Map<String, dynamic>>> getUserScanHistory({
    int limit = 20,
    DateTime? startAfter,
  }) async {
    try {
      print('📚 Loading scan history...');
      String userId = await getCurrentUserId();
      
      Query query = _firestore
          .collection(SCANS_COLLECTION)
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .orderBy(FieldPath.documentId); // This uses __name__
      
      if (startAfter != null) {
        query = query.startAfter([Timestamp.fromDate(startAfter)]);
      }
      
      QuerySnapshot snapshot = await query.limit(limit).get()
          .timeout(Duration(seconds: 15));
      
      List<Map<String, dynamic>> history = snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
      
      print('✅ Loaded ${history.length} scan records');
      return history;
      
    } catch (e) {
      print('❌ Error getting scan history: $e');
      throw Exception('Failed to get scan history: $e');
    }
  }
  
  // Other methods remain the same...
  static Future<Map<String, dynamic>?> getScanById(String scanId) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection(SCANS_COLLECTION)
          .doc(scanId)
          .get()
          .timeout(Duration(seconds: 15));
      
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }
      
      return null;
      
    } catch (e) {
      print('❌ Error getting scan: $e');
      throw Exception('Failed to get scan: $e');
    }
  }
  
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
  
  static Future<Map<String, dynamic>> getDailyCaloriesSummary(DateTime date) async {
    try {
      print('📊 Loading daily summary for: $date');
      String userId = await getCurrentUserId();
      
      DateTime startOfDay = DateTime(date.year, date.month, date.day);
      DateTime endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);
      
      QuerySnapshot snapshot = await _firestore
          .collection(SCANS_COLLECTION)
          .where('userId', isEqualTo: userId)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .get()
          .timeout(Duration(seconds: 15));
      
      double totalCalories = 0;
      int scanCount = 0;
      double totalProtein = 0;
      double totalCarbs = 0;
      double totalFat = 0;
      double totalFiber = 0;
      
      for (var doc in snapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        totalCalories += (data['totalCalories'] ?? 0).toDouble();
        scanCount++;
        
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
      
      print('✅ Daily summary loaded: ${scanCount} scans, ${totalCalories.toInt()} calories');
      
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
      };
      
    } catch (e) {
      print('❌ Error getting daily summary: $e');
      throw Exception('Failed to get daily summary: $e');
    }
  }
}