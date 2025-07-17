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
        'service': 'enhanced-food-analyzer',
        'gemini_api_key': gemini_key_status,
        'usda_api_key': usda_key_status,
        'security': 'secrets-based',
        'features': ['ai_analysis', 'nutrition_database', 'malaysian_cuisine']
    })

@app.route('/analyze-food', methods=['POST'])
def analyze_food():
    try:
        print("=== Starting Enhanced Food Analysis ===")
        
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
                "database_match": "Test data"
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
        
        # Analyze food with enhanced Gemini + nutrition database
        results = analyze_with_enhanced_gemini(image_data)
        
        print(f"Enhanced analysis completed, found {len(results)} food items")
        
        return jsonify({
            'success': True,
            'foods': results,
            'enhanced': True,
            'nutrition_database': 'USDA' if USDA_API_KEY else 'Disabled'
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
            'message': 'Enhanced Food Analyzer API', 
            'endpoints': ['/health', '/analyze-food'],
            'features': ['Gemini AI Analysis', 'USDA Nutrition Database', 'Malaysian Cuisine Support']
        })
    elif request.method == 'POST':
        return analyze_food()

async def search_food_nutrition(food_name, data_type="Foundation,SR Legacy", page_size=25):
    """Search USDA database with detailed logging"""
    
    log_function_call("search_food_nutrition", 
                     food_name=food_name, 
                     data_type=data_type)
    
    try:
        if not USDA_API_KEY:
            print("❌ No USDA API key available")
            return {"status": "error", "error": "No USDA API key"}
        
        start_time = time.time()
        
        async with httpx.AsyncClient() as client:
            params = {
                "query": food_name,
                "dataType": data_type,
                "pageSize": page_size,
                "sortBy": "dataType.keyword",
                "sortOrder": "asc",
                "api_key": USDA_API_KEY
            }
            
            response = await client.get(f"{USDA_BASE_URL}/foods/search", params=params, timeout=15)
            
            usda_time = time.time() - start_time
            log_api_call("USDA FoodData", f"{USDA_BASE_URL}/foods/search", response.status_code, usda_time)
            
            response.raise_for_status()
            api_data = response.json()
            
            print(f"   📊 USDA returned {api_data.get('totalHits', 0)} results")
            
            # Process and structure the response
            formatted_results = []
            
            for food in api_data.get("foods", []):
                nutrients = {}
                for nutrient in food.get("foodNutrients", []):
                    nutrient_name = nutrient.get("nutrientName", "")
                    nutrient_value = nutrient.get("value", 0)
                    nutrient_unit = nutrient.get("unitName", "")
                    
                    if "protein" in nutrient_name.lower():
                        nutrients["protein"] = {"value": nutrient_value, "unit": nutrient_unit}
                    elif "carbohydrate" in nutrient_name.lower():
                        nutrients["carbohydrates"] = {"value": nutrient_value, "unit": nutrient_unit}
                    elif "total lipid" in nutrient_name.lower() or "fat" in nutrient_name.lower():
                        nutrients["fat"] = {"value": nutrient_value, "unit": nutrient_unit}
                    elif "energy" in nutrient_name.lower():
                        nutrients["calories"] = {"value": nutrient_value, "unit": nutrient_unit}
                    elif "fiber" in nutrient_name.lower():
                        nutrients["fiber"] = {"value": nutrient_value, "unit": nutrient_unit}
                
                formatted_results.append({
                    "fdcId": food.get("fdcId"),
                    "description": food.get("description"),
                    "dataType": food.get("dataType"),
                    "nutrients": nutrients,
                    "brandOwner": food.get("brandOwner"),
                    "ingredients": food.get("ingredients"),
                    "servingSize": food.get("servingSize"),
                    "servingSizeUnit": food.get("servingSizeUnit")
                })
            
            return {
                "status": "success",
                "total_results": api_data.get("totalHits", 0),
                "foods": formatted_results[:10]
            }
            
    except Exception as e:
        print(f"❌ USDA API error: {str(e)}")
        return {"status": "error", "error": str(e)}

