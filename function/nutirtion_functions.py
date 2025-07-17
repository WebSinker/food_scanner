# nutrition_functions.py - Add this to your Firebase Functions

from firebase_functions import https_fn, options
from flask import Flask, request, jsonify
import httpx
import asyncio
import os

app = Flask(__name__)

# USDA API Configuration
USDA_API_KEY = os.environ.get('USDA_API_KEY')
USDA_BASE_URL = "https://api.nal.usda.gov/fdc/v1"

@app.route('/search-food-nutrition', methods=['POST'])
async def search_food_nutrition_endpoint():
    """HTTP endpoint wrapper for USDA food nutrition search"""
    try:
        data = request.get_json()
        food_name = data.get('food_name')
        data_type = data.get('data_type', 'Foundation,SR Legacy')
        page_size = data.get('page_size', 25)
        
        if not food_name:
            return jsonify({'error': 'food_name is required'}), 400
        
        # Your existing search_food_nutrition logic here
        async with httpx.AsyncClient() as client:
            params = {
                "query": food_name,
                "dataType": data_type,
                "pageSize": page_size,
                "sortBy": "dataType.keyword",
                "sortOrder": "asc",
                "api_key": USDA_API_KEY
            }
            
            response = await client.get(f"{USDA_BASE_URL}/foods/search", params=params)
            response.raise_for_status()
            
            api_data = response.json()
            
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
            
            return jsonify({
                "status": "success",
                "total_results": api_data.get("totalHits", 0),
                "foods": formatted_results[:10]
            })
            
    except Exception as e:
        return jsonify({
            "status": "error",
            "error": str(e),
            "message": "Failed to fetch nutrition data"
        }), 500

@app.route('/search-malaysian-foods', methods=['POST'])
async def search_malaysian_foods_endpoint():
    """HTTP endpoint for Malaysian food search"""
    try:
        data = request.get_json()
        food_name = data.get('food_name')
        
        if not food_name:
            return jsonify({'error': 'food_name is required'}), 400
        
        # Malaysian food search logic here
        malaysian_terms = ["malaysian", "asian", "southeast", "nasi", "rendang", "satay", "laksa"]
        search_query = f"{food_name} {' OR '.join(malaysian_terms)}"
        
        async with httpx.AsyncClient() as client:
            params = {
                "query": search_query,
                "dataType": "Foundation,SR Legacy",
                "pageSize": 20,
                "api_key": USDA_API_KEY
            }
            
            response = await client.get(f"{USDA_BASE_URL}/foods/search", params=params)
            response.raise_for_status()
            
            api_data = response.json()
            
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
            
            return jsonify({
                "status": "success",
                "query": food_name,
                "malaysian_foods": malaysian_foods[:10],
                "note": "Results filtered for Asian/Malaysian cuisine"
            })
            
    except Exception as e:
        return jsonify({
            "status": "error",
            "error": str(e),
            "message": "Failed to search Malaysian foods"
        }), 500

# Firebase Function entry points
@https_fn.on_request(
    cors=options.CorsOptions(
        cors_origins=["*"],
        cors_methods=["POST", "GET", "OPTIONS"]
    ),
    memory=options.MemoryOption.GB_1,
    timeout_sec=60,
    secrets=["USDA_API_KEY"]
)
def nutrition_search(req):
    """Firebase Function for nutrition search"""
    with app.request_context(req.environ):
        return app.full_dispatch_request()

@https_fn.on_request(
    cors=options.CorsOptions(
        cors_origins=["*"],
        cors_methods=["POST", "GET", "OPTIONS"]
    ),
    memory=options.MemoryOption.GB_1,
    timeout_sec=60,
    secrets=["USDA_API_KEY"]
)
def malaysian_food_search(req):
    """Firebase Function for Malaysian food search"""
    with app.request_context(req.environ):
        return app.full_dispatch_request()