import SwiftUI

// MARK: - 宜忌视图组件

/// 宜忌项目视图 - 紧凑横排显示
struct YiJiRowView: View {
    let title: String
    let items: [String]
    let isYi: Bool
    
    private var backgroundColor: Color {
        isYi ? Color.green.opacity(0.15) : Color.red.opacity(0.15)
    }
    
    private var foregroundColor: Color {
        isYi ? .green : .red
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 宜/忌 图标
            ZStack {
                Circle()
                    .fill(foregroundColor)
                    .frame(width: 24, height: 24)
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // 宜忌项目
            Text(items.joined(separator: " "))
                .font(.system(size: 12))
                .foregroundColor(Color(red: 85/255, green: 85/255, blue: 85/255))
                .lineLimit(nil)
            
            Spacer()
        }
    }
}

/// 宜忌网格视图 - 使用FlowLayout显示标签
struct YiJiGridView: View {
    let yiItems: [String]
    let jiItems: [String]
    
    var body: some View {
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
                    ForEach(yiItems, id: \.self) { item in
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
                    ForEach(jiItems, id: \.self) { item in
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
}

/// Flow Layout - 自动换行布局
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
