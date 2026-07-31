import SwiftUI

enum MainTab: String, CaseIterable, Codable, Hashable {
  case general
  case models
  case history

  var title: String {
    switch self {
    case .general: return "General"
    case .models: return "Models"
    case .history: return "History"
    }
  }

  var systemImage: String {
    switch self {
    case .general: return "gearshape"
    case .models: return "cpu"
    case .history: return "clock.arrow.circlepath"
    }
  }
}

final class WindowState: ObservableObject {
  @Published var selectedTab: MainTab = .general
}

struct MainView: View {
  @ObservedObject var state: WindowState
  @ObservedObject var settings: AppSettings
  @ObservedObject var historyManager: HistoryManager
  let onIconVisibilityChange: (IconVisibilityMode) -> Void

  var body: some View {
    TabView(selection: $state.selectedTab) {
      GeneralSettingsView(
        settings: settings,
        onIconVisibilityChange: onIconVisibilityChange
      )
      .tabItem {
        Label(MainTab.general.title, systemImage: MainTab.general.systemImage)
      }
      .tag(MainTab.general)

      ModelsSettingsView(settings: settings)
        .tabItem {
          Label(MainTab.models.title, systemImage: MainTab.models.systemImage)
        }
        .tag(MainTab.models)

      HistoryView(historyManager: historyManager, settings: settings)
        .tabItem {
          Label(MainTab.history.title, systemImage: MainTab.history.systemImage)
        }
        .tag(MainTab.history)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
