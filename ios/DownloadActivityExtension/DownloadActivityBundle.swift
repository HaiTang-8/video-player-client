import WidgetKit
import SwiftUI

@main
struct DownloadActivityBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.2, *) {
            DownloadActivityWidget()
        }
    }
}
