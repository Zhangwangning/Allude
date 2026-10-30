import SwiftUI
import MapKit

// MARK: - 取件地址地图卡（2026-10-14 主人定稿 · 方案 B）
//
// 定位结论（主人问「软件内导航能不能免费做」时给的答复）：
//   · 软件内**看地图**免费 —— MapKit 是 Apple 自带框架，零密钥零费用；
//   · 实时语音导航 Apple **禁止第三方内嵌**，必须跳系统地图 App ——
//     同样免费（`MKMapItem.openInMaps` + `MKGeocodingRequest`，后者 iOS 26 起
//     取代已弃用的 `CLGeocoder`）。
// 所以本卡 = MapKit 迷你预览 + 点按跳 Apple 地图步行/驾车导航，
// 不引入任何第三方 SDK / 密钥。

struct AddressMapCard: View {

    let address: String

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic
    @State private var isGeocoding = false
    @State private var didFail = false

    var body: some View {
        if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptyCard
        } else {
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
    }

    /// 没有取件地址时的形态（2026-10-25）：
    /// 以前照样渲染一整张卡 + 地图 + 导航按钮，`MKGeocodingRequest("")` 必然失败，
    /// 于是固定显示「无法解析该地址，点按仍可在地图中搜索」—— 用户会以为导航坏了，
    /// 实际是根本没有地址可去。这里直接说清楚「未填写地址」，并去掉无意义的导航入口。
    private var emptyCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("未填写取件地址")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            Text("点右上「编辑」补充")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(AppTheme.cardPadding + 3)
        .frame(maxWidth: .infinity)
        .cardSurface()
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

    /// 解析地址坐标。
    ///
    /// 🔴 必须**先 POI 搜索、再退回地址解析**（2026-10-25 修，主人问「已取页面的地址
    /// 为什么无法导航」时定位到根因）：
    ///   · `MKGeocodingRequest(addressString:)` 面向**结构化街道地址**（省市区 + 门牌），
    ///     拿「家佳福超市」「甘州院子店」这类**门店名**去问，它基本返回空 ——
    ///     于是所有驿站 / 超市类取件地址都卡在「无法解析该地址」；
    ///   · `MKLocalSearch` 才是 POI 检索（Apple 地图里搜商户用的就是它），
    ///     而且天生偏向设备当前位置，同名店铺会优先给最近的那家。
    /// 所以顺序是：POI 搜到就用 → 搜不到再按地址解析 → 都不行才标记失败。
    ///
    /// 回调统一**回主线程**：两个 API 的结果回调都不保证在主线程，
    /// 而调用方要改 `@State`（coordinate / didFail），非主线程更新 SwiftUI 状态会报警告。
    private func resolveCoordinate(_ completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        let finish: (CLLocationCoordinate2D?) -> Void = { coord in
            DispatchQueue.main.async { completion(coord) }
        }

        let poiRequest = MKLocalSearch.Request()
        poiRequest.naturalLanguageQuery = address
        MKLocalSearch(request: poiRequest).start { response, _ in
            if let coord = response?.mapItems.first?.location.coordinate {
                finish(coord)
                return
            }
            // POI 没搜到（少见写法 / 纯路名）→ 退回地址解析
            guard let geocodeRequest = MKGeocodingRequest(addressString: address) else {
                finish(nil)
                return
            }
            geocodeRequest.getMapItems { items, _ in
                finish(items?.first?.location.coordinate)
            }
        }
    }

    /// 落地坐标并收拢镜头（900m 视野，驿站就在街边，够看全街区）
    private func apply(_ coord: CLLocationCoordinate2D) {
        coordinate = coord
        camera = .region(MKCoordinateRegion(
            center: coord,
            latitudinalMeters: 900, longitudinalMeters: 900))
    }

    private func geocode() {
        guard coordinate == nil, !isGeocoding else { return }
        isGeocoding = true
        resolveCoordinate { coord in
            isGeocoding = false
            if let coord {
                apply(coord)
            } else {
                didFail = true
            }
        }
    }

    /// 跳转导航：有坐标 → Apple 地图步行导航；无坐标 → 先把地址丢给
    /// `maps.apple.com` 搜索（URL scheme 兜底，解析失败也能用）。
    private func navigate() {
        if let coordinate {
            openNavigation(to: coordinate)
            return
        }
        // 还没有坐标：立刻补一次地理编码，回来再决定走哪条路
        guard !isGeocoding else { return }
        isGeocoding = true
        resolveCoordinate { coord in
            isGeocoding = false
            if let coord {
                apply(coord)
                openNavigation(to: coord)
            } else {
                didFail = true
                openMapsQuery()
            }
        }
    }

    /// 跳 Apple 地图步行导航。
    /// 2026-10-20：iOS 26 起 `MKPlacemark` 与 `MKMapItem(placemark:)` 已弃用 →
    /// 改用 `MKMapItem(location:address:)`（只给坐标、无结构化地址，address 传 nil）。
    private func openNavigation(to coordinate: CLLocationCoordinate2D) {
        let item = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil)
        item.name = address
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    /// 兜底：让 Apple 地图按地址文本搜索（高德/百度装了也能从地图 App 内选）
    private func openMapsQuery() {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://maps.apple.com/?q=\(encoded)") else { return }
        UIApplication.shared.open(url)
    }
}
