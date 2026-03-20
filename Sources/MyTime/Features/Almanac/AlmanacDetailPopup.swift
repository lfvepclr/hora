import SwiftUI

/// 黄历详情弹窗 - 模块化组件
/// 显示完整的黄历信息，包括五行、冲煞、宜忌、吉凶神等
struct AlmanacDetailPopup: View {
    let date: Date
    @Binding var isPresented: Bool
    
    private var almanac: AlmanacData {
        LunarCalendarService.shared.getAlmanacInfo(for: date)
    }
    
    // 标题颜色 #c69c70
    private let titleColor = Color(red: 198/255, green: 156/255, blue: 112/255)
    // 内容颜色 #555
    private let contentColor = Color(red: 85/255, green: 85/255, blue: 85/255)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 16) {
                // 五行、冲煞、彭祖
                basicInfoSection
                
                // 喜神、福神、财神（自带上下分隔线）
                godsSection
                
                // 宜忌
                YiJiRowView(title: "宜", items: almanac.yi, isYi: true)
                YiJiRowView(title: "忌", items: almanac.ji, isYi: false)
                
                // 吉神
                if !almanac.jiShen.isEmpty {
                    shenRow(title: "吉神", items: almanac.jiShen)
                }
                
                // 凶神
                if !almanac.xiongShen.isEmpty {
                    shenRow(title: "凶神", items: almanac.xiongShen)
                }
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 0)) // 先清除默认圆角
        .clipShape(UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: 0, bottomTrailing: 8, topTrailing: 8)))
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: -2, y: 2)
    }
    
    // MARK: - 基本信息（五行、冲煞、彭祖）
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow(title: "五行", content: almanac.wuXing)
            infoRow(title: "冲煞", content: "\(almanac.chong) \(almanac.sha)")
            infoRow(title: "彭祖", content: almanac.pengZu)
        }
    }
    
    // MARK: - 喜神、福神、财神
    private var godsSection: some View {
        VStack(spacing: 0) {
            // 上分隔线
            Rectangle()
                .fill(Color.gray.opacity(0.5))
                .frame(height: 1)
            
            HStack(spacing: 20) {
                godRow(title: "喜神", content: "正南")
                godRow(title: "福神", content: "东南")
                godRow(title: "财神", content: "西南")
            }
            .padding(.vertical, 8)
            
            // 下分隔线
            Rectangle()
                .fill(Color.gray.opacity(0.5))
                .frame(height: 1)
        }
    }
    
    // MARK: - 辅助方法
    
    private func infoRow(title: String, content: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(titleColor)
                .frame(width: 36, alignment: .leading)
            
            Text(content)
                .font(.system(size: 13))
                .foregroundColor(contentColor)
                .lineLimit(nil)
            
            Spacer()
        }
    }
    
    private func godRow(title: String, content: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(titleColor)
            Text(content)
                .font(.system(size: 12))
                .foregroundColor(contentColor)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func shenRow(title: String, items: [String]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(titleColor)
                .frame(width: 36, alignment: .leading)
            
            Text(items.joined(separator: " "))
                .font(.system(size: 12))
                .foregroundColor(contentColor)
                .lineLimit(nil)
            
            Spacer()
        }
    }
}

// MARK: - Preview

struct AlmanacDetailPopup_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.3)
                .ignoresSafeArea()
            
            AlmanacDetailPopup(date: Date(), isPresented: .constant(true))
                .frame(width: 280, height: 400)
        }
    }
}
