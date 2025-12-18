# AI Coding Agent Instructions for `thpitze_main`

## Project Overview
`thpitze_main` is a Flutter project structured for modularity and scalability. The project is organized into distinct layers to separate concerns and facilitate future development.

### Key Components
- **`lib/app`**: Contains the main application entry point (`ThpitzeApp`). This is where the app's UI and navigation are initialized.
- **`lib/core`**: Reserved for core application services. UI components should not directly depend on this layer.
- **`lib/plugins`**: Placeholder for plugin registration and discovery. This layer is intended for integrating external or internal plugins.

### Testing
- Tests are located in the `test` directory.
- Example: `test/widget_test.dart` contains a basic widget test for a counter app.
- Use `flutter test` to run all tests.

### Developer Workflows
#### Building and Running
- Use standard Flutter commands:
  - `flutter run` to run the app.
  - `flutter build <platform>` to build for a specific platform (e.g., `flutter build apk`).

#### Testing
- Run all tests with:
  ```bash
  flutter test
  ```

### Project-Specific Conventions
- **Modularity**: The project is structured to separate concerns:
  - `core` for backend logic.
  - `plugins` for extensibility.
  - `app` for UI and navigation.
- **Stateless Widgets**: The app uses `StatelessWidget` for simplicity in `ThpitzeApp`.

### Integration Points
- Currently, no external dependencies or integrations are defined.
- Future plugins or services should be added to the `plugins` or `core` layers as appropriate.

### Examples
#### Adding a New Feature
1. Define core logic in `lib/core`.
2. If the feature requires external dependencies, register them in `lib/plugins`.
3. Add UI components in `lib/app`.

#### Writing Tests
- Place tests in the `test` directory.
- Use `WidgetTester` for widget-specific tests.

---

This document will evolve as the project grows. Update it to reflect new conventions, workflows, or architectural decisions.