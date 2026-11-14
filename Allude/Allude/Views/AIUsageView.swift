import SwiftUI

// MARK: ============================================================================
// 用量统计（2026-11-14 主人要求：App 内简单的消耗与人民币花费）
//
// 只读本机记账（`AIUsageStore`），按各家官方价目表**估算**；不做图表、不做图表库。
// 版式照设置页：功能/数字在上，说明在下。
// ============================================================================

struct AIUsageView: View {
    @State private var total = AIUsageStore.allTotals
    @State private var perProvider: [(provider: AIProvider, totals: AIUsageStore.Totals)] = []
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard

                if total.requests == 0 {
                    Text("还没有用量。开启某家模型并让它参与过解析后，这里会开始累计。")
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    providerCard
                    resetRow
                }

                Text("只统计这台设备上、由 Allude 发起的增强请求；token 数与金额按各家公开价目表估算（元 / 百万 tokens），实际以服务商账单为准。数据只留本机，不上传。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("用量统计")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["AI_USAGE_SEED"] == "1" {
                AIUsageStore.add(provider: .deepseek, model: "deepseek-chat", input: 128_400, output: 31_200)
                AIUsageStore.add(provider: .deepseek, model: "deepseek-chat", input: 64_000, output: 12_000)
                AIUsageStore.add(provider: .kimi, model: "moonshot-v1-8k", input: 9_800, output: 2_400)
            }
            #endif
            reload()
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(AIUsageStore.costText(total.costCNY))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("累计估算花费")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                metric("请求", "\(total.requests)")
                metricDivider
                metric("输入", AIUsageStore.tokenText(total.inputTokens))
                metricDivider
                metric("输出", AIUsageStore.tokenText(total.outputTokens))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    private var providerCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(perProvider.enumerated()), id: \.element.provider.id) { index, item in
                if index > 0 { SettingsDivider() }
                HStack(spacing: 12) {
                    Image(item.provider.iconAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                        .clipShape(.rect(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.provider.title)
                            .font(AppTheme.TypeScale.rowTitle)
                        Text("\(item.totals.requests) 次 · 入 \(AIUsageStore.tokenText(item.totals.inputTokens)) / 出 \(AIUsageStore.tokenText(item.totals.outputTokens))")
                            .font(AppTheme.TypeScale.note)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(AIUsageStore.costText(item.totals.costCNY))
                        .font(AppTheme.TypeScale.rowTitle)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .settingsCard()
    }

    private var resetRow: some View {
        Button(role: .destructive) {
            confirmReset = true
        } label: {
            HStack {
                Text("清除统计")
                    .font(AppTheme.TypeScale.rowTitle)
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .settingsCard()
        .confirmationDialog("清除本机的用量统计？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                AIUsageStore.reset()
                reload()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只清本机记录，不影响服务商那边的账单。")
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(AppTheme.TypeScale.rowTitle)
            Text(title)
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 0.5, height: 28)
            .padding(.horizontal, 8)
    }

    private func reload() {
        total = AIUsageStore.allTotals
        perProvider = AIProvider.allCases
            .map { ($0, AIUsageStore.totals(for: $0)) }
            .filter { $0.1.requests > 0 }
    }
}
