# 🍽️ AI Food Calorie Scanner

A Flutter mobile app that uses AI to analyze food images and provide accurate nutritional information. Simply take a photo of your food, and get instant calorie counts, macronutrient breakdowns, and portion analysis powered by Google's Gemini AI and USDA nutritional databases.

## 📱 Features

### 🔍 **AI-Powered Food Recognition**
- **Smart Food Identification**: Uses Gemini 2.0 Flash to identify multiple food items in a single image
- **Portion Size Estimation**: Estimates weight and serving sizes based on visual cues
- **Confidence Scoring**: Shows how confident the AI is in its food identification
- **Malaysian Cuisine Support**: Enhanced recognition for Southeast Asian foods

### 📊 **Accurate Nutritional Analysis**
- **USDA Database Integration**: Real nutritional data from official USDA FoodData Central
- **Comprehensive Macros**: Protein, carbohydrates, fat, and fiber content
- **Calorie Calculation**: Precise calorie counts based on actual portion sizes
- **Adjustable Portions**: Slider to fine-tune portion sizes and see real-time nutrition updates

### 💾 **Data Management**
- **Firebase Backend**: Secure cloud storage for all scan history
- **Scan History**: View all previous food scans with timestamps
- **Daily Summaries**: Track daily calorie intake and nutrition patterns
- **Data Export**: Access to detailed nutritional breakdowns

### 🎨 **User Experience**
- **Material Design 3**: Modern, intuitive interface
- **Camera & Gallery**: Take photos or select from existing images
- **Real-time Updates**: Instant nutrition recalculation as you adjust portions
- **Progress Indicators**: Clear feedback during AI analysis
- **Error Handling**: Graceful fallbacks when services are unavailable

## 🏗️ Architecture

### **Frontend (Flutter)**
- **Language**: Dart
- **Framework**: Flutter 3.x
- **State Management**: StatefulWidget with setState
- **UI**: Material Design 3 with custom theming
- **Image Handling**: image_picker package
- **HTTP Client**: http package for API calls

### **Backend (Firebase Functions)**
- **Runtime**: Python 3.11
- **Framework**: Flask
- **AI Service**: Google Gemini 2.0 Flash API
- **Database**: Cloud Firestore
- **Authentication**: Firebase Anonymous Auth
- **Hosting**: Firebase Functions (Serverless)

### **Nutrition Services**
- **Primary Database**: USDA FoodData Central API
- **Secondary Sources**: Open Food Facts (for branded items)
- **Regional Support**: Enhanced Malaysian/Asian food database
- **Data Processing**: Real-time nutritional calculations

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (3.0+)
- Firebase Account
- Google Cloud Platform Account
- USDA FoodData Central API Key
- Gemini API Key

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/ai-food-calorie-scanner.git
   cd ai-food-calorie-scanner
   ```

2. **Install Flutter dependencies**
   ```bash
   flutter pub get
   ```

3. **Firebase Setup**
   ```bash
   # Install Firebase CLI
   npm install -g firebase-tools
   
   # Login to Firebase
   firebase login
   
   # Initialize Firebase project
   firebase init
   ```

4. **Configure API Keys**
   ```bash
   # Set Gemini API Key
   firebase functions:secrets:set GEMINI_API_KEY
   
   # Set USDA API Key
   firebase functions:secrets:set USDA_API_KEY
   ```

5. **Deploy Firebase Functions**
   ```bash
   cd functions
   firebase deploy --only functions
   ```

6. **Update Firebase Configuration**
   - Replace `firebase_options.dart` with your project configuration
   - Update function URLs in `main.dart`

7. **Run the app**
   ```bash
   flutter run
   ```

## 🔑 API Keys Setup

### Gemini API Key
1. Go to [Google AI Studio](https://makersuite.google.com/app/apikey)
2. Create a new API key
3. Add to Firebase secrets: `firebase functions:secrets:set GEMINI_API_KEY`

### USDA API Key
1. Visit [USDA FoodData Central](https://fdc.nal.usda.gov/api-guide.html)
2. Sign up for a free API key
3. Add to Firebase secrets: `firebase functions:secrets:set USDA_API_KEY`

## 📁 Project Structure

```
ai-food-calorie-scanner/
├── lib/
│   ├── main.dart                 # Main app entry point
│   ├── models/
│   │   └── food_models.dart      # Data models
│   └── services/
│       └── firebase_service.dart # Firebase integration
├── functions/
│   ├── main.py                   # Gemini AI analysis
│   ├── nutrition_functions.py    # USDA nutrition lookup
│   └── requirements.txt          # Python dependencies
├── android/                      # Android-specific code
├── ios/                         # iOS-specific code
├── firebase.json                # Firebase configuration
└── pubspec.yaml                 # Flutter dependencies
```

## 🔧 Configuration

### Firebase Functions Environment
```python
# functions/main.py
FIREBASE_FUNCTION_URL = 'https://us-central1-your-project.cloudfunctions.net/food_analyzer'
```

### Flutter App Configuration
```dart
// lib/main.dart
static const String FIREBASE_FUNCTION_URL = 
    'https://us-central1-your-project.cloudfunctions.net/food_analyzer/analyze-food';
