# Native Swift Autocomplete App - Detailed Technical Specification

## Overview
A native Swift macOS application that provides VS Code-style text autocomplete across all text input fields system-wide. Works in web browsers, WhatsApp, Messages, and any app with text inputs. Supports local LLM inference (primary) and optional online LLMs (user-provided API keys). Automatically disables in coding editors (VS Code, Xcode, etc.) and browser URL bars.

## Core Features
- System-wide autocomplete for all text input fields (excluding blacklisted apps)
- Local LLM inference with optional online LLM support
- User personalization through fine-tuning
- Universal autocomplete style (consistent across all apps)
- Smart continuation for race conditions
- Multilingual support
- Full accessibility support (VoiceOver, Switch Control)

---

## Technical Architecture

### System Integration
- **Accessibility API + CGEvent Hybrid**: Use AX API to read text context and CGEvent for suggestion display/injection
- **Accessibility Roles**: Detect URL bars and secure fields via AX role identification
- **No Sandboxing**: Distributed outside App Store for full system access
- **Combination Fallback**: Text insertion via AXValue set first, fall back to CGEvent typing

### Model & Inference
- **Model Format**: CoreML (.mlmodel) - native Apple format, optimized for Apple Silicon
- **Model Size**: Small (1-3B parameters) - good balance of quality and performance
- **Quantization**: Adaptive based on available memory and Mac specs
  - Medium (Q8_0) when memory available
  - Low (Q4_K_M) when constrained
- **Threading**: GPU-accelerated only - offload all inference to GPU, no CPU threads
- **Memory Management**: Dynamic limit based on free system RAM
- **Model Loading**: Timeout-based unload - load when needed, unload after inactivity

### Text Processing
- **Context Window**: Dynamic adaptive window - expands based on punctuation and sentence structure
- **Debounce Time**: Short (150ms) - balanced for fast typers
- **Token Generation**: Dynamic - generate until confidence drops or stop token reached
- **Prompt Engineering**: Adaptive prompting - changes based on content type
- **Latency Target**: 100-300ms

---

## User Interface & Experience

### Suggestion Display
- **Visual Style**: Inline preview shown in greyed-out floating overlay positioned over text field
- **Floating Overlay**: Follows active window across multiple monitors/screen spaces
- **Single Suggestion**: Always show top match regardless of confidence score
- **Preview Rendering**: Floating overlay window matching field's font/styling

### User Interactions
- **Accept/Reject**: Tab/Enter to accept, Esc to dismiss (hardcoded shortcuts)
- **Cursor Behavior**: Force cursor to end of suggestion after insertion
- **Paste Behavior**: Accepted suggestions inserted as clipboard paste (separate undo action)
- **Smart Continuation**: Hybrid approach - prefix check first, re-compute if uncertain
- **Race Conditions**: Smart continuation maintains suggestion relevance during typing

### Controls & Settings
- **Menu Bar Toggle**: Quick enable/disable from menu bar icon
- **Performance Metrics**: Menu bar icon showing status indicator, click for details
- **App Exclusions**: Granular combination - app + window type + content rules
- **Code Toggle**: Combination of per-app settings + hotkey + intelligent behavior
- **Battery Handling**: User preference - let user decide behavior on low battery
- **Hotkey Override**: Global hotkey for quick enable/disable while typing

---

## Code Detection & Filtering

### Detection Approach
- **Combination Method**: App blacklist + pattern detection + manual toggle
- **Code Patterns**: File extension detection (.py, .js, .cpp, etc.)
- **App Blacklist**: VS Code, Xcode, other coding IDEs (configurable)
- **Browser URL Bars**: Detected via accessibility role, auto-disabled

### Smart Adaptation
- **App Switching**: Smart adaptive - reset if unrelated apps, maintain if same document type
- **Per-App Context**: Maintain separate context for each app, adapt based on document type
- **Manual Override**: Users can manually enable/disable specific apps

---

## Privacy & Data Handling

### Privacy Strategy
- **Local-First Only**: Never send data externally, all processing happens on-device
- **Training Data Collection**: Mix of user personal data and instruction tuning
  - PII filtering to strip emails, phone numbers, credit cards
  - Explicit whitelist - only train from user-selected text/app categories
  - Encrypted local storage

### Data Storage
- **Location**: App container (~/Library/Containers/app)
- **Export**: Export with encryption - users can export models, password-protected
- **Training Data**: Never export user data unencrypted
- **Crash Recovery**: Minimal state save - save basic preferences, lose session data

### Sensitive Fields
- **Password Fields**: Auto-disable on secure fields
- **Secure Input**: Detect secure role and disable autocomplete
- **No training data persistence from secure fields**

