import Foundation
import PostHog

/// Product analytics through PostHog Cloud (TT-208, D92): anonymous events only. No identify and no person profiles, no
/// session replay, no autocapture and no swizzled screen views (SwiftUI screens are named by `Analytics.screen`). The
/// SDK's lifecycle events (Application Installed, Updated, Opened, Backgrounded) stay on. Started only in Release builds
/// (TestFlight and the App Store) whose `POSTHOG_PROJECT_TOKEN` is set; Debug builds, previews and tests send nothing.
@MainActor
final class PostHogAnalytics: AnalyticsTracking {
    static let tokenKey = "TTPostHogToken"

    /// The tracker for this launch, or nil when this build sends no analytics.
    static func start(bundle: Bundle = .main) -> PostHogAnalytics? {
        #if DEBUG
        return nil
        #else
        guard let token = bundle.object(forInfoDictionaryKey: tokenKey) as? String,
              !token.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        let config = PostHogConfig(projectToken: token, host: PostHogConfig.defaultHost)
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.enableSwizzling = false
        config.sessionReplay = false
        config.personProfiles = .never
        // Feature flags come with A/B tests (TT-211).
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register(["channel": BuildChannel.isTestFlight ? "testflight" : "appstore"])
        return PostHogAnalytics()
        #endif
    }

    func track(_ event: AnalyticsEvent) {
        PostHogSDK.shared.capture(event.name, properties: event.properties.mapValues(\.raw))
    }

    func screen(_ screen: AnalyticsScreen) {
        PostHogSDK.shared.screen(screen.rawValue)
    }
}
