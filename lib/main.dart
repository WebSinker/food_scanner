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
      title: 'Enhanced USDA Food Scanner',
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

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  final ScrollController _scrollController = ScrollController();
  
  File? _selectedImage;
  bool _isAnalyzing = false;
  bool _isSaving = false;
  List<FoodResult> _results = [];
  String? _lastScanId;
  
  // Animation controllers for smooth UX
  late AnimationController _buttonsAnimationController;
  late AnimationController _imageAnimationController;
  late Animation<double> _buttonsAnimation;
  late Animation<double> _imageAnimation;
  
  bool _isImageCollapsed = false;
  bool _areButtonsVisible = true;
  bool _hasAnalyzedOnce = false;
  bool _isTotalSummaryCollapsed = true; // Start collapsed
  bool _allowSummaryExpansion = false; // Only allow expansion when scrolled
  
  // Updated URL for enhanced backend
  static const String FIREBASE_FUNCTION_URL = 
      'https://food-analyzer-pwtj4ty7sq-uc.a.run.app/analyze-food';

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controllers
    _buttonsAnimationController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    _imageAnimationController = AnimationController(
      duration: Duration(milliseconds: 400),
      vsync: this,
    );
    
    _buttonsAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _buttonsAnimationController, curve: Curves.easeInOut),
    );
    _imageAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _imageAnimationController, curve: Curves.easeInOut),
    );
    
    // Set up scroll listener
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // Only handle scroll-based behavior if we have results
    if (_results.isEmpty) return;
    
    final scrollPosition = _scrollController.position.pixels;
    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    
    // Enable summary expansion when user has scrolled into results (> 50px)
    if (scrollPosition > 50 && !_allowSummaryExpansion) {
      setState(() {
        _allowSummaryExpansion = true;
      });
    }
    
    // When user scrolls down into results (> 100px from top)
    if (scrollPosition > 100) {
      // Hide buttons and collapse image for more viewing space
      if (_areButtonsVisible || !_isImageCollapsed) {
        setState(() {
          _areButtonsVisible = false;
          _isImageCollapsed = true;
        });
        _buttonsAnimationController.forward();
        _imageAnimationController.forward();
      }
    } 
    // When user scrolls back to top (< 50px from top)
    else if (scrollPosition < 50) {
      // Show buttons and expand image
      if (!_areButtonsVisible || _isImageCollapsed) {
        setState(() {
          _areButtonsVisible = true;
          _isImageCollapsed = false;
        });
        _buttonsAnimationController.reverse();
        _imageAnimationController.reverse();
      }
      
      // Reset summary expansion permission and collapse summary when at top
      if (_allowSummaryExpansion) {
        setState(() {
          _allowSummaryExpansion = false;
          _isTotalSummaryCollapsed = true;
        });
      }
    }
    
    // Auto-collapse summary when scrolling near bottom to prevent cutoff
    if (maxScrollExtent > 0 && scrollPosition > (maxScrollExtent - 100)) {
      if (!_isTotalSummaryCollapsed) {
        setState(() {
          _isTotalSummaryCollapsed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _buttonsAnimationController.dispose();
    _imageAnimationController.dispose();
    super.dispose();
  }

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
          // Keep UI in expanded state when new image is selected
          _isImageCollapsed = false;
          _areButtonsVisible = true;
          _hasAnalyzedOnce = false;
        });
        
        // Reset animations to initial state
        _imageAnimationController.reset();
        _buttonsAnimationController.reset();
        
        // Scroll to top to ensure user sees the new image
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
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
      
      print('🚀 Starting enhanced USDA food analysis...');
      print('📏 Image size: ${bytes.length} bytes');
      
      // Call Enhanced Firebase Function
      final response = await http.post(
        Uri.parse(FIREBASE_FUNCTION_URL),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'image': base64Image,
        }),
      ).timeout(Duration(seconds: 120)); // Increased timeout for comprehensive search

      print('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        print('🔍 Response data keys: ${data.keys.toList()}');
        
        if (data['success'] == true && data['foods'] != null) {
          List<FoodResult> results = [];
          
          print('📊 Processing ${data['foods'].length} food items...');
          
          for (int i = 0; i < data['foods'].length; i++) {
            var food = data['foods'][i];
            try {
              print('\n🍽️ Processing item ${i + 1}: ${food['name']}');
              
              // Use enhanced factory method
              final foodResult = FoodResult.fromEnhancedApi(food);
              results.add(foodResult);
              
              // Log enhanced data
              print('   🗃️ Database: ${foodResult.databaseType}');
              print('   🔢 FDC ID: ${foodResult.fdcId ?? 'N/A'}');
              print('   🏷️ NDB Number: ${foodResult.ndbNumber ?? 'N/A'}');
              print('   📊 Confidence: ${(foodResult.confidence * 100).toInt()}%');
              print('   🔍 USDA Results: ${foodResult.usdaSearchResults ?? 0}');
              
            } catch (e) {
              print('❌ Error parsing food item ${i + 1}: $e');
              print('   📄 Raw data: $food');
            }
          }
          
          if (results.isNotEmpty) {
            setState(() {
              _results = results;
              _areButtonsVisible = true;
              _isImageCollapsed = false;
              _hasAnalyzedOnce = true;
            });
            
            // Log detailed analysis results
            FoodAnalysisLogger.logDetailedResults(_results);
            FoodAnalysisLogger.logNdbNumbers(_results);
            
            // Reset animations to ensure proper initial state
            _buttonsAnimationController.reset();
            _imageAnimationController.reset();
            
            print('✅ Analysis complete: ${_results.length} items processed');
            
          } else {
            _showError('No food items detected. Please try with a clearer image.');
          }
        } else {
          _showError('Analysis failed: ${data['error'] ?? 'Unknown error'}');
          print('❌ API Error details: $data');
        }
      } else {
        final errorBody = response.body;
        print('❌ Server error ${response.statusCode}: $errorBody');
        _showError('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Analysis error: $e');
      if (e.toString().contains('TimeoutException')) {
        _showError('Analysis timed out. The comprehensive USDA search takes longer but provides better results. Please try again.');
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

  void _toggleImageCollapse() {
    setState(() {
      _isImageCollapsed = !_isImageCollapsed;
    });
    
    if (_isImageCollapsed) {
      _imageAnimationController.forward();
    } else {
      _imageAnimationController.reverse();
    }
    
    // If user manually expands image, scroll to top to show buttons
    if (!_isImageCollapsed && !_areButtonsVisible) {
      _scrollController.animateTo(
        0,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
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
      print('💾 Starting save process with enhanced data...');
      print('📊 Results count: ${_results.length}');
      
      // Log what we're saving
      for (final result in _results) {
        print('   📋 ${result.name}: ${result.dataSourceInfo}');
      }
      
      String scanId = await FirebaseService.saveScanResult(
        results: _results,
        imagePath: _selectedImage!.path,
        metadata: {
          'appVersion': '2.0.0',
          'deviceInfo': Platform.operatingSystem,
          'analysisTimestamp': DateTime.now().toIso8601String(),
          'enhancedAnalysis': true,
          'usdaDatabases': _results
              .where((r) => r.databasesSearched != null)
              .expand((r) => r.databasesSearched!)
              .toSet()
              .toList(),
          'totalUsdaResults': _results
              .map((r) => r.usdaSearchResults ?? 0)
              .reduce((a, b) => a + b),
        },
      ).timeout(
        Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Save operation timed out after 30 seconds. Please check your internet connection.');
        },
      );

      print('✅ Save successful with ID: $scanId');
      
      setState(() {
        _lastScanId = scanId;
      });

      _showSuccess('Enhanced scan saved successfully!');
      
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
      _isImageCollapsed = false;
      _areButtonsVisible = true;
      _hasAnalyzedOnce = false;
      _isTotalSummaryCollapsed = true; // Reset to collapsed
      _allowSummaryExpansion = false; // Reset expansion permission
    });
    
    // Reset animations to initial state
    _imageAnimationController.reset();
    _buttonsAnimationController.reset();
    
    // Scroll back to top
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Enhanced USDA Food Scanner'),
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
          // Image section with smooth animation
          AnimatedBuilder(
            animation: _imageAnimation,
            builder: (context, child) {
              final height = _isImageCollapsed 
                ? 80.0 + (200.0 * _imageAnimation.value)
                : 280.0;
              
              return Container(
                height: height,
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      if (_selectedImage != null)
                        Positioned.fill(
                          child: Image.file(
                            _selectedImage!,
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        _buildEmptyImagePlaceholder(),
                      
                      // Collapse/expand toggle (only show when there are results)
                      if (_results.isNotEmpty)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: IconButton(
                              onPressed: _toggleImageCollapse,
                              icon: Icon(
                                _isImageCollapsed ? Icons.expand_more : Icons.expand_less,
                                color: Colors.white,
                              ),
                              iconSize: 20,
                            ),
                          ),
                        ),
                      
                      // Image info overlay when collapsed
                      if (_isImageCollapsed && _selectedImage != null)
                        Positioned(
                          bottom: 8,
                          left: 8,
                          right: 48,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Analyzed Image • Scroll up to expand',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Action buttons section
          if (_results.isEmpty)
            _buildActionButtons()
          else if (_hasAnalyzedOnce && _areButtonsVisible)
            _buildActionButtons()
          else if (_hasAnalyzedOnce && !_areButtonsVisible)
            SizedBox.shrink()
          else
            _buildActionButtons(),

          // Results section with enhanced display
          if (_results.isNotEmpty)
            Expanded(
              child: Column(
                children: [
                  // Enhanced results header
                  Container(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green[50]!, Colors.blue[50]!],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      border: Border(
                        bottom: BorderSide(color: Colors.green[200]!, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.science, color: Colors.green[700]),
                        SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Enhanced USDA Analysis',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                ),
                              ),
                              Text(
                                'Comprehensive nutrition database search',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_areButtonsVisible)
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Scroll for focus view',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green[700],
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Scroll up for options',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue[700],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Enhanced scrollable results
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final result = _results[index];
                        return _buildEnhancedFoodCard(result, index);
                      },
                    ),
                  ),
                  
                  // Enhanced total calories summary
                  _buildEnhancedTotalSummary(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEnhancedFoodCard(FoodResult result, int index) {
    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Enhanced header with database info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.name,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      if (result.databaseMatch != null)
                        Text(
                          result.databaseMatch!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    _buildConfidenceBadge(result),
                    SizedBox(height: 4),
                    _buildDatabaseBadge(result),
                  ],
                ),
              ],
            ),
            
            SizedBox(height: 16),
            
            // Enhanced data source info
            if (result.fdcId != null || result.ndbNumber != null)
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[25],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[100]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.storage, size: 16, color: Colors.blue[700]),
                        SizedBox(width: 6),
                        Text(
                          'USDA Database Match',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    if (result.fdcId != null)
                      Text('FDC ID: ${result.fdcId}', 
                           style: TextStyle(fontSize: 11, color: Colors.blue[600])),
                    if (result.ndbNumber != null && result.ndbNumber != 'N/A')
                      Text('NDB: ${result.ndbNumber}', 
                           style: TextStyle(fontSize: 11, color: Colors.blue[600])),
                    if (result.usdaSearchResults != null)
                      Text('${result.usdaSearchResults} database results found', 
                           style: TextStyle(fontSize: 11, color: Colors.blue[600])),
                  ],
                ),
              ),
            
            SizedBox(height: 16),
            
            // Calories prominently displayed
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Calories',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        '${result.calculatedTotalCalories.toInt()}',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Weight',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        '${result.weight.toInt()}g',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 16),
            
            // Weight slider
            Text(
              'Adjust portion size:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 12),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 20),
              ),
              child: Slider(
                value: result.weight,
                min: 10,
                max: 500,
                divisions: 49,
                label: '${result.weight.round()}g',
                onChanged: (value) => _updateWeight(index, value),
                activeColor: Colors.green[600],
                inactiveColor: Colors.green[100],
              ),
            ),
            
            // Enhanced nutrition info
            if (result.nutrients != null) ...[
              SizedBox(height: 16),
              Text(
                'Detailed nutrition breakdown:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              SizedBox(height: 12),
              _buildNutritionGrid(result),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConfidenceBadge(FoodResult result) {
    Color badgeColor;
    if (result.confidence > 0.7) {
      badgeColor = Colors.green;
    } else if (result.confidence > 0.5) {
      badgeColor = Colors.orange;
    } else {
      badgeColor = Colors.red;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '${(result.confidence * 100).toInt()}%',
        style: TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDatabaseBadge(FoodResult result) {
    Color badgeColor;
    String badgeText = result.databaseType;
    
    switch (result.databaseType) {
      case 'Foundation':
        badgeColor = Colors.purple;
        break;
      case 'SR Legacy':
        badgeColor = Colors.blue;
        break;
      case 'Survey (FNDDS)':
        badgeColor = Colors.teal;
        badgeText = 'Survey';
        break;
      case 'Branded':
        badgeColor = Colors.indigo;
        break;
      case 'Estimated':
        badgeColor = Colors.grey;
        break;
      default:
        badgeColor = Colors.grey;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withOpacity(0.3)),
      ),
      child: Text(
        badgeText,
        style: TextStyle(
          color: badgeColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildNutritionGrid(FoodResult result) {
    final nutrients = result.nutrients!;
    final macroPercentages = nutrients.getMacroPercentages(result.weight);
    
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildEnhancedNutrientCard(
                'Protein', 
                '${nutrients.adjustedProtein(result.weight).toInt()}g',
                '${macroPercentages['protein']!.toInt()}%',
                Colors.red[100]!, 
                Colors.red[700]!
              )
            ),
            SizedBox(width: 8),
            Expanded(
              child: _buildEnhancedNutrientCard(
                'Carbs', 
                '${nutrients.adjustedCarbs(result.weight).toInt()}g',
                '${macroPercentages['carbs']!.toInt()}%',
                Colors.blue[100]!, 
                Colors.blue[700]!
              )
            ),
          ],
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildEnhancedNutrientCard(
                'Fat', 
                '${nutrients.adjustedFat(result.weight).toInt()}g',
                '${macroPercentages['fat']!.toInt()}%',
                Colors.orange[100]!, 
                Colors.orange[700]!
              )
            ),
            SizedBox(width: 8),
            Expanded(
              child: _buildEnhancedNutrientCard(
                'Fiber', 
                '${nutrients.adjustedFiber(result.weight).toInt()}g',
                '',
                Colors.green[100]!, 
                Colors.green[700]!
              )
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEnhancedNutrientCard(String label, String value, String percentage, Color bgColor, Color textColor) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textColor.withOpacity(0.8),
            ),
          ),
          SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          if (percentage.isNotEmpty) ...[
            SizedBox(height: 2),
            Text(
              percentage,
              style: TextStyle(
                fontSize: 10,
                color: textColor.withOpacity(0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEnhancedTotalSummary() {
    // Count database types
    Map<String, int> dbCounts = {};
    for (final result in _results) {
      dbCounts[result.databaseType] = (dbCounts[result.databaseType] ?? 0) + 1;
    }

    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      child: Column(
        children: [
          // Always visible compact summary
          GestureDetector(
            onTap: _allowSummaryExpansion ? () {
              setState(() {
                _isTotalSummaryCollapsed = !_isTotalSummaryCollapsed;
              });
            } : () {
              // Show a hint to scroll down
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Scroll down into results to view details'),
                  duration: Duration(seconds: 2),
                  backgroundColor: Colors.blue[600],
                ),
              );
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green[100]!, Colors.green[50]!],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                border: Border(top: BorderSide(color: Colors.green[300]!, width: 1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 4,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Compact total display
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green[600],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${_totalCalories.toInt()} cal',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          '${_results.length} item${_results.length != 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Expand/collapse indicator with conditional styling and interaction
                  AnimatedOpacity(
                    duration: Duration(milliseconds: 300),
                    opacity: _allowSummaryExpansion ? 1.0 : 0.6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _allowSummaryExpansion 
                              ? (_isTotalSummaryCollapsed ? 'Show Details' : 'Hide Details')
                              : 'Scroll for Details',
                          style: TextStyle(
                            fontSize: 12,
                            color: _allowSummaryExpansion ? Colors.green[700] : Colors.grey[500],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(width: 4),
                        AnimatedRotation(
                          turns: (_isTotalSummaryCollapsed || !_allowSummaryExpansion) ? 0 : 0.5,
                          duration: Duration(milliseconds: 300),
                          child: Icon(
                            _allowSummaryExpansion ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_down,
                            color: _allowSummaryExpansion ? Colors.green[700] : Colors.grey[500],
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Collapsible detailed summary - only expand if allowed
          AnimatedContainer(
            duration: Duration(milliseconds: 300),
            height: (_isTotalSummaryCollapsed || !_allowSummaryExpansion) ? 0 : null,
            child: (_isTotalSummaryCollapsed || !_allowSummaryExpansion) 
                ? null
                : Container(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green[50]!, Colors.green[50]!.withOpacity(0.5)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Column(
                      children: [
                        SizedBox(height: 12),
                        
                        // Large calorie display
                        Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.green[200]!),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Total Calories',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                '${_totalCalories.toInt()}',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'from ${_results.length} food item${_results.length != 1 ? 's' : ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        SizedBox(height: 12),
                        
                        // Database source summary
                        if (dbCounts.isNotEmpty) ...[
                          Text(
                            'Database Sources',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: dbCounts.entries.map((entry) {
                              MaterialColor badgeColor;
                              switch (entry.key) {
                                case 'Foundation':
                                  badgeColor = Colors.purple;
                                  break;
                                case 'SR Legacy':
                                  badgeColor = Colors.blue;
                                  break;
                                case 'Survey (FNDDS)':
                                  badgeColor = Colors.teal;
                                  break;
                                case 'Branded':
                                  badgeColor = Colors.indigo;
                                  break;
                                default:
                                  badgeColor = Colors.grey;
                              }
                              
                              return Container(
                                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: badgeColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: badgeColor.withOpacity(0.3)),
                                ),
                                child: Text(
                                  '${entry.value}× ${entry.key}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: badgeColor[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // Camera and Gallery buttons
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

        // Enhanced Analyze button
        if (_selectedImage != null && _results.isEmpty)
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
                          Text('Analyzing with Enhanced USDA...'),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.science),
                          SizedBox(width: 8),
                          Text('Analyze with USDA Database', style: TextStyle(fontSize: 16)),
                        ],
                      ),
              ),
            ),
          ),

        // Save button
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
                          Text('Saving Enhanced Data...'),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.save),
                          SizedBox(width: 8),
                          Text('Save Enhanced Scan'),
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
                    'Enhanced Scan Saved Successfully',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyImagePlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.science_outlined,
            size: 72,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            'Enhanced USDA Food Analysis',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            'Comprehensive nutrition database search',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
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

// Scan History Screen (keeping existing implementation)
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

// Daily Summary Screen (keeping existing implementation)
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