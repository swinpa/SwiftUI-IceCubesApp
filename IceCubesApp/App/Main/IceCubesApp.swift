import Account
import AppAccount
import AVFoundation
import DesignSystem
import Env
import KeychainSwift
import MediaUI
import Network
import RevenueCat
import StatusKit
import SwiftUI
import Timeline
import WishKit

@main
struct IceCubesApp: App {
    /*
     在 SwiftUI 中处理应用的生命周期事件和窗口状态时，AppDelegate 和 SceneDelegate 的角色被整合到 SwiftUI 的应用结构中。尽管 SwiftUI 主要使用 @main 入口点和 App 协议来管理应用生命周期，仍然可以通过 SwiftUI 的 App 结构和 UIApplicationDelegateAdaptor 适配器来集成传统的 AppDelegate 方法。
     */
  @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    /*
     使用 @Environment 属性包装器来监视应用的生命周期状态变化，如活跃、非活跃和后台状态。
     你只需要声明这个属性。系统会自动将当前场景的状态注入到你的视图中
     
     当你在 SwiftUI 视图中声明 @Environment(\.scenePhase) private var scenePhase 时，你是在告诉 SwiftUI 你希望能够访问当前场景的生命周期状态。@Environment 属性包装器允许你读取和响应 SwiftUI 环境中的值。
     */
    
    /*
     @Environment(\.scenePhase) 的工作原理
     1. 声明环境变量:
     当你在 SwiftUI 视图中声明 @Environment(\.scenePhase) private var scenePhase 时，你是在告诉 SwiftUI 你希望能够访问当前场景的生命周期状态。@Environment 属性包装器允许你读取和响应 SwiftUI 环境中的值。
     
     2. 自动注入值:
     SwiftUI 会自动注入当前场景的状态到你的视图中。scenePhase 是一个 ScenePhase 类型的值，表示应用当前的状态。SwiftUI 会在视图生命周期中自动更新这个值。
     3. 响应状态变化:
     你可以使用 onChange(of:perform:) 修饰符来响应 scenePhase 的变化。这使得你可以根据应用的状态变化执行特定的操作，例如在应用进入后台时保存数据，或在应用变为活跃时刷新界面。
     4. 环境更新:
     当场景的状态发生变化（如应用从后台恢复到前台），SwiftUI 会自动更新 scenePhase 的值，并触发视图的重新评估。你的视图会根据新的 scenePhase 值来执行相应的操作。
     */
  @Environment(\.scenePhase) var scenePhase
  @Environment(\.openWindow) var openWindow

  @State var appAccountsManager = AppAccountsManager.shared
  @State var currentInstance = CurrentInstance.shared
  @State var currentAccount = CurrentAccount.shared
  @State var userPreferences = UserPreferences.shared
  @State var pushNotificationsService = PushNotificationsService.shared
  @State var appIntentService = AppIntentService.shared
  @State var watcher = StreamWatcher.shared
  @State var quickLook = QuickLook.shared
  @State var theme = Theme.shared

  @State var selectedTab: Tab = .timeline
  @State var appRouterPath = RouterPath()

  @State var isSupporter: Bool = false

    /*
     应用入口，全局有且只有一个Scene类型的body
     当有其他Scene类型的属性时，如果属性内部由多个scene组成，那么该属性需要使用
     @SceneBuilder修饰，如otherScenes
     otherScenes中由两个WindowGroup组成
     appScene则只有一个WindowGroup，所以不需要 @SceneBuilder组成
     */
  var body: some Scene {
    appScene
    otherScenes
  }

  func setNewClientsInEnv(client: Client) {
    currentAccount.setClient(client: client)
    currentInstance.setClient(client: client)
    userPreferences.setClient(client: client)
    /*
     在 Swift 中，Task 是用于处理并发操作的一个重要结构，特别是在使用 Swift 的异步/等待（async/await）编程模型时。Task 的作用主要是管理和执行异步任务，以及处理任务的生命周期。
     setNewClientsInEnv是一个非async 方法，但方法体内又await currentInstance.fetchCurrentInstance()，所以这里需要用
     task{
        xxx
     }
     这样包住
     */
    Task {
      await currentInstance.fetchCurrentInstance()
      watcher.setClient(client: client, instanceStreamingURL: currentInstance.instance?.urls?.streamingApi)
      watcher.watch(streams: [.user, .direct])
    }
  }

  func handleScenePhase(scenePhase: ScenePhase) {
    switch scenePhase {
    case .background:
      watcher.stopWatching()
    case .active:
      watcher.watch(streams: [.user, .direct])
      UNUserNotificationCenter.current().setBadgeCount(0)
      userPreferences.reloadNotificationsCount(tokens: appAccountsManager.availableAccounts.compactMap(\.oauthToken))
      Task {
        await userPreferences.refreshServerPreferences()
      }
    default:
      break
    }
  }

  func setupRevenueCat() {
    Purchases.logLevel = .error
    Purchases.configure(withAPIKey: "appl_JXmiRckOzXXTsHKitQiicXCvMQi")
    Purchases.shared.getCustomerInfo { info, _ in
      if info?.entitlements["Supporter"]?.isActive == true {
        isSupporter = true
      }
    }
  }

  func refreshPushSubs() {
    PushNotificationsService.shared.requestPushNotifications()
  }
}

class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(_: UIApplication,
                   didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool
  {
    try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
    try? AVAudioSession.sharedInstance().setActive(true)
    PushNotificationsService.shared.setAccounts(accounts: AppAccountsManager.shared.pushAccounts)
    Telemetry.setup()
    Telemetry.signal("app.launched")
    WishKit.configure(with: "AF21AE07-3BA9-4FE2-BFB1-59A3B3941730")
    return true
  }

  func application(_: UIApplication,
                   didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
  {
    PushNotificationsService.shared.pushToken = deviceToken
    Task {
      PushNotificationsService.shared.setAccounts(accounts: AppAccountsManager.shared.pushAccounts)
      await PushNotificationsService.shared.updateSubscriptions(forceCreate: false)
    }
  }

  func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError _: Error) {}

  func application(_: UIApplication, didReceiveRemoteNotification _: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
    UserPreferences.shared.reloadNotificationsCount(tokens: AppAccountsManager.shared.availableAccounts.compactMap(\.oauthToken))
    return .noData
  }

  func application(_: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options _: UIScene.ConnectionOptions) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    if connectingSceneSession.role == .windowApplication {
      configuration.delegateClass = SceneDelegate.self
    }
    return configuration
  }

  override func buildMenu(with builder: UIMenuBuilder) {
    super.buildMenu(with: builder)
    builder.remove(menu: .document)
    builder.remove(menu: .toolbar)
    builder.remove(menu: .sidebar)
  }
}