```

## 📊 Usage

### Taking a Food Photo
1. Open the app
2. Choose "Camera" or "Gallery"
3. Take/select a photo of your food
4. Tap "Analyze Food"
5. Wait for AI analysis (15-30 seconds)
6. Review and adjust portion sizes
7. Save the scan to your history

### Viewing Nutrition Data
- **Macronutrients**: Protein, carbs, fat, fiber
- **Calories**: Per 100g and total for portion
- **Confidence Score**: AI confidence in food identification
- **Data Source**: USDA database reference

### Managing History
- **View All Scans**: Access complete scan history
- **Daily Summaries**: See daily calorie totals
- **Delete Scans**: Remove unwanted entries
- **Export Data**: Access detailed nutritional information

## 🛠️ Development

### Local Development
```bash
# Run with hot reload
flutter run

# Run Firebase emulators
firebase emulators:start

# Test specific functions
firebase functions:shell
```

### Testing
```bash
# Run Flutter tests
flutter test

# Test Firebase functions locally
cd functions && python -m pytest
```

### Deployment
```bash
# Deploy functions only
firebase deploy --only functions

# Deploy hosting (if configured)
firebase deploy --only hosting

# Deploy everything
firebase deploy
```

## 📈 Performance

- **Analysis Time**: 15-30 seconds per image
- **Accuracy**: 80-95% for common foods
- **Database Coverage**: 400,000+ food items
- **Offline Support**: Limited (cached data only)
- **Image Size**: Optimized to 1024x1024px

## 🔒 Privacy & Security

- **Anonymous Authentication**: No personal data required
- **Data Encryption**: All data encrypted in transit and at rest
- **Image Processing**: Images processed server-side, not stored permanently
- **GDPR Compliant**: Data deletion and export available
- **Firebase Security Rules**: Proper access controls implemented

## 🌍 Localization

- **Primary**: English
- **Regional Support**: Malaysian/Southeast Asian cuisine
- **Measurements**: Metric system (grams, kilograms)
- **Currency**: Not applicable
- **Time Zones**: Local device timezone

## 🚧 Known Issues

- **Complex Mixed Dishes**: May struggle with heavily mixed foods
- **Liquid Foods**: Limited support for soups and beverages
- **Very Small Portions**: Minimum ~10g for accurate analysis
- **Poor Lighting**: Image quality affects accuracy
- **Network Dependency**: Requires internet connection

## 🎯 Roadmap

### Version 2.0
- [ ] Barcode scanning for packaged foods
- [ ] Meal planning integration
- [ ] Nutrition goal tracking
- [ ] Social sharing features
- [ ] Offline mode improvements

### Version 2.1
- [ ] Recipe analysis
- [ ] Restaurant menu integration
- [ ] Dietary restriction alerts
- [ ] Advanced analytics dashboard
- [ ] Multi-language support

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

### Code Style
- **Flutter**: Follow [Dart style guide](https://dart.dev/guides/language/effective-dart/style)
- **Python**: Follow [PEP 8](https://www.python.org/dev/peps/pep-0008/)
- **Commits**: Use [Conventional Commits](https://www.conventionalcommits.org/)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Google Gemini**: For powerful AI vision capabilities
- **USDA FoodData Central**: For comprehensive nutrition database
- **Firebase**: For reliable backend infrastructure
- **Flutter**: For cross-platform mobile development
- **Open Food Facts**: For branded food database

## 📞 Support

- **Email**: support@yourapp.com
- **GitHub Issues**: [Report bugs](https://github.com/yourusername/ai-food-calorie-scanner/issues)
- **Documentation**: [Wiki](https://github.com/yourusername/ai-food-calorie-scanner/wiki)
- **Community**: [Discord](https://discord.gg/yourserver)

## 📊 Stats

![GitHub stars](https://img.shields.io/github/stars/yourusername/ai-food-calorie-scanner)
![GitHub forks](https://img.shields.io/github/forks/yourusername/ai-food-calorie-scanner)
![GitHub issues](https://img.shields.io/github/issues/yourusername/ai-food-calorie-scanner)
![GitHub license](https://img.shields.io/github/license/yourusername/ai-food-calorie-scanner)
![Flutter version](https://img.shields.io/badge/Flutter-3.0+-blue)
![Firebase](https://img.shields.io/badge/Firebase-9.0+-orange)

---

**Built with ❤️ in Malaysia** 🇲🇾

*Making nutrition tracking accessible and accurate for everyone*