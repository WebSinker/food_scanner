from firebase_functions import https_fn, options
from flask import Flask, request, jsonify
import base64
import json
import requests
import os
import re

app = Flask(__name__)

# Securely get Gemini API key from Firebase Secrets
GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY')
GEMINI_API_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent'

@app.route('/health', methods=['GET'])
def health_check():
    api_key_status = "configured" if GEMINI_API_KEY else "missing"
    
    return jsonify({
        'status': 'healthy', 
        'service': 'food-analyzer',
        'gemini_api_key': api_key_status,
        'security': 'secrets-based'  # Indicate we're using secure secrets
    })

@app.route('/analyze-food', methods=['POST'])
def analyze_food():
    try:
        print("=== Starting food analysis ===")
        
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
                }
            }]
            return jsonify({'success': True, 'foods': mock_results})
        
        # Check API key
        if not GEMINI_API_KEY:
            print("ERROR: No Gemini API key configured")
            return jsonify({
                'success': True,
                'foods': get_fallback_response("No API key configured")
            })
        
        print("API key loaded from secure secrets")
        print("Starting Gemini analysis...")
        
        # Analyze food with Gemini
        results = analyze_with_gemini(image_data)
        
        print(f"Analysis completed, found {len(results)} food items")
        
        return jsonify({
            'success': True,
            'foods': results
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
        return jsonify({'message': 'Food Analyzer API', 'endpoints': ['/health', '/analyze-food']})
    elif request.method == 'POST':
        return analyze_food()

def analyze_with_gemini(base64_image):
    """Analyze food image using Gemini Vision API"""
    
    print("=== Gemini Analysis Started ===")
    
    if not GEMINI_API_KEY:
        print("ERROR: No API key available")
        return get_fallback_response("No API key configured")
    
    # Validate base64 image
    try:
        # Try to decode to verify it's valid base64
        decoded = base64.b64decode(base64_image + '==')  # Add padding if needed
        print(f"Base64 image decoded successfully, size: {len(decoded)} bytes")
    except Exception as e:
        print(f"ERROR: Invalid base64 image: {str(e)}")
        return get_fallback_response("Invalid image format")
    
    prompt = """
    Analyze this food image and identify all visible food items. For each food item, provide detailed nutritional information.
    
    Return the response as a valid JSON array with this exact structure:
    [
        {
            "name": "Food name",
            "calories_per_100g": calories per 100 grams (number),
            "estimated_weight_grams": estimated weight of this food portion in grams (number),
            "total_calories": estimated total calories for the portion shown (number),
            "confidence": confidence score between 0.0 and 1.0 (number),
            "nutrients": {
                "protein": protein in grams (number),
                "carbs": carbohydrates in grams (number),
                "fat": fat in grams (number),
                "fiber": fiber in grams (number)
            }
        }
    ]
    
    Instructions:
    - Identify ALL visible food items separately
    - Estimate portion sizes based on visual cues (plates, utensils, common serving sizes)
    - Use standard USDA nutritional database values
    - Be realistic with portion size estimation
    - Confidence should reflect how clearly you can identify the food
    - Return ONLY the JSON array, no additional text
    - Ensure all numeric values are actual numbers, not strings
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
        print("Making request to Gemini API (using secure secrets)")
        
        response = requests.post(
            f"{GEMINI_API_URL}?key={GEMINI_API_KEY}",
            headers=headers_req,
            json=payload,
            timeout=30
        )
        
        print(f"Gemini API response status: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            print("Gemini API response received successfully")
            
            if 'candidates' in result and len(result['candidates']) > 0:
                text_response = result['candidates'][0]['content']['parts'][0]['text']
                print(f"Gemini response text (first 200 chars): {text_response[:200]}...")
                
                # Extract and parse JSON from response
                parsed_results = parse_gemini_response(text_response)
                print(f"Parsed {len(parsed_results)} food items from response")
                return parsed_results
            else:
                print("ERROR: No candidates in Gemini response")
                print(f"Full response: {result}")
                return get_fallback_response("No response from AI")
        else:
            error_text = response.text
            print(f"Gemini API error: {response.status_code} - {error_text}")
            
            # Check for specific API errors
            if response.status_code == 400:
                if "API key" in error_text:
                    return get_fallback_response("Invalid API key")
                elif "quota" in error_text.lower():
                    return get_fallback_response("API quota exceeded")
                else:
                    return get_fallback_response(f"API error: {response.status_code}")
            elif response.status_code == 403:
                return get_fallback_response("API access forbidden - check API key permissions")
            else:
                return get_fallback_response(f"API error: {response.status_code}")
            
    except requests.exceptions.Timeout:
        print("ERROR: Gemini API request timed out")
        return get_fallback_response("API request timed out")
    except requests.exceptions.ConnectionError:
        print("ERROR: Could not connect to Gemini API")
        return get_fallback_response("Cannot connect to AI service")
    except Exception as e:
        print(f"ERROR: Gemini request failed: {str(e)}")
        import traceback
        traceback.print_exc()
        return get_fallback_response(f"Request error: {str(e)}")

def parse_gemini_response(text_response):
    """Parse JSON response from Gemini"""
    try:
        print("=== Parsing Gemini Response ===")
        
        # Clean the response to extract JSON
        # Remove markdown code blocks if present
        cleaned_text = re.sub(r'```json\s*', '', text_response)
        cleaned_text = re.sub(r'```\s*$', '', cleaned_text)
        
        # Find JSON array boundaries
        json_start = cleaned_text.find('[')
        json_end = cleaned_text.rfind(']') + 1
        
        if json_start != -1 and json_end > json_start:
            json_str = cleaned_text[json_start:json_end]
            print(f"Extracted JSON: {json_str[:200]}...")
            
            foods = json.loads(json_str)
            print(f"Successfully parsed JSON with {len(foods)} items")
            
            # Validate and clean the response
            validated_foods = []
            for i, food in enumerate(foods):
                if validate_food_item(food):
                    validated_foods.append(food)
                    print(f"Food {i+1} validated: {food.get('name', 'Unknown')}")
                else:
                    print(f"Food {i+1} failed validation: {food}")
            
            if validated_foods:
                return validated_foods
            else:
                print("No valid food items found after validation")
                return get_fallback_response("No valid food items found")
        else:
            print("No JSON array found in response")
            print(f"Response text: {text_response}")
            return get_fallback_response("No JSON found in response")
            
    except json.JSONDecodeError as e:
        print(f"JSON parsing error: {str(e)}")
        print(f"Failed to parse: {text_response}")
        return get_fallback_response(f"JSON parsing error")

def validate_food_item(food):
    """Validate that food item has required fields with correct types"""
    required_fields = ['name', 'calories_per_100g', 'estimated_weight_grams', 'total_calories', 'confidence']
    
    for field in required_fields:
        if field not in food:
            print(f"Missing field: {field}")
            return False
        if field != 'name' and not isinstance(food[field], (int, float)):
            print(f"Invalid type for {field}: {type(food[field])}")
            return False
    
    if 'nutrients' in food:
        nutrient_fields = ['protein', 'carbs', 'fat', 'fiber']
        for nutrient in nutrient_fields:
            if nutrient in food['nutrients'] and not isinstance(food['nutrients'][nutrient], (int, float)):
                print(f"Invalid nutrient type for {nutrient}: {type(food['nutrients'][nutrient])}")
                return False
    
    return True

def get_fallback_response(error_msg="Analysis failed"):
    """Fallback response when Gemini analysis fails"""
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
        "debug_error": error_msg
    }]

# Firebase Functions entry point with secret binding
@https_fn.on_request(
    cors=options.CorsOptions(
        cors_origins=["*"],
        cors_methods=["POST", "GET", "OPTIONS"]
    ),
    memory=options.MemoryOption.GB_1,
    timeout_sec=60,
    secrets=["GEMINI_API_KEY"]  # Bind the secret to this function
)
def food_analyzer(req):
    with app.request_context(req.environ):
        return app.full_dispatch_request()