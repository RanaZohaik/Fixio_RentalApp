# Fixio Rental App 🛠️📱

Fixio is a comprehensive Flutter mobile application designed to simplify renting and sharing items, tools, equipment, electronics, and services. The platform connects item owners (vendors) with users looking to rent, offering built-in messaging, item management, earnings analytics, and administrative controls.

---

## 🌟 Key Features

### 👤 **User & Authentication**
- **Secure Authentication**: Email/Password authentication powered by Firebase Auth.
- **Role-Based Access**: Specialized interfaces for Renters, Vendors, and Administrators.
- **User Profiles**: Manage profile information, uploaded listings, and active rental requests.
- **Verification System**: ID and profile verification for trust and security.

### 🔍 **Item Discovery & Browsing**
- **Category Browsing**: Explore items by categories and sub-categories.
- **Real-Time Search**: Quickly find items with keyword search and category filtering.
- **Detailed Item Pages**: View item photos, descriptions, daily/hourly rates, vendor info, and location.

### 💼 **Vendor Portal**
- **List Items**: Easy item upload with photos, descriptions, pricing, and availability.
- **Manage Listings**: Edit or update existing product information and availability.
- **Earnings & Analytics**: Comprehensive dashboard to monitor earnings, views, and item performance.

### 💬 **Communication & Support**
- **In-App Messaging**: Direct chat between renters and vendors for inquiry and negotiation.
- **Voice Recognition Integration**: Built-in speech-to-text helper support.

### 🛡️ **Admin Dashboard**
- **System Overview**: Platform-wide statistics, active users, total listings, and transaction metrics.
- **Content Moderation**: Review user profiles, verify vendor requests, and manage active listings.

---

## 🛠️ Tech Stack & Dependencies

- **Framework**: [Flutter](https://flutter.dev/) (SDK ^3.10.0) & Dart
- **Backend & Database**: 
  - [Firebase Auth](https://pub.dev/packages/firebase_auth)
  - [Cloud Firestore](https://pub.dev/packages/cloud_firestore)
  - [Firebase Storage](https://pub.dev/packages/firebase_storage)
- **UI Components & Utilities**:
  - `google_fonts`, `carousel_slider`, `flutter_staggered_grid_view`, `cached_network_image`
  - `geolocator`, `image_picker`, `permission_handler`, `speech_to_text`
  - `shared_preferences`, `intl`, `http`, `url_launcher`

---

## 🚀 Getting Started

### Prerequisites

Ensure you have the following installed on your local development machine:
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`>= 3.10.0`)
- [Dart SDK](https://dart.dev/get-started/sdk)
- Android Studio / VS Code with Flutter plugins
- Xcode (if building for iOS)

### Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/rabia-amir001/Fixio-Rental-App.git
   cd Fixio-Rental-App
   ```

2. **Install Flutter packages**:
   ```bash
   flutter pub get
   ```

3. **Configure Firebase**:
   - Add your `google-services.json` file to `android/app/`
   - Add your `GoogleService-Info.plist` file to `ios/Runner/`

4. **Run the Application**:
   ```bash
   flutter run
   ```

---

## 📁 Project Structure

```
lib/
├── constants/         # App constants, colors, theme definitions
├── models/            # Data models (User, Category, Item, etc.)
├── routes/            # Application navigation and routes
├── screens/           # UI Screens categorized by feature
│   ├── admin/         # Admin dashboard and management screens
│   ├── auth/          # Login, Register, Forgot Password
│   ├── chat/          # Real-time messaging screens
│   ├── home/          # Browse, Home, Profile, Item Details
│   ├── vender/        # Vendor dashboard, Upload/Edit listings, Analytics
│   └── verification/  # User verification screens
├── services/          # Firebase & API service integration
├── utils/             # Helper utilities and validators
└── widgets/           # Reusable UI widgets
```

---

## 📄 License

This project is developed for Fixio Rental Application.