---

## Learning & Personalization

### Fine-Tuning Strategy
- **Approach**: Mix of user personal data + instruction tuning
- **Update Frequency**: Incremental updates - real-time adaptation to user preferences
- **Training Trigger**: Real-time - update model immediately after each interaction
- **Dataset**: General diverse text + user's personal typing patterns over time
- **Model Updates**: Prompt user before updating base models

### Personalization Scope
- **Style**: Universal autocomplete style (consistent across apps)
- **Content**: Adapts to user's writing patterns, not app-specific
- **Privacy**: All learning happens locally, no cloud transmission

---

## Model Management

### Base Model
- **Initial Download**: Auto-download on first run
- **Update Strategy**: Prompt user before updating to new versions
- **Version Pinning**: Users can choose which version to use
- **Multilingual**: Multilingual model supporting multiple languages

### Model Lifecycle
- **Loading**: Timeout-based - load when needed, unload after inactivity
- **Memory**: Dynamic based on free system RAM
- **Error Handling**: Graceful degradation - log error, continue without suggestions, notify user

### Fine-Tuned Models
- **Storage**: App container, sandboxed
- **Encryption**: Store encrypted, only decrypt during training
- **Export**: Export with password encryption enabled

---

## Performance & Optimization

### Latency Targets
- **Target**: 100-300ms from typing pause to suggestion appearance
- **Debounce**: 150ms wait before triggering inference
- **Token Generation**: Dynamic length based on content
- **Inference**: GPU-accelerated, minimal CPU usage

### Resource Management
- **Memory**: Dynamic based on available RAM
- **Model Unload**: Timeout-based after inactivity
- **Battery**: User-configurable behavior
- **Threading**: GPU-accelerated only

### Performance Optimization
- **Quantization**: Adaptive (medium/low) based on system specs
- **Context Window**: Dynamic adaptive to balance speed/accuracy
- **Single Suggestion**: Minimize compute by generating one completion

---

## Accessibility & Compatibility

### Accessibility Features
- **Full VoiceOver Support**: Suggestions fully announced and navigable
- **Switch Control**: Full support for alternative input methods
- **Screen Reader Integration**: Suggestions announced as they appear

### Multi-Monitor
- **Floating Overlay**: Follows active window across monitors
- **Screen Spaces**: Maintains position in each space

### IME Integration
- **IME-Aware Suggestions**: Provide suggestions within IME composition
- **Multi-Language**: Multilingual model supports various input methods
- **Language Detection**: Model handles multiple languages natively

### Auto-Correction
- **Before Autocorrect**: Show suggestions before macOS applies corrections
- **System Integration**: Works alongside macOS native features

---

## Error Handling & Edge Cases

### Inference Errors
- **OOM**: Graceful degradation, notify user
- **Timeout**: Fall back to smaller model or fewer tokens
- **Corruption**: Show notification, disable until model repaired
- **Graceful Degradation**: Always continue without suggestions, never crash

### Text Injection Failures
- **AXValue Failed**: Fall back to CGEvent typing
- **CGEvent Failed**: Show error notification
- **Context Lost**: Re-read context and retry

### Conflicts
- **IME Active**: Provide IME-aware suggestions
- **Keyboard Shortcuts**: Hardcoded shortcuts (Tab/Esc), conflicts go to app first
- **Multiple Input Methods**: Work alongside, don't block other input methods

---

## Distribution & Monetization

### Distribution
- **Method**: Direct download only (no App Store)
- **Format**: Unsigned binaries, users must trust manually
- **Platform**: GitHub releases or website hosting

### Pricing
- **Model**: Paid only (one-time purchase or subscription)
- **Beta Testing**: GitHub issues only for feedback
- **Support**: Direct support channels

### Branding
- **Name Direction**: Mac-native sounding names
- **Style**: Fits Apple ecosystem design language

---

## Development Scope

### MVP Scope
- **Approach**: Full features from day one
- **Timeline**: Solo developer
- **Phases**: No strict timeline, research/exploration focused

### Technical Concerns
- **Primary Concern**: System integration reliability across all apps
- **Secondary**: Performance (100-300ms latency)
- **Tertiary**: Model quality with small local models

---

## Settings & Preferences

### User Configurable
- **Battery Handling**: User decides behavior on low battery
- **App Exclusions**: Granular per-app + window + content rules
- **Model Selection**: Choose between available models/quantizations
- **Settings Sync**: Selective sync - user chooses which settings to sync
- **Training Data**: User controls what apps/categories to train from

