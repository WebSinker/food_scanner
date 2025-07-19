from firebase_functions import https_fn, options
from flask import Flask, request, jsonify
import base64
import json
import requests
import os
import re
import asyncio
import httpx
import time

app = Flask(__name__)

# Securely get API keys from Firebase Secrets
GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY')
USDA_API_KEY = os.environ.get('USDA_API_KEY')
GEMINI_API_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent'
USDA_BASE_URL = "https://api.nal.usda.gov/fdc/v1"

# Logging functions
def log_function_call(function_name, **kwargs):
    """Log when functions are called"""
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"🟢 [{timestamp}] FUNCTION CALLED: {function_name}")
    for key, value in kwargs.items():
        print(f"   📝 {key}: {value}")

def log_api_call(api_name, url, status_code, response_time=None):
    """Log API calls"""
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"🔵 [{timestamp}] API CALL: {api_name}")
    print(f"   🌐 URL: {url}")
    print(f"   📊 Status: {status_code}")
    if response_time:
        print(f"   ⏱️ Time: {response_time:.2f}s")

@app.route('/health', methods=['GET'])
def health_check():
    gemini_key_status = "configured" if GEMINI_API_KEY else "missing"
    usda_key_status = "configured" if USDA_API_KEY else "missing"
    
    return jsonify({
        'status': 'healthy', 
        'service': 'enhanced-usda-food-analyzer',
        'gemini_api_key': gemini_key_status,
        'usda_api_key': usda_key_status,
        'security': 'secrets-based',
        'features': ['ai_analysis', 'multi_database_usda_search', 'ndb_logging'],
        'supported_databases': ['Foundation', 'SR Legacy', 'Survey (FNDDS)', 'Branded']
    })

