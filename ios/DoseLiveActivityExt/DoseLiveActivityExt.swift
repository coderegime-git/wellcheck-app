import ActivityKit
import WidgetKit
import SwiftUI

struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
  public typealias LiveDeliveryData = ContentState
  public struct ContentState: Codable, Hashable {}
  var id = UUID()
}

extension LiveActivitiesAppAttributes {
  func prefixedKey(_ key: String) -> String { "\(id)_\(key)" }
}

// Same group id as in Xcode and in Flutter
let sharedDefault = UserDefaults(suiteName: "group.com.app.wellcheck")!
private func doseInfo(_ ctx: ActivityViewContext<LiveActivitiesAppAttributes>)
  -> (name: String, dosage: String, dose: Date?) {
  let a = ctx.attributes
  let all = sharedDefault.dictionaryRepresentation()

  func read(_ suffix: String) -> Any? {
    if let v = all[a.prefixedKey(suffix)] { return v }
    // fallback: any key ending with the suffix
    return all.first(where: { $0.key.hasSuffix("_\(suffix)") })?.value
  }

  let name = (read("name") as? String) ?? "Medication"
  let dosage = (read("dosage") as? String) ?? ""

  var ms: Double? = nil
  let raw = read("doseAtMs")
  if let s = raw as? String { ms = Double(s) }
  else if let n = raw as? NSNumber { ms = n.doubleValue }

  let dose = (ms != nil && ms! > 0) ? Date(timeIntervalSince1970: ms! / 1000) : nil
  return (name, dosage, dose)
}

private func isMissed(_ ctx: ActivityViewContext<LiveActivitiesAppAttributes>,
                      _ dose: Date?) -> Bool {
  return ctx.isStale
}

private func countdown(to dose: Date) -> Text {
  let end = max(dose, Date.now.addingTimeInterval(1))
  return Text(timerInterval: Date.now...end, countsDown: true)
}

struct DoseCountdownWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
      let info = doseInfo(context)
      let missed = isMissed(context, info.dose)
      VStack(alignment: .leading, spacing: 6) {
      //  Text("💊 \(info.name)").font(.headline)
      HStack(spacing: 8) {
        Image("logo")
          .resizable()
          .scaledToFit()
          .frame(width: 28, height: 28)
          .clipShape(RoundedRectangle(cornerRadius: 6))
        Text(info.name).font(.headline)
      }
        if !info.dosage.isEmpty {
          Text(info.dosage).font(.subheadline).foregroundColor(.secondary)
        }
//          if let d = info.dose {
//               Text("dose=\(d.formatted(date: .omitted, time: .standard)) now=\(Date.now.formatted(date: .omitted, time: .standard))")
//                 .font(.caption2)
//             }
if let d = info.dose {
  Text("Scheduled \(d.formatted(date: .omitted, time: .shortened))")
    .font(.caption)
    .foregroundColor(.secondary)
}
        if missed {
          Text("Missed. Open the app to log it.")
            .font(.subheadline.bold())
            .foregroundColor(.red)
        } else if let dose = info.dose {
          HStack(spacing: 6) {
            Text("Due in").font(.subheadline)
            countdown(to: dose)
              .font(.title2.bold()).monospacedDigit()
          }
        } else {
          let all = sharedDefault.dictionaryRepresentation().keys
            Text("total=\(all.count) test=\(sharedDefault.string(forKey: "debug_test") ?? "nil")")
              .font(.caption2)
            Text(all.sorted().prefix(6).joined(separator: " | "))
              .font(.system(size: 8))
          }
      }
      .padding()
    } dynamicIsland: { context in
      let info = doseInfo(context)
      let missed = isMissed(context, info.dose)
      return DynamicIsland {
     //   DynamicIslandExpandedRegion(.leading) { Text("💊") }
     DynamicIslandExpandedRegion(.leading) {
       Image("logo").resizable().scaledToFit().frame(width: 28, height: 28)
     }
        DynamicIslandExpandedRegion(.center) {
          VStack {
            Text(info.name).font(.headline)
            if missed {
              Text("Missed").font(.title3).foregroundColor(.red)
            } else if let dose = info.dose {
              countdown(to: dose).font(.title3).monospacedDigit()
            }
          }
        }
      }compactLeading: {
         Image("logo").resizable().scaledToFit().frame(width: 20, height: 20)
       } compactTrailing: {
        if missed {
          Text("Missed").font(.caption2).foregroundColor(.red)
        } else if let dose = info.dose {
          countdown(to: dose).frame(width: 52).monospacedDigit()
        }
      } minimal: {
          Image("logo").resizable().scaledToFit().frame(width: 18, height: 18)
        }
    }
  }
}

@main
struct DoseLiveActivityBundle: WidgetBundle {
  var body: some Widget { DoseCountdownWidget() }
}