### Stored Preferences
- **Location**: App container
- **Sync**: Selective iCloud sync across devices
- **Export**: Settings exportable for backup

---

## Onboarding Experience

### First Launch
- **Style**: Minimal setup - quick download, brief explanation, ready to go
- **Process**: 
  1. Auto-download model on first run
  2. Brief explanation of features
  3. Accessibility permissions request
  4. Ready to use

### User Education
- **Progressive Reveal**: Basic mode first, advanced features revealed over time
- **In-App Tips**: Contextual hints as user interacts
- **Documentation**: Comprehensive online docs

---

## Security Considerations

### Permissions
- **Accessibility**: Explicit user permission required
- **No Root Privileges**: Works with standard user permissions
- **Sandbox**: No sandbox for full system access

### Data Protection
- **All Processing Local**: Never sends data externally
- **Encrypted Storage**: Training data and models encrypted
- **PII Filtering**: Automatically strips sensitive information
- **Secure Fields**: Auto-detects and excludes password/security fields

---

## API & Online LLM Support (Future)

### Architecture
- **User-Provided Keys**: Users bring their own API keys
- **Quotas**: Daily/monthly quotas with warnings when approaching
- **Usage Tracking**: Track API calls and warn about limits
- **Optional Feature**: Not required for core functionality

### Configuration
- **Provider Selection**: Support multiple providers (OpenAI, Anthropic, etc.)
- **Model Selection**: User chooses which model to use
- **Fallback**: Local-first, online as optional enhancement

---

## Telemetry & Analytics

### Data Collection
- **Policy**: Opt-in anonymous only
- **Scope**: Non-identifiable metrics (suggestion acceptance rate, latency, errors)
- **Storage**: Local analytics with option to share

### Privacy
- **Default**: No telemetry
- **User Control**: Explicit opt-in required
- **No PII**: Never collect personally identifiable information

---

## Technology Stack

### Native Components
- **Language**: Swift
- **UI**: SwiftUI + AppKit (as needed)
- **ML**: CoreML
- **Concurrency**: Swift structured concurrency
- **Accessibility**: Accessibility API
- **Input Monitoring**: CGEvent tap

### ML Runtime
- **Primary**: CoreML framework
- **Format**: .mlmodel files
- **Accelerators**: Apple Neural Engine (ANE), GPU

### System APIs
- **Accessibility**: AXUIElement, AXValue
- **Window Management**: NSWindow, NSWorkspace
- **Input Monitoring**: CGEventTap
- **Process Monitoring**: NSRunningApplication

---

## Future Enhancements (Post-MVP)

### Potential Features
- Advanced training data visualization
- Community model sharing (encrypted)
- Integration with more ML frameworks
- Cloud sync for personalized models
- Advanced code detection heuristics
- Custom prompt engineering per content type
- Team/enterprise features

### Research Areas
- Better context understanding
- Improved code detection
- Enhanced IME integration
- Performance optimizations
- Smarter continuation algorithms

---

## Appendix: Key Design Decisions Summary

### Why Local-First?
- Privacy: No data leaves user's device
- Reliability: Works without internet
- Control: User owns their data and models

### Why CoreML?
- Performance: Native optimization for Apple Silicon
- Ecosystem: First-class Apple framework support
- Efficiency: Best GPU/ANE utilization

### Why No Sandbox?
- Functionality: Full system access required for reliable text interception
- Distribution: Direct download avoids App Store limitations
- Control: Complete control over app behavior

### Why Hybrid AX+CGEvent?
- Reliability: AX for reading, CGEvent for writing/injection
- Permissions: Both have established permission models
- Fallback: If one fails, other may work

### Why Single Suggestion?
- Performance: Minimize compute overhead
- UX: Faster latency, less cognitive load
- Simplicity: Cleaner UI, less distraction

### Why Dynamic Context?
- Accuracy: More context = better suggestions
- Efficiency: Don't waste resources on unnecessary context
- Adaptability: Different content needs different context lengths

---

## Success Criteria

### Technical Metrics
- **Latency**: <300ms average suggestion time
- **Accuracy**: >70% suggestion acceptance rate
- **Performance**: <10% CPU usage when idle
- **Memory**: <2GB memory footprint with model loaded
- **Crash Rate**: <0.1% sessions crash

### User Experience Metrics
- **Setup Time**: <5 minutes from download to working
- **Learning Curve**: <1 hour to comfortable usage
- **Satisfaction**: >4/5 user rating
- **Adoption**: Suggestions accepted >50% of time after first week

### Business Metrics
- **Revenue**: Sustainable pricing model
- **Support**: <24 hour response time for issues
- **Growth**: Organic user growth through word-of-mouth