@app.route('/analyze-food', methods=['POST'])
def analyze_food():
    try:
        print("=== Starting Enhanced USDA-Only Food Analysis ===")
        
        # Get JSON data
        try:
            data = request.get_json(force=True)
            print(f"Received data keys: {list(data.keys()) if data else 'No data'}")
        except Exception as e:
            print(f"JSON parsing error: {str(e)}")
            return jsonify({'error': f'Invalid JSON: {str(e)}'}), 400
        
        if not data:
            print("No data provided")
            return jsonify({'error': 'No data provided'}), 400
        
        image_data = data.get('image')
        if not image_data:
            print("No image provided in data")
            return jsonify({'error': 'No image provided'}), 400
        
        print(f"Image data length: {len(image_data) if image_data else 0}")
        
        # Remove data URL prefix if present
        if 'base64,' in image_data:
            image_data = image_data.split('base64,')[1]
            print("Removed data URL prefix")
        
        # For testing, if image is just "test", return mock data
        if image_data == "test":
            print("Using test mock data")
            mock_results = [{
                "name": "Test Food Item",
                "calories_per_100g": 200,
                "estimated_weight_grams": 150,
                "total_calories": 300,
                "confidence": 0.95,
                "nutrients": {
                    "protein": 10,
                    "carbs": 25,
                    "fat": 8,
                    "fiber": 3
                },
                "data_source": "Test",
                "database_match": "Test data",
                "fdc_id": "TEST123",
                "ndb_number": "TEST_NDB"
            }]
            return jsonify({
                'success': True, 
                'foods': mock_results,
                'enhanced': True,
                'nutrition_database': 'Test'
            })
        
        # Check API keys
        if not GEMINI_API_KEY:
            print("ERROR: No Gemini API key configured")
            return jsonify({
                'success': True,
                'foods': get_fallback_response("No Gemini API key configured")
            })
        
        print("API keys loaded from secure secrets")
        print("Starting Enhanced Gemini analysis...")
        
        # Analyze food with enhanced Gemini + comprehensive USDA search
        results = analyze_with_enhanced_gemini(image_data)
        
        print(f"Enhanced analysis completed, found {len(results)} food items")
        
        return jsonify({
            'success': True,
            'foods': results,
            'enhanced': True,
            'nutrition_database': 'USDA_Multi_Database' if USDA_API_KEY else 'Disabled'
        })
        
    except Exception as e:
        print(f"ERROR in analyze_food: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'error': f'Internal server error: {str(e)}'}), 500

@app.route('/', methods=['GET', 'POST'])
def default_route():
    if request.method == 'GET':
        # Check for health parameter
        if request.args.get('health'):
            return health_check()
        return jsonify({
            'message': 'Enhanced USDA-Only Food Analyzer API', 
            'endpoints': ['/health', '/analyze-food'],
            'features': ['Gemini AI Analysis', 'Multi-Database USDA Search', 'NDB Number Logging'],
            'databases': ['Foundation', 'SR Legacy', 'Survey (FNDDS)', 'Branded']
        })
    elif request.method == 'POST':
        return analyze_food()

async def comprehensive_usda_search(food_name, max_results_per_db=10):
    """
    Search across multiple USDA databases with comprehensive logging
    Priority order: Foundation > SR Legacy > Survey (FNDDS) > Branded
    """
    
    log_function_call("comprehensive_usda_search", 
                     food_name=food_name, 
                     max_results_per_db=max_results_per_db)
    
    try:
        if not USDA_API_KEY:
            print("❌ No USDA API key available")
            return {"status": "error", "error": "No USDA API key"}
        
        # Define database search order (priority-based)
        database_searches = [
            {"name": "Foundation", "dataType": "Foundation", "priority": 1},
            {"name": "SR Legacy", "dataType": "SR Legacy", "priority": 2}, 
            {"name": "Survey (FNDDS)", "dataType": "Survey (FNDDS)", "priority": 3},
            {"name": "Branded", "dataType": "Branded", "priority": 4}
        ]
        
        all_results = []
        best_match = None
        
        print(f"🔍 Starting comprehensive USDA search for: '{food_name}'")
        print(f"🗃️ Will search {len(database_searches)} databases in priority order")
        
        async with httpx.AsyncClient() as client:
            for db_info in database_searches:
                db_name = db_info["name"]
                data_type = db_info["dataType"]
                priority = db_info["priority"]
                
                print(f"\n📊 Searching Database {priority}/4: {db_name}")
                start_time = time.time()
                
                try:
                    params = {
                        "query": food_name,
                        "dataType": data_type,
                        "pageSize": max_results_per_db,
                        "sortBy": "dataType.keyword",
                        "sortOrder": "asc",
                        "api_key": USDA_API_KEY
                    }
                    
                    response = await client.get(f"{USDA_BASE_URL}/foods/search", params=params, timeout=15)
                    
                    search_time = time.time() - start_time
                    log_api_call(f"USDA {db_name}", f"{USDA_BASE_URL}/foods/search", response.status_code, search_time)
                    
                    response.raise_for_status()
                    api_data = response.json()
                    
                    foods = api_data.get("foods", [])
                    total_hits = api_data.get("totalHits", 0)
                    
                    print(f"   ✅ {db_name}: {len(foods)} results (total hits: {total_hits})")
                    
                    # Process results from this database
                    for food in foods:
                        processed_food = process_usda_food_item(food, db_name, priority)
                        if processed_food:
                            all_results.append(processed_food)
                            
                            # Log NDB number and FDC ID for tracking
                            fdc_id = food.get("fdcId", "Unknown")
                            ndb_number = food.get("ndbNumber", "N/A")
                            description = food.get("description", "Unknown")
                            
                            print(f"   📋 Found: {description}")
                            print(f"      🔢 FDC ID: {fdc_id}")
                            print(f"      🏷️ NDB Number: {ndb_number}")
                            print(f"      🗃️ Database: {db_name}")
                            
                            # Set best match if we don't have one yet (first result from highest priority DB)
                            if best_match is None:
                                best_match = processed_food
                                print(f"   ⭐ Set as BEST MATCH (Database: {db_name}, Priority: {priority})")
                
                except Exception as e:
                    print(f"   ❌ Error searching {db_name}: {str(e)}")
                    continue
        
        # Sort all results by database priority, then by relevance
        all_results.sort(key=lambda x: (x.get("database_priority", 99), -x.get("relevance_score", 0)))
        
        print(f"\n📈 SEARCH SUMMARY:")
        print(f"   📊 Total results found: {len(all_results)}")
        print(f"   🏆 Best match database: {best_match.get('data_source', 'None') if best_match else 'None'}")
        print(f"   🔢 Best match FDC ID: {best_match.get('fdc_id', 'None') if best_match else 'None'}")
        print(f"   🏷️ Best match NDB: {best_match.get('ndb_number', 'None') if best_match else 'None'}")
        
        return {
            "status": "success",
            "total_results": len(all_results),
            "best_match": best_match,
            "all_results": all_results[:20],  # Return top 20 results
            "databases_searched": [db["name"] for db in database_searches],
            "search_query": food_name
        }
            
    except Exception as e:
        print(f"❌ Comprehensive USDA search error: {str(e)}")
        return {"status": "error", "error": str(e)}

def process_usda_food_item(food, database_name, priority):
    """Process a single USDA food item and extract relevant nutrition data"""
    try:
        fdc_id = food.get("fdcId")
        description = food.get("description", "")
        ndb_number = food.get("ndbNumber", "N/A")
        
        # Extract nutrients
        nutrients = {}
        for nutrient in food.get("foodNutrients", []):
            nutrient_name = nutrient.get("nutrientName", "").lower()
            nutrient_value = nutrient.get("value", 0)
            nutrient_unit = nutrient.get("unitName", "")
            
            # Map nutrient names to standard keys
            if "energy" in nutrient_name or "calorie" in nutrient_name:
                nutrients["calories"] = {"value": nutrient_value, "unit": nutrient_unit}
            elif "protein" in nutrient_name:
                nutrients["protein"] = {"value": nutrient_value, "unit": nutrient_unit}
            elif "carbohydrate" in nutrient_name:
                nutrients["carbohydrates"] = {"value": nutrient_value, "unit": nutrient_unit}
            elif "total lipid" in nutrient_name or ("fat" in nutrient_name and "sat" not in nutrient_name):
                nutrients["fat"] = {"value": nutrient_value, "unit": nutrient_unit}
            elif "fiber" in nutrient_name:
                nutrients["fiber"] = {"value": nutrient_value, "unit": nutrient_unit}
        
        # Calculate relevance score (higher = better)
        relevance_score = calculate_relevance_score(description, database_name)
        
        return {
            "fdcId": fdc_id,
            "ndb_number": ndb_number,
            "description": description,
            "dataType": food.get("dataType"),
            "nutrients": nutrients,
            "data_source": f"USDA_{database_name.replace(' ', '_')}",
            "database_priority": priority,
            "relevance_score": relevance_score,
            "brandOwner": food.get("brandOwner"),
            "ingredients": food.get("ingredients"),
            "servingSize": food.get("servingSize"),
            "servingSizeUnit": food.get("servingSizeUnit")
        }
        
    except Exception as e:
        print(f"❌ Error processing food item: {str(e)}")
        return None

def calculate_relevance_score(description, database_name):
    """Calculate relevance score for ranking results"""
    score = 0
    
    # Database priority scoring
    db_scores = {
        "Foundation": 100,
        "SR Legacy": 80, 
        "Survey (FNDDS)": 60,
        "Branded": 40
    }
    score += db_scores.get(database_name, 0)
    
    # Description quality scoring
    desc_lower = description.lower()
    
    # Prefer shorter, more specific descriptions
    if len(description) < 50:
        score += 20
    elif len(description) < 100:
        score += 10
    
    # Prefer entries without brand names or complex modifiers
    if not any(word in desc_lower for word in ["brand", "inc.", "corp", "company", "ltd"]):
        score += 15
    
    # Prefer raw/basic foods over processed
    if any(word in desc_lower for word in ["raw", "fresh", "plain"]):
        score += 10
    
    return score

def analyze_with_enhanced_gemini(base64_image):
    """Enhanced Gemini analysis with comprehensive USDA search"""
    
    log_function_call("analyze_with_enhanced_gemini", 
                     image_size=f"{len(base64_image)} characters")
    
    print("=== Enhanced Gemini Analysis with Comprehensive USDA Search ===")
    print("🔍 ANALYSIS FLOW:")
    print("   1. Gemini Vision API → Food identification")
    print("   2. Comprehensive USDA Multi-Database Search")
    print("   3. NDB Number Logging & Best Match Selection")
    print("   4. Enhanced nutrition data integration")
    
    if not GEMINI_API_KEY:
        print("❌ ERROR: No Gemini API key available")
        return get_fallback_response("No Gemini API key configured")
    
    # Validate base64 image
    try:
        decoded = base64.b64decode(base64_image + '==')
        print(f"Base64 image decoded successfully, size: {len(decoded)} bytes")
    except Exception as e:
        print(f"ERROR: Invalid base64 image: {str(e)}")
        return get_fallback_response("Invalid image format")
    
    # Enhanced prompt for better food identification
    prompt = """
    Analyze this food image and identify all visible food items with maximum accuracy.

    For each food item you identify:
    1. Provide the most specific, common food name possible (avoid brand names)
    2. Use standard food terminology that would be found in nutrition databases
    3. Estimate the portion size based on visual cues
    4. Focus on accuracy over specificity for unusual items

    Return a JSON response with this structure:
    [
        {
            "name": "Specific common food name (e.g., 'grilled chicken breast', 'white rice', 'broccoli')",
            "estimated_weight_grams": your_visual_estimate,
            "confidence": confidence_score_0_to_1,
            "preparation_method": "raw|cooked|fried|steamed|grilled|boiled|etc",
            "food_category": "protein|grain|vegetable|fruit|dairy|fat|other",
            "visual_cues": "brief description of what you see"
        }
    ]

    Guidelines:
    - Use common, searchable food names that would be in USDA database
    - For mixed dishes, break them down into main components if possible
    - Estimate portion sizes using plate size, utensils, hand size as reference
    - Be conservative with confidence scores for unclear items
    - Return ONLY the JSON array, no additional text
    """
    
    payload = {
        "contents": [
            {
                "parts": [
                    {
                        "text": prompt
                    },
                    {
                        "inline_data": {
                            "mime_type": "image/jpeg",
                            "data": base64_image
                        }
                    }
                ]
            }
        ],
        "generationConfig": {
            "temperature": 0.1,
            "topK": 32,
            "topP": 1,
            "maxOutputTokens": 2048,
        }
    }
    
    headers_req = {
        'Content-Type': 'application/json',
    }
    
    try:
        print("📡 STEP 1: Calling Gemini Vision API...")
        start_time = time.time()
        
        response = requests.post(
            f"{GEMINI_API_URL}?key={GEMINI_API_KEY}",
            headers=headers_req,
            json=payload,
            timeout=30
        )
        
        gemini_time = time.time() - start_time
        log_api_call("Gemini Vision", GEMINI_API_URL, response.status_code, gemini_time)
        
        if response.status_code == 200:
            result = response.json()
            
            if 'candidates' in result and len(result['candidates']) > 0:
                text_response = result['candidates'][0]['content']['parts'][0]['text']
                print(f"✅ Gemini analysis complete")
                
                # Parse initial response
                initial_results = parse_gemini_response(text_response)
                print(f"📋 Gemini identified {len(initial_results)} food items")
                
                # COMPREHENSIVE USDA NUTRITION ENHANCEMENT
                print("📡 STEP 2: Enhancing with comprehensive USDA database search...")
                enhanced_results = asyncio.run(enhance_with_comprehensive_usda(initial_results))
                
                return enhanced_results
            else:
                print("❌ ERROR: No candidates in Gemini response")
                return get_fallback_response("No response from AI")
        else:
            print(f"❌ Gemini API error: {response.status_code}")
            return get_fallback_response(f"API error: {response.status_code}")
            
    except Exception as e:
        print(f"❌ ERROR: Gemini request failed: {str(e)}")
        return get_fallback_response(f"Request error: {str(e)}")

async def enhance_with_comprehensive_usda(initial_results):
    """Enhanced nutrition data lookup using comprehensive USDA search"""
    
    log_function_call("enhance_with_comprehensive_usda", 
                     food_items=len(initial_results))
    
    print("🔍 COMPREHENSIVE USDA ENHANCEMENT PROCESS:")
    enhanced_results = []
    
    for i, item in enumerate(initial_results, 1):
        food_name = item.get('name', '')
        estimated_weight = item.get('estimated_weight_grams', 100)
        
        print(f"\n📋 Processing food {i}/{len(initial_results)}: {food_name}")
        print(f"   ⚖️ Estimated weight: {estimated_weight}g")
        
        try:
            # Comprehensive USDA search across all databases
            print("   🔍 Starting comprehensive USDA search...")
            nutrition_data = await comprehensive_usda_search(food_name)
            
            if nutrition_data.get('status') == 'success' and nutrition_data.get('best_match'):
                best_match = nutrition_data['best_match']
                
                print(f"   ✅ Best match found: {best_match.get('description', 'Unknown')}")
                print(f"   🗃️ Database: {best_match.get('data_source', 'Unknown')}")
                print(f"   🔢 FDC ID: {best_match.get('fdcId', 'Unknown')}")
                print(f"   🏷️ NDB Number: {best_match.get('ndb_number', 'N/A')}")
                
                # Extract and scale nutrition data
                nutrients = best_match.get('nutrients', {})
                calories_per_100g = nutrients.get('calories', {}).get('value', 200)
                
                scaling_factor = estimated_weight / 100.0
                total_calories = calories_per_100g * scaling_factor
                
                print(f"   🔥 Calories: {calories_per_100g}/100g → {total_calories:.1f} total")
                
                enhanced_results.append({
                    "name": food_name,
                    "calories_per_100g": calories_per_100g,
                    "estimated_weight_grams": estimated_weight,
                    "total_calories": round(total_calories, 1),
                    "confidence": item.get('confidence', 0.8),
                    "nutrients": {
                        "protein": round(nutrients.get('protein', {}).get('value', 0) * scaling_factor, 1),
                        "carbs": round((nutrients.get('carbohydrates', {}).get('value', 0)) * scaling_factor, 1),
                        "fat": round(nutrients.get('fat', {}).get('value', 0) * scaling_factor, 1),
                        "fiber": round(nutrients.get('fiber', {}).get('value', 0) * scaling_factor, 1)
                    },
                    "data_source": best_match.get('data_source', 'USDA'),
                    "database_match": best_match.get('description', ''),
                    "fdc_id": best_match.get('fdcId'),
                    "ndb_number": best_match.get('ndb_number', 'N/A'),
                    "food_category": item.get('food_category', 'other'),
                    "preparation_method": item.get('preparation_method', 'unknown'),
                    "usda_search_results": len(nutrition_data.get('all_results', [])),
                    "databases_searched": nutrition_data.get('databases_searched', [])
                })
                
            else:
                print(f"   ⚠️ No USDA match found, using fallback estimates")
                enhanced_results.append(create_fallback_item(item))
                
        except Exception as e:
            print(f"   ❌ Error processing {food_name}: {str(e)}")
            enhanced_results.append(create_fallback_item(item))
    
    print(f"\n✅ Comprehensive enhancement complete: {len(enhanced_results)} items processed")
    return enhanced_results

def create_fallback_item(item):
    """Create fallback nutrition item when database lookup fails"""
    estimated_weight = item.get('estimated_weight_grams', 100)
    
    return {
        "name": item.get('name', 'Unknown Food'),
        "calories_per_100g": 200,
        "estimated_weight_grams": estimated_weight,
        "total_calories": round(200 * estimated_weight / 100, 1),
        "confidence": max(item.get('confidence', 0.5) - 0.2, 0.3),
        "nutrients": {
            "protein": round(8 * estimated_weight / 100, 1),
            "carbs": round(30 * estimated_weight / 100, 1),
            "fat": round(10 * estimated_weight / 100, 1),
            "fiber": round(4 * estimated_weight / 100, 1)
        },
        "data_source": "Estimated",
        "database_match": "No USDA match found",
        "fdc_id": None,
        "ndb_number": "N/A",
        "food_category": item.get('food_category', 'unknown'),
        "preparation_method": item.get('preparation_method', 'unknown'),
        "usda_search_results": 0,
        "databases_searched": []
    }

def parse_gemini_response(text_response):
    """Parse JSON response from Gemini"""
    try:
        print("=== Parsing Gemini Response ===")
        
        # Clean the response to extract JSON
        cleaned_text = re.sub(r'```json\s*', '', text_response)
        cleaned_text = re.sub(r'```\s*$', '', cleaned_text)
        
        # Find JSON array boundaries
        json_start = cleaned_text.find('[')
        json_end = cleaned_text.rfind(']') + 1
        
        if json_start != -1 and json_end > json_start:
            json_str = cleaned_text[json_start:json_end]
            foods = json.loads(json_str)
            
            # Validate results
            validated_foods = []
            for food in foods:
                if validate_food_item(food):
                    validated_foods.append(food)
            
            return validated_foods if validated_foods else get_default_item()
        else:
            print("No JSON array found in response")
            return get_default_item()
            
    except json.JSONDecodeError as e:
        print(f"JSON parsing error: {str(e)}")
        return get_default_item()

def validate_food_item(food):
    """Validate food item structure"""
    required_fields = ['name', 'estimated_weight_grams', 'confidence']
    
    for field in required_fields:
        if field not in food:
            return False
    
    # Set defaults for missing fields
    if 'food_category' not in food:
        food['food_category'] = 'other'
    if 'preparation_method' not in food:
        food['preparation_method'] = 'unknown'
    
    return True

def get_default_item():
    """Get default item when parsing fails"""
    return [{
        "name": "Unknown Food",
        "estimated_weight_grams": 100,
        "confidence": 0.3,
        "food_category": "other",
        "preparation_method": "unknown"
    }]

def get_fallback_response(error_msg="Analysis failed"):
    """Fallback response when enhanced analysis fails"""
    print(f"Using fallback response: {error_msg}")
    return [{
        "name": f"Food Item ({error_msg})",
        "calories_per_100g": 200,
        "estimated_weight_grams": 150,
        "total_calories": 300,
        "confidence": 0.3,
        "nutrients": {
            "protein": 8,
            "carbs": 30,
            "fat": 10,
            "fiber": 4
        },
        "data_source": "Fallback",
        "database_match": "Analysis failed",
        "fdc_id": None,
        "ndb_number": "N/A",
        "debug_error": error_msg,
        "usda_search_results": 0,
        "databases_searched": []
    }]

# Firebase Functions entry point
@https_fn.on_request(
    cors=options.CorsOptions(
        cors_origins=["*"],
        cors_methods=["POST", "GET", "OPTIONS"]
    ),
    memory=options.MemoryOption.GB_1,
    timeout_sec=120,
    secrets=["GEMINI_API_KEY", "USDA_API_KEY"]
)
def food_analyzer(req):
    with app.request_context(req.environ):
        return app.full_dispatch_request()