async def search_malaysian_foods(food_name):
    """Search Malaysian foods with detailed logging"""
    
    log_function_call("search_malaysian_foods", food_name=food_name)
    
    try:
        if not USDA_API_KEY:
            print("❌ No USDA API key available")
            return {"status": "error", "error": "No USDA API key"}
        
        start_time = time.time()
        
        # Malaysian food search logic
        malaysian_terms = ["malaysian", "asian", "southeast", "nasi", "rendang", "satay", "laksa"]
        search_query = f"{food_name} {' OR '.join(malaysian_terms)}"
        
        async with httpx.AsyncClient() as client:
            params = {
                "query": search_query,
                "dataType": "Foundation,SR Legacy",
                "pageSize": 20,
                "api_key": USDA_API_KEY
            }
            
            response = await client.get(f"{USDA_BASE_URL}/foods/search", params=params, timeout=15)
            
            usda_time = time.time() - start_time
            log_api_call("USDA Malaysian Search", f"{USDA_BASE_URL}/foods/search", response.status_code, usda_time)
            
            response.raise_for_status()
            api_data = response.json()
            
            print(f"   📊 Malaysian search returned {api_data.get('totalHits', 0)} results")
            
            malaysian_foods = []
            for food in api_data.get("foods", []):
                description = food.get("description", "").lower()
                
                if any(term in description for term in ["asian", "chinese", "malaysian", "thai", "indonesian"]):
                    nutrients = {}
                    for nutrient in food.get("foodNutrients", []):
                        name = nutrient.get("nutrientName", "").lower()
                        value = nutrient.get("value", 0)
                        unit = nutrient.get("unitName", "")
                        
                        if "energy" in name:
                            nutrients["calories"] = {"value": value, "unit": unit}
                        elif "protein" in name:
                            nutrients["protein"] = {"value": value, "unit": unit}
                        elif "carbohydrate" in name:
                            nutrients["carbs"] = {"value": value, "unit": unit}
                        elif "total lipid" in name:
                            nutrients["fat"] = {"value": value, "unit": unit}
                        elif "fiber" in name:
                            nutrients["fiber"] = {"value": value, "unit": unit}
                    
                    malaysian_foods.append({
                        "fdcId": food.get("fdcId"),
                        "description": food.get("description"),
                        "nutrients": nutrients,
                        "relevance": "asian_cuisine"
                    })
            
            return {
                "status": "success",
                "query": food_name,
                "malaysian_foods": malaysian_foods[:10],
                "note": "Results filtered for Asian/Malaysian cuisine"
            }
            
    except Exception as e:
        print(f"❌ Malaysian search error: {str(e)}")
        return {"status": "error", "error": str(e)}

