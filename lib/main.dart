import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/firebase_service.dart';
import 'models/food_models.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with generated options
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(FoodApp());
}

class FoodApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Food Calorie Scanner',
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
      ),
      home: HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  bool _isAnalyzing = false;
  bool _isSaving = false;
  List<FoodResult> _results = [];
  String? _lastScanId;

  static const String FIREBASE_FUNCTION_URL = 
      'https://food-analyzer-pwtj4ty7sq-uc.a.run.app/analyze-food';

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _results = [];
          _lastScanId = null;
        });
      }
    } catch (e) {
      _showError('Failed to pick image: $e');
    }
  }

  Future<void> _analyzeFood() async {
    if (_selectedImage == null) return;

    setState(() {
      _isAnalyzing = true;
      _results = [];
    });

    try {
      // Convert image to base64
      final bytes = await _selectedImage!.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      print('Sending image to AI for analysis...');
      
      // Call Firebase Function with Gemini
      final response = await http.post(
        Uri.parse(FIREBASE_FUNCTION_URL),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'image': base64Image,
        }),
      ).timeout(Duration(seconds: 60));

      print('Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true && data['foods'] != null) {
          List<FoodResult> results = [];
          
          for (var food in data['foods']) {
            try {
              results.add(FoodResult(
                name: food['name'] ?? 'Unknown Food',
                calories: (food['calories_per_100g'] ?? 200).toDouble(),
                confidence: (food['confidence'] ?? 0.5).toDouble(),
                weight: (food['estimated_weight_grams'] ?? 100).toDouble(),
                totalCaloriesFromAI: (food['total_calories'] ?? 200).toDouble(),
                nutrients: food['nutrients'] != null 
                    ? NutrientInfo.fromJson(food['nutrients']) 
                    : null,
              ));
            } catch (e) {
              print('Error parsing food item: $e');
            }
          }
          
          if (results.isNotEmpty) {
            setState(() {
              _results = results;
            });
          } else {
            _showError('No food items detected. Please try with a clearer image.');
          }
        } else {
          _showError('Analysis failed: ${data['error'] ?? 'Unknown error'}');
        }
      } else {
        _showError('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('Analysis error: $e');
      if (e.toString().contains('TimeoutException')) {
        _showError('Analysis timed out. Please try again with a smaller image.');
      } else if (e.toString().contains('SocketException')) {
        _showError('Network error. Please check your internet connection.');
      } else {
        _showError('Analysis failed: $e');
      }
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  Future<void> _saveScanResult() async {
    if (_results.isEmpty || _selectedImage == null) {
      _showError('No results to save');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      print('🔧 Starting save process...');
      print('📊 Results count: ${_results.length}');
      print('🖼️ Image path: ${_selectedImage!.path}');
      
      // Add a timeout wrapper
      String scanId = await FirebaseService.saveScanResult(
        results: _results,
        imagePath: _selectedImage!.path,
        metadata: {
          'appVersion': '1.0.0',
          'deviceInfo': Platform.operatingSystem,
          'analysisTimestamp': DateTime.now().toIso8601String(),
        },
      ).timeout(
        Duration(seconds: 30), // 30 second timeout
        onTimeout: () {
          throw Exception('Save operation timed out after 30 seconds. Please check your internet connection.');
        },
      );

      print('✅ Save successful with ID: $scanId');
      
      setState(() {
        _lastScanId = scanId;
      });

      _showSuccess('Scan saved successfully!');
      
    } catch (e) {
      print('❌ Save error details: $e');
      print('❌ Error type: ${e.runtimeType}');
      
      String errorMessage = 'Failed to save scan';
      
      if (e.toString().contains('TimeoutException') || e.toString().contains('timed out')) {
        errorMessage = 'Save timed out. Please check your internet connection and try again.';
      } else if (e.toString().contains('PERMISSION_DENIED')) {
        errorMessage = 'Permission denied. Firebase may not be properly configured.';
      } else if (e.toString().contains('UNAUTHENTICATED')) {
        errorMessage = 'Authentication failed. Please restart the app.';
      } else if (e.toString().contains('UNAVAILABLE')) {
        errorMessage = 'Firebase service unavailable. Please try again later.';
      } else {
        errorMessage = 'Save failed: ${e.toString()}';
      }
      
      _showError(errorMessage);
    } finally {
      // ALWAYS reset the loading state
      setState(() {
        _isSaving = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _updateWeight(int index, double newWeight) {
    setState(() {
      _results[index] = _results[index].copyWith(weight: newWeight);
    });
  }

  double get _totalCalories {
    return _results.fold(0.0, (sum, result) => sum + result.calculatedTotalCalories);
  }

  void _resetAnalysis() {
    setState(() {
      _selectedImage = null;
      _results = [];
      _lastScanId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('AI Food Calorie Scanner'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_selectedImage != null || _results.isNotEmpty)
            IconButton(
              onPressed: _resetAnalysis,
              icon: Icon(Icons.refresh),
              tooltip: 'Reset',
            ),
          IconButton(
            onPressed: () => _navigateToHistory(),
            icon: Icon(Icons.history),
            tooltip: 'Scan History',
          ),
          IconButton(
            onPressed: () => _navigateToDailySummary(),
            icon: Icon(Icons.analytics),
            tooltip: 'Daily Summary',
          ),
        ],
      ),
      body: Column(
        children: [
          // Image section
          Container(
            height: 280,
            width: double.infinity,
            margin: EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: _selectedImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _selectedImage!,
                      fit: BoxFit.cover,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.camera_alt_outlined,
                        size: 72,
                        color: Colors.grey[400],
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Select a food image to analyze',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Take a photo or choose from gallery',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
          ),

          // Action buttons
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: Icon(Icons.camera_alt),
                    label: Text('Camera'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: Icon(Icons.photo_library),
                    label: Text('Gallery'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 16),

          // Analyze button
          if (_selectedImage != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isAnalyzing ? null : _analyzeFood,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[600],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isAnalyzing
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Analyzing with AI...'),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_awesome),
                            SizedBox(width: 8),
                            Text('Analyze Food', style: TextStyle(fontSize: 16)),
                          ],
                        ),
                ),
              ),
            ),

          // Save button (appears after analysis)
          if (_results.isNotEmpty && _lastScanId == null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveScanResult,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple[600],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSaving
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('Saving...'),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.save),
                            SizedBox(width: 8),
                            Text('Save Scan'),
                          ],
                        ),
                ),
              ),
            ),

          // Saved indicator
          if (_lastScanId != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  border: Border.all(color: Colors.green[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[700]),
                    SizedBox(width: 8),
                    Text(
                      'Scan Saved Successfully',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Results section (rest of your existing code)
          if (_results.isNotEmpty)
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.restaurant_menu, color: Colors.green[700]),
                        SizedBox(width: 8),
                        Text(
                          'AI Analysis Results',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final result = _results[index];
                        return Card(
                          margin: EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Food name and confidence
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        result.name,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[800],
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: result.confidence > 0.7
                                            ? Colors.green
                                            : result.confidence > 0.5
                                                ? Colors.orange
                                                : Colors.red,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${(result.confidence * 100).toInt()}%',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                
                                SizedBox(height: 12),
                                
                                // Weight slider
                                Text(
                                  'Adjust portion size:',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Slider(
                                  value: result.weight,
                                  min: 10,
                                  max: 500,
                                  divisions: 49,
                                  label: '${result.weight.round()}g',
                                  onChanged: (value) => _updateWeight(index, value),
                                  activeColor: Colors.green[600],
                                ),
                                
                                // Calories info
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Calories: ${result.calculatedTotalCalories.toInt()}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green[700],
                                      ),
                                    ),
                                    Text(
                                      '${result.weight.toInt()}g',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                
                                // Nutrition info
                                if (result.nutrients != null) ...[
                                  SizedBox(height: 12),
                                  Text(
                                    'Nutrition:',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      _buildNutrientChip('Protein', '${result.nutrients!.adjustedProtein(result.weight).toInt()}g', Colors.red[100]!),
                                      _buildNutrientChip('Carbs', '${result.nutrients!.adjustedCarbs(result.weight).toInt()}g', Colors.blue[100]!),
                                      _buildNutrientChip('Fat', '${result.nutrients!.adjustedFat(result.weight).toInt()}g', Colors.orange[100]!),
                                      _buildNutrientChip('Fiber', '${result.nutrients!.adjustedFiber(result.weight).toInt()}g', Colors.green[100]!),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  
                  // Total calories summary
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      border: Border(top: BorderSide(color: Colors.grey[300]!)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Calories:',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        Text(
                          '${_totalCalories.toInt()}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNutrientChip(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.grey[800],
        ),
      ),
    );
  }

  void _navigateToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ScanHistoryScreen()),
    );
  }

  void _navigateToDailySummary() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DailySummaryScreen()),
    );
  }
}

