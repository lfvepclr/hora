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
        YiJiGridView(yiItems: almanac.yi, jiItems: almanac.ji)
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