def analyze_with_enhanced_gemini(base64_image):
    """Enhanced Gemini analysis with detailed logging"""
    
    log_function_call("analyze_with_enhanced_gemini", 
                     image_size=f"{len(base64_image)} characters")
    
    print("=== Enhanced Gemini Analysis Started ===")
    print("🔍 ANALYSIS FLOW:")
    print("   1. Gemini Vision API → Food identification")
    print("   2. USDA Database → Nutrition lookup")
    print("   3. Data enhancement → Combined results")
    
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
    
    # Enhanced prompt that instructs Gemini for better food identification
    prompt = """
    Analyze this food image and identify all visible food items. I have access to nutrition databases for accurate nutritional information.

    For each food item you identify:
    1. Provide the most specific food name possible (include preparation method, cooking style)
    2. Estimate the portion size based on visual cues (plates, utensils, reference objects)
    3. Note if it appears to be Malaysian/Southeast Asian cuisine
    4. Assess your confidence in the identification

    Return a JSON response with this structure:
    [
        {
            "name": "Specific food name (e.g., 'chicken fried rice' not just 'rice')",
            "estimated_weight_grams": your_visual_estimate,
            "confidence": confidence_score_0_to_1,
            "cuisine_type": "malaysian|western|asian|other",
            "preparation_method": "fried|steamed|grilled|raw|boiled|etc",
            "needs_nutrition_lookup": true,
            "visual_cues": "brief description of what you see"
        }
    ]

    Guidelines:
    - Be as specific as possible with food names
    - Include cooking methods and visible ingredients
    - For Malaysian foods: nasi lemak, rendang, laksa, satay, char kway teow, etc.
    - Estimate portion sizes using plate size, utensils, hand size as reference
    - Set needs_nutrition_lookup to true for database lookup
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
                
                # THIS IS WHERE NUTRITION ENHANCEMENT HAPPENS
                print("📡 STEP 2: Enhancing with nutrition database...")
                enhanced_results = asyncio.run(enhance_with_nutrition_data(initial_results))
                
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

async def enhance_with_nutrition_data(initial_results):
    """Enhanced nutrition data lookup with detailed logging"""
    
    log_function_call("enhance_with_nutrition_data", 
                     food_items=len(initial_results))
    
    print("🔍 NUTRITION ENHANCEMENT PROCESS:")
    enhanced_results = []
    
    for i, item in enumerate(initial_results, 1):
        food_name = item.get('name', '')
        estimated_weight = item.get('estimated_weight_grams', 100)
        cuisine_type = item.get('cuisine_type', 'other')
        
        print(f"\n📋 Processing food {i}/{len(initial_results)}: {food_name}")
        print(f"   🍽️ Cuisine type: {cuisine_type}")
        print(f"   ⚖️ Estimated weight: {estimated_weight}g")
        
        try:
            # Choose search strategy
            if cuisine_type == "malaysian" or cuisine_type == "asian":
                print("   🌏 Using Malaysian food search strategy")
                nutrition_data = await search_malaysian_foods(food_name)
                foods = nutrition_data.get('malaysian_foods', [])
                data_source = "USDA_Malaysian"
            else:
                print("   🌐 Using standard USDA search strategy")
                nutrition_data = await search_food_nutrition(food_name)
                foods = nutrition_data.get('foods', [])
                data_source = "USDA_Standard"
            
            if nutrition_data.get('status') == 'success' and foods:
                best_match = foods[0]
                print(f"   ✅ Database match found: {best_match.get('description', 'Unknown')}")
                print(f"   📊 Data source: {data_source}")
                
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
                        "carbs": round((nutrients.get('carbohydrates', {}).get('value', 0) or 
                                     nutrients.get('carbs', {}).get('value', 0)) * scaling_factor, 1),
                        "fat": round(nutrients.get('fat', {}).get('value', 0) * scaling_factor, 1),
                        "fiber": round(nutrients.get('fiber', {}).get('value', 0) * scaling_factor, 1)
                    },
                    "data_source": data_source,
                    "database_match": best_match.get('description', ''),
                    "fdc_id": best_match.get('fdcId'),
                    "cuisine_type": cuisine_type,
                    "preparation_method": item.get('preparation_method', 'unknown')
                })
                
            else:
                print(f"   ⚠️ No database match found, using fallback estimates")
                enhanced_results.append(create_fallback_item(item))
                
        except Exception as e:
            print(f"   ❌ Error processing {food_name}: {str(e)}")
            enhanced_results.append(create_fallback_item(item))
    
    print(f"\n✅ Enhancement complete: {len(enhanced_results)} items processed")
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
        "database_match": "No database match found",
        "cuisine_type": item.get('cuisine_type', 'unknown'),
        "preparation_method": item.get('preparation_method', 'unknown')
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
                if validate_enhanced_food_item(food):
                    validated_foods.append(food)
            
            return validated_foods if validated_foods else get_default_item()
        else:
            print("No JSON array found in response")
            return get_default_item()
            
    except json.JSONDecodeError as e:
        print(f"JSON parsing error: {str(e)}")
        return get_default_item()

def validate_enhanced_food_item(food):
    """Validate enhanced food item structure"""
    required_fields = ['name', 'estimated_weight_grams', 'confidence']
    
    for field in required_fields:
        if field not in food:
            return False
    
    # Set defaults for missing fields
    if 'cuisine_type' not in food:
        food['cuisine_type'] = 'other'
    if 'preparation_method' not in food:
        food['preparation_method'] = 'unknown'
    if 'needs_nutrition_lookup' not in food:
        food['needs_nutrition_lookup'] = True
    
    return True

def get_default_item():
    """Get default item when parsing fails"""
    return [{
        "name": "Unknown Food",
        "estimated_weight_grams": 100,
        "confidence": 0.3,
        "cuisine_type": "other",
        "preparation_method": "unknown",
        "needs_nutrition_lookup": True
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
        "debug_error": error_msg
    }]

# Firebase Functions entry point with both secrets
@https_fn.on_request(
    cors=options.CorsOptions(
        cors_origins=["*"],
        cors_methods=["POST", "GET", "OPTIONS"]
    ),
    memory=options.MemoryOption.GB_1,
    timeout_sec=90,
    secrets=["GEMINI_API_KEY", "USDA_API_KEY"]
)
def food_analyzer(req):
    with app.request_context(req.environ):
        return app.full_dispatch_request()