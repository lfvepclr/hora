import SwiftUI

struct AlmanacDetailView: View {
    let date: Date
    
    private var lunarInfo: LunarInfo {
        LunarCalendarService.shared.getLunarInfo(for: date)
    }
    
    private var almanac: AlmanacData {
        LunarCalendarService.shared.getAlmanacInfo(for: date)
    }
    
    private var shiChenList: [ShiChenData] {
        LunarCalendarService.shared.getShiChenInfo(for: date)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 日期头部
                headerSection
                
                // 宜忌
                yiJiSection
                
                // 详细信息网格
                detailGridSection
                
                // 时辰吉凶
                shiChenSection
            }
            .padding()
        }
        .navigationTitle("黄历详情")
        .frame(minWidth: 600, minHeight: 500)
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日 EEEE"
        return formatter.string(from: date)
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(lunarInfo.displayLunarDate)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.primary)
            
            HStack(spacing: 8) {
                Text("\(lunarInfo.ganZhiYear)年 \(lunarInfo.ganZhiMonth)月 \(lunarInfo.ganZhiDay)日")
                Text("[属\(lunarInfo.zodiac)]")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            
            Text(dateString)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - 宜忌
    
    private var yiJiSection: some View {
        HStack(spacing: 16) {
            // 宜
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("宜")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                }
                
                FlowLayout(spacing: 6) {
                    ForEach(almanac.yi, id: \.self) { item in
                        Text(item)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .cornerRadius(4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.green.opacity(0.05))
            .cornerRadius(12)
            
            // 忌
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("忌")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                }
                
                FlowLayout(spacing: 6) {
                    ForEach(almanac.ji, id: \.self) { item in
                        Text(item)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .cornerRadius(4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.red.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Detail Grid
    
    private var detailGridSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            DetailItem(title: "五行", value: almanac.wuXing)
            DetailItem(title: "冲煞", value: "冲\(almanac.chong) 煞\(almanac.sha)")
            DetailItem(title: "值神", value: almanac.zhiShen)
            DetailItem(title: "建除", value: almanac.jianChu)
            DetailItem(title: "胎神", value: almanac.taiShen)
            DetailItem(title: "星宿", value: almanac.xingXiu)
        }
    }
    
    // MARK: - 时辰吉凶
    
    private var shiChenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("时辰吉凶")
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                ForEach(shiChenList, id: \.name) { shiChen in
                    ShiChenCell(data: shiChen)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Supporting Views

struct DetailItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }
}

struct ShiChenCell: View {
    let data: ShiChenData
    
    var body: some View {
        VStack(spacing: 2) {
            Text(data.name)
                .font(.caption)
                .fontWeight(.medium)
            Text(data.timeRange)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Image(systemName: data.isGood ? "checkmark.circle" : "xmark.circle")
                .foregroundStyle(data.isGood ? .green : .red)
                .font(.caption)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(data.isGood ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                
                self.size.width = max(self.size.width, x)
            }
            
            self.size.height = y + rowHeight
        }
    }
}