// Scan History Screen
class ScanHistoryScreen extends StatefulWidget {
  @override
  _ScanHistoryScreenState createState() => _ScanHistoryScreenState();
}

class _ScanHistoryScreenState extends State<ScanHistoryScreen> {
  List<Map<String, dynamic>> _scanHistory = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadScanHistory();
  }

  Future<void> _loadScanHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      List<Map<String, dynamic>> history = await FirebaseService.getUserScanHistory();
      setState(() {
        _scanHistory = history;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteScan(String scanId, int index) async {
    try {
      await FirebaseService.deleteScan(scanId);
      setState(() {
        _scanHistory.removeAt(index);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scan deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete scan: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scan History'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadScanHistory,
            icon: Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 64, color: Colors.red),
                      SizedBox(height: 16),
                      Text('Error loading history'),
                      SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadScanHistory,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _scanHistory.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No scan history yet',
                            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Start scanning food to see your history here',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: _scanHistory.length,
                      itemBuilder: (context, index) {
                        final scan = _scanHistory[index];
                        final timestamp = scan['timestamp']?.toDate() ?? DateTime.now();
                        final totalCalories = (scan['totalCalories'] ?? 0).toDouble();
                        final foodItems = List<Map<String, dynamic>>.from(scan['foodItems'] ?? []);

                        return Card(
                          margin: EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: EdgeInsets.all(16),
                            leading: CircleAvatar(
                              backgroundColor: Colors.green[100],
                              child: Icon(Icons.restaurant_menu, color: Colors.green[700]),
                            ),
                            title: Text(
                              '${foodItems.length} food item${foodItems.length != 1 ? 's' : ''}',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(height: 4),
                                Text(
                                  'Total: ${totalCalories.toInt()} calories',
                                  style: TextStyle(
                                    color: Colors.green[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  _formatDateTime(timestamp),
                                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                ),
                                if (foodItems.isNotEmpty) ...[
                                  SizedBox(height: 8),
                                  Wrap(
                                    spacing: 4,
                                    children: foodItems.take(3).map((item) {
                                      return Container(
                                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue[50],
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          item['name'] ?? 'Unknown',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.blue[700],
                                          ),
                                        ),
                                      );
                                    }).toList()
                                      ..add(
                                        foodItems.length > 3
                                            ? Container(
                                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey[200],
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  '+${foodItems.length - 3} more',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              )
                                            : Container(),
                                      ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'delete') {
                                  _showDeleteConfirmation(scan['id'], index);
                                } else if (value == 'details') {
                                  _showScanDetails(scan);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'details',
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline, size: 16),
                                      SizedBox(width: 8),
                                      Text('View Details'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Delete', style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} hours ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  void _showDeleteConfirmation(String scanId, int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Delete Scan'),
          content: Text('Are you sure you want to delete this scan? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteScan(scanId, index);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showScanDetails(Map<String, dynamic> scan) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final foodItems = List<Map<String, dynamic>>.from(scan['foodItems'] ?? []);
        final timestamp = scan['timestamp']?.toDate() ?? DateTime.now();

        return AlertDialog(
          title: Text('Scan Details'),
          content: Container(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Date: ${_formatDateTime(timestamp)}'),
                SizedBox(height: 8),
                Text('Total Calories: ${(scan['totalCalories'] ?? 0).toInt()}'),
                SizedBox(height: 16),
                Text('Food Items:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Container(
                  height: 200,
                  child: ListView.builder(
                    itemCount: foodItems.length,
                    itemBuilder: (context, index) {
                      final item = foodItems[index];
                      return Card(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['name'] ?? 'Unknown',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text('Weight: ${(item['weight'] ?? 0).toInt()}g'),
                              Text('Calories: ${(item['totalCalories'] ?? 0).toInt()}'),
                              if (item['nutrients'] != null) ...[
                                SizedBox(height: 4),
                                Text(
                                  'P: ${(item['nutrients']['protein'] ?? 0).toInt()}g, '
                                  'C: ${(item['nutrients']['carbs'] ?? 0).toInt()}g, '
                                  'F: ${(item['nutrients']['fat'] ?? 0).toInt()}g',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

// Daily Summary Screen
class DailySummaryScreen extends StatefulWidget {
  @override
  _DailySummaryScreenState createState() => _DailySummaryScreenState();
}

class _DailySummaryScreenState extends State<DailySummaryScreen> {
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic>? _dailySummary;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDailySummary();
  }

  Future<void> _loadDailySummary() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      Map<String, dynamic> summary = await FirebaseService.getDailyCaloriesSummary(_selectedDate);
      setState(() {
        _dailySummary = summary;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadDailySummary();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Daily Summary'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _selectDate,
            icon: Icon(Icons.calendar_today),
            tooltip: 'Select Date',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 64, color: Colors.red),
                      SizedBox(height: 16),
                      Text('Error loading summary'),
                      SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadDailySummary,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date selector
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDate(_selectedDate),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _selectDate,
                                icon: Icon(Icons.calendar_today, size: 16),
                                label: Text('Change Date'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue[600],
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: 16),

                      // Calories summary
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.local_fire_department, color: Colors.orange),
                                  SizedBox(width: 8),
                                  Text(
                                    'Calories',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 16),
                              Center(
                                child: Column(
                                  children: [
                                    Text(
                                      '${(_dailySummary?['totalCalories'] ?? 0).toInt()}',
                                      style: TextStyle(
                                        fontSize: 48,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange[700],
                                      ),
                                    ),
                                    Text(
                                      'Total Calories',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildStatItem(
                                    'Scans',
                                    '${_dailySummary?['scanCount'] ?? 0}',
                                    Icons.camera_alt,
                                    Colors.blue,
                                  ),
                                  _buildStatItem(
                                    'Avg/Scan',
                                    _dailySummary?['scanCount'] != null && _dailySummary!['scanCount'] > 0
                                        ? '${((_dailySummary!['totalCalories'] ?? 0) / _dailySummary!['scanCount']).toInt()}'
                                        : '0',
                                    Icons.trending_up,
                                    Colors.green,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: 16),

                      // No data message
                      if ((_dailySummary?['totalCalories'] ?? 0) == 0)
                        Card(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.no_meals,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No scans for this date',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Start scanning food to track your daily nutrition',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == yesterday) {
      return 'Yesterday';
    } else {
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    }
  }
}