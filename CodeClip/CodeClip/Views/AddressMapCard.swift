import SwiftUI
import MapKit

// MARK: - 取件地址地图卡（2026-10-14 主人定稿 · 方案 B）
//
// 定位结论（主人问「软件内导航能不能免费做」时给的答复）：
//   · 软件内**看地图**免费 —— MapKit 是 Apple 自带框架，零密钥零费用；
//   · 实时语音导航 Apple **禁止第三方内嵌**，必须跳系统地图 App ——
//     同样免费（`MKMapItem.openInMaps` + `CLGeocoder`）。
// 所以本卡 = MapKit 迷你预览 + 点按跳 Apple 地图步行/驾车导航，
// 不引入任何第三方 SDK / 密钥。

struct AddressMapCard: View {

    let address: String

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic
    @State private var isGeocoding = false
    @State private var didFail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 行 1：地址文本 + 导航按钮（点文字/按钮都走同一条跳转链路）
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)

                Text(address)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 6)

                navigateButton
            }

            // 行 2：地图预览（点地图同样跳导航）
            map
        }
        .padding(AppTheme.cardPadding + 3)
        .frame(maxWidth: .infinity)
        .cardSurface()
        .onAppear(perform: geocode)
    }

    /// 导航胶囊按钮：液态玻璃 + 步行语义（驿站就在街边，步行是第一动线）
    private var navigateButton: some View {
        Button(action: navigate) {
            Label("导航", systemImage: "figure.walk")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.regular.tint(AppTheme.accent.opacity(0.6)).interactive(),
                             in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("在地图中导航到该地址")
    }

    @ViewBuilder
    private var map: some View {
        ZStack {
            if let coordinate {
                Map(position: $camera) {
                    Marker(address, coordinate: coordinate)
                }
                .mapStyle(.standard)
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
            } else {
                placeholder
            }
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.innerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.innerRadius, style: .continuous)
                .stroke(.separator.opacity(0.4), lineWidth: 0.5)
        }
        // 点地图 = 跳导航（simultaneous 保留地图自身的缩放/拖动手势）
        .simultaneousGesture(TapGesture().onEnded { navigate() })
    }

    /// 地理编码中的占位：不显示灰块空图，告诉用户「正在解析」
    private var placeholder: some View {
        ZStack {
            Color(.secondarySystemBackground)
            VStack(spacing: 8) {
                if isGeocoding {
                    ProgressView().scaleEffect(0.9)
                    Text("正在解析位置…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if didFail {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                    Text("无法解析该地址，点按仍可在地图中搜索")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    Image(systemName: "map")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                    Text("位置未解析")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 地理编码 / 跳转

    /// 解析地址坐标（MapKit 免费服务，本机+Apple 混合，限频约 50 次/分钟，
    /// 详情页点开一两次的频率远够用）。
    private func geocode() {
        guard coordinate == nil, !isGeocoding else { return }
        isGeocoding = true
        CLGeocoder().geocodeAddressString(address) { placemarks, _ in
            DispatchQueue.main.async {
                isGeocoding = false
                if let coord = placemarks?.first?.location?.coordinate {
                    coordinate = coord
                    camera = .region(MKCoordinateRegion(
                        center: coord,
                        latitudinalMeters: 900, longitudinalMeters: 900))
                } else {
                    didFail = true
                }
            }
        }
    }

    /// 跳转导航：有坐标 → Apple 地图步行导航；无坐标 → 先把地址丢给
    /// `maps.apple.com` 搜索（URL scheme 兜底，解析失败也能用）。
    private func navigate() {
        if let coordinate {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            item.name = address
            item.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
            ])
            return
        }
        // 还没有坐标：立刻补一次地理编码，回来再决定走哪条路
        guard !isGeocoding else { return }
        isGeocoding = true
        CLGeocoder().geocodeAddressString(address) { placemarks, _ in
            DispatchQueue.main.async {
                isGeocoding = false
                if let coord = placemarks?.first?.location?.coordinate {
                    coordinate = coord
                    camera = .region(MKCoordinateRegion(
                        center: coord,
                        latitudinalMeters: 900, longitudinalMeters: 900))
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: coord))
                    item.name = address
                    item.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
                    ])
                } else {
                    didFail = true
                    openMapsQuery()
                }
            }
        }
    }

    /// 兜底：让 Apple 地图按地址文本搜索（高德/百度装了也能从地图 App 内选）
    private func openMapsQuery() {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://maps.apple.com/?q=\(encoded)") else { return }
        UIApplication.shared.open(url)
    }
}
