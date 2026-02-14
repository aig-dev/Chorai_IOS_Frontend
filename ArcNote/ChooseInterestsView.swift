import SwiftUI
import Combine

struct DataItem: Identifiable {
    var id: Int
    var title: String
    var size: CGFloat
    var color: Color
    var offset = CGSize.zero
    var isSelected = false
    var isMultiSelected = false
    
    // 从InterestCategory创建DataItem
    init(from category: InterestCategory) {
        self.id = category.id
        self.title = category.nameEn
        self.size = CGFloat.random(in: 100...140) // 随机大小
        self.color = Self.getRandomColor()
    }
    
    // 获取随机颜色
    private static func getRandomColor() -> Color {
        let colors: [Color] = [.blue, .purple, .green, .orange, .pink, .red, .cyan, .yellow, .mint, .indigo, .teal, .brown]
        return colors.randomElement() ?? .blue
    }
}

struct ChooseInterestsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showNext = false
    @State private var showTabBar = false
    
    // 兴趣数据管理器
    @StateObject private var interestsManager = InterestsManager()
    @StateObject private var authManager = AuthManager.shared
    @State private var interests: [DataItem] = []
    @State private var isLayoutComplete = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景图片
                Image("home_bg")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 0) {
                        // 顶部状态栏和跳过按钮
                        HStack {
                            Spacer()
                            Button(action: {
                                // 跳过逻辑 - 直接进入 Explorer 页面
                                showTabBar = true
                            }) {
                                HStack(spacing: 4) {
                                    Text("skip")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 60)
                
                // 标题区域
                VStack(spacing: 12) {
                    Text("Choose Your Interests")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("This will help us recommend content and connect you with like-minded users")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(.horizontal, 30)
                .padding(.top, 20)
                
                Spacer()
                
                // 加载状态和错误处理
                if interestsManager.isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        
                        Text("Loading interests...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(height: 400)
                } else if let error = interestsManager.error {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.red)
                        
                        Text("Failed to load interests")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                        
                        Button("Retry") {
                            loadInterests()
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(0.2))
                        )
                    }
                    .frame(height: 400)
                } else {
                    // 兴趣气泡区域 - 完全使用 BubbleView 的实现
                    ZStack {
                    ForEach(Array(interests.enumerated()), id: \.element.id) { index, item in
                        ZStack {
                            Circle()
                                .fill(
                                    item.isMultiSelected ? 
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.2),
                                            Color.white.opacity(0.2)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) :
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.gray.opacity(0.2),
                                            Color.gray.opacity(0.2)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: item.size)
                                // 上高光
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 1.5)
                                        .offset(x: -1, y: 1)
                                        .mask(
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.clear, Color.white],
                                                        startPoint: .topTrailing,
                                                        endPoint: UnitPoint(x: -0.5, y: 0.9)
                                                    )
                                                )
                                        )
                                        .opacity(item.isMultiSelected ? 1 : 0)
                                )
                                // 下高光
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 1)
                                        .offset(x: -1, y: 1)
                                        .mask(
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.white, Color.clear],
                                                        startPoint: .bottom,
                                                        endPoint: UnitPoint(x: 1, y: 0.05)
                                                    )
                                                )
                                        )
                                        .opacity(item.isMultiSelected ? 1 : 0)
                                )
                                .shadow(
                                    color: item.isMultiSelected ? Color.white.opacity(0.4) : Color.black.opacity(0.2),
                                    radius: item.isMultiSelected ? 15 : 8,
                                    x: 0,
                                    y: item.isMultiSelected ? 8 : 4
                                )
                                .scaleEffect(item.isMultiSelected ? 1.2 : 1.0)
                            
                            Text(item.title)
                                .font(.system(size: min(item.size * 0.18, 14), weight: .semibold))
                                .foregroundColor(item.isMultiSelected ? .white : .white)
                                .shadow(color: item.isMultiSelected ? Color.white.opacity(0.8) : Color.black.opacity(0.7), radius: 2, x: 0, y: 1)
                        }
                        .offset(item.offset)
                        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: item.offset)
                        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: item.isMultiSelected)
                        .onTapGesture {
                            let wasMultiSelected = interests[index].isMultiSelected
                            
                            interests[index].isMultiSelected.toggle()
                            
                            if !interests[index].isMultiSelected {
                                interests[index].isSelected = false
                            }
                            
                            DispatchQueue.main.async {
                                if wasMultiSelected {
                                    layoutBubblesAfterDeselection()
                                } else {
                                    layoutBubblesAfterSelection()
                                }
                            }
                        }
                    }
                    }
                    .scaleEffect(isLayoutComplete ? 1.0 : 0.1)
                    .opacity(isLayoutComplete ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 1.0), value: isLayoutComplete)
                    .frame(height: 400)
                }
                
                Spacer()
                
                // 趋势话题区域
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trending Topics")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<3, id: \.self) { _ in
                                Button(action: {
                                    // 点击逻辑
                                }) {
                                    Text("Trending Topics")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(Color.gray.opacity(0.3))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 20)
                
                Spacer()
                
                // 底部按钮
                HStack(spacing: 40) {
                    Button(action: {
                        resetSelection()
                    }) {
                        Text("Reset")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    Button(action: {
                        saveSelectedInterests()
                    }) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 80, height: 80)
                            
                            if interestsManager.isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text("Next")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .disabled(interestsManager.isSaving)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, max(30, geometry.safeAreaInsets.bottom + 10))
                    }
                    .frame(minHeight: geometry.size.height - geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom)
                }
                .frame(width: geometry.size.width)
            }
        }
        .ignoresSafeArea(.all)
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $showTabBar) {
            TabBarView()
        }
        .onAppear {
            loadInterests()
        }
        .onChange(of: interestsManager.interests) { newInterests in
            if !newInterests.isEmpty {
                interests = newInterests.map { DataItem(from: $0) }
                layoutBubbles()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isLayoutComplete = true
                }
            }
        }
        .onChange(of: interestsManager.saveSuccess) { success in
            if success {
                showTabBar = true
            }
        }
        .onChange(of: interestsManager.isSaving) { isSaving in
            if !isSaving && interestsManager.saveSuccess == false {
                showTabBar = true
            }
        }
    }
    
    // MARK: - 加载兴趣数据
    private func loadInterests() {
        print("加载兴趣数据")
        interestsManager.loadInterests()
    }
    
    // MARK: - 保存选中的兴趣
    private func saveSelectedInterests() {
        let selectedInterestIds = interests.filter { $0.isMultiSelected }.map { $0.id }
        
        if selectedInterestIds.isEmpty {
            showTabBar = true
            return
        }
        
        guard let currentUserId = authManager.currentUser?.id else {
            showTabBar = true
            return
        }
        
        print("保存选中的兴趣: \(selectedInterestIds), 用户ID: \(currentUserId)")
        interestsManager.saveUserInterests(userId: currentUserId, interestIds: selectedInterestIds)
    }
    
    // 重置选择
    private func resetSelection() {
        for i in 0..<interests.count {
            interests[i].isMultiSelected = false
            interests[i].isSelected = false
        }
        layoutBubblesAfterDeselection()
    }
    
    // 点击后的轻量级布局调整
    private func layoutBubblesAfterSelection() {
        for iteration in 0..<80 {
            for i in 0..<interests.count {
                var forceX: CGFloat = 0
                var forceY: CGFloat = 0
                
                for j in 0..<interests.count {
                    if i != j {
                        let dx = interests[j].offset.width - interests[i].offset.width
                        let dy = interests[j].offset.height - interests[i].offset.height
                        let distance = sqrt(dx * dx + dy * dy)
                        
                        if distance > 0 {
                            let iSize = interests[i].isMultiSelected ? interests[i].size * 1.2 : interests[i].size
                            let jSize = interests[j].isMultiSelected ? interests[j].size * 1.2 : interests[j].size
                            let minDistance = (iSize + jSize) / 2
                            let overlap = minDistance - distance
                            
                            if overlap > 0 {
                                let force = overlap / distance
                                forceX -= dx * force * 0.7
                                forceY -= dy * force * 0.7
                            } else {
                                let gap = distance - minDistance
                                if gap > 5 && gap < 25 {
                                    let attractionForce = (gap - 5) / 20 * 0.04
                                    forceX += dx * attractionForce
                                    forceY += dy * attractionForce
                                }
                            }
                        }
                    }
                }
                
                let centerDistance = sqrt(interests[i].offset.width * interests[i].offset.width + 
                                        interests[i].offset.height * interests[i].offset.height)
                if centerDistance > 120 {
                    let centerForce = 0.015
                    forceX -= interests[i].offset.width * centerForce
                    forceY -= interests[i].offset.height * centerForce
                }
                
                applyBoundaryConstraints(for: i, forceX: &forceX, forceY: &forceY)
                
                let stepSize = 0.15 * (1.0 - Double(iteration) / 80.0)
                interests[i].offset.width += forceX * stepSize
                interests[i].offset.height += forceY * stepSize
            }
        }
        
        quickFixOverlaps()
        compactLayout()
    }
    
    // 取消选择后的强紧凑化布局
    private func layoutBubblesAfterDeselection() {
        for iteration in 0..<100 {
            for i in 0..<interests.count {
                var forceX: CGFloat = 0
                var forceY: CGFloat = 0
                
                for j in 0..<interests.count {
                    if i != j {
                        let dx = interests[j].offset.width - interests[i].offset.width
                        let dy = interests[j].offset.height - interests[i].offset.height
                        let distance = sqrt(dx * dx + dy * dy)
                        
                        if distance > 0 {
                            let iSize = interests[i].isMultiSelected ? interests[i].size * 1.2 : interests[i].size
                            let jSize = interests[j].isMultiSelected ? interests[j].size * 1.2 : interests[j].size
                            let minDistance = (iSize + jSize) / 2
                            let overlap = minDistance - distance
                            
                            if overlap > 0 {
                                let force = overlap / distance
                                forceX -= dx * force * 1.0
                                forceY -= dy * force * 1.0
                            } else {
                                let gap = distance - minDistance
                                if gap > 0 && gap < 30 {
                                    let attractionForce = (30 - gap) / 30 * 0.04
                                    forceX += dx * attractionForce
                                    forceY += dy * attractionForce
                                }
                            }
                        }
                    }
                }
                
                let centerDistance = sqrt(interests[i].offset.width * interests[i].offset.width + 
                                        interests[i].offset.height * interests[i].offset.height)
                if centerDistance > 100 {
                    let centerForce = 0.02
                    forceX -= interests[i].offset.width * centerForce
                    forceY -= interests[i].offset.height * centerForce
                }
                
                applyBoundaryConstraints(for: i, forceX: &forceX, forceY: &forceY)
                
                let stepSize = 0.2 * (1.0 - Double(iteration) / 100.0)
                interests[i].offset.width += forceX * stepSize
                interests[i].offset.height += forceY * stepSize
            }
        }
        
        quickFixOverlaps()
        gentleCompactLayout()
    }
    
    // 温和的紧凑化布局
    private func gentleCompactLayout() {
        for iteration in 0..<40 {
            for i in 0..<interests.count {
                var forceX: CGFloat = 0
                var forceY: CGFloat = 0
                
                for j in 0..<interests.count {
                    if i != j {
                        let dx = interests[j].offset.width - interests[i].offset.width
                        let dy = interests[j].offset.height - interests[i].offset.height
                        let distance = sqrt(dx * dx + dy * dy)
                        
                        if distance > 0 {
                            let iSize = interests[i].isMultiSelected ? interests[i].size * 1.2 : interests[i].size
                            let jSize = interests[j].isMultiSelected ? interests[j].size * 1.2 : interests[j].size
                            let minDistance = (iSize + jSize) / 2
                            let gap = distance - minDistance
                            
                            if gap > 10 && gap < 50 {
                                let compactForce = (gap - 10) / 40 * 0.03
                                forceX += dx * compactForce
                                forceY += dy * compactForce
                            }
                        }
                    }
                }
                
                let stepSize = 0.08 * (1.0 - Double(iteration) / 40.0)
                interests[i].offset.width += forceX * stepSize
                interests[i].offset.height += forceY * stepSize
            }
        }
    }
    
    // 快速修复重叠
    private func quickFixOverlaps() {
        for _ in 0..<30 {
            var hasOverlap = false
            
            for i in 0..<interests.count {
                for j in (i+1)..<interests.count {
                    let dx = interests[j].offset.width - interests[i].offset.width
                    let dy = interests[j].offset.height - interests[i].offset.height
                    let distance = sqrt(dx * dx + dy * dy)
                    
                    let iSize = interests[i].isMultiSelected ? interests[i].size * 1.2 : interests[i].size
                    let jSize = interests[j].isMultiSelected ? interests[j].size * 1.2 : interests[j].size
                    let minDistance = (iSize + jSize) / 2
                    
                    if distance < minDistance {
                        hasOverlap = true
                        
                        let overlap = minDistance - distance
                        let moveDistance = overlap / 2
                        
                        if distance > 0 {
                            let moveX = (dx / distance) * moveDistance
                            let moveY = (dy / distance) * moveDistance
                            
                            interests[i].offset.width -= moveX
                            interests[i].offset.height -= moveY
                            interests[j].offset.width += moveX
                            interests[j].offset.height += moveY
                        } else {
                            let randomAngle = Double.random(in: 0..<2 * Double.pi)
                            let moveX = cos(randomAngle) * moveDistance
                            let moveY = sin(randomAngle) * moveDistance
                            
                            interests[i].offset.width -= moveX
                            interests[i].offset.height -= moveY
                            interests[j].offset.width += moveX
                            interests[j].offset.height += moveY
                        }
                    }
                }
            }
            
            if !hasOverlap {
                break
            }
        }
    }
    
    // 使用力导向算法布局气泡
    private func layoutBubbles() {
        guard interests.count > 0 else { return }
        
        let sortedData = interests.enumerated().sorted { $0.element.size > $1.element.size }
        let sortedIndices = sortedData.map { $0.offset }
        
        interests[sortedIndices[0]].offset = CGSize.zero
        
        for i in 1..<sortedIndices.count {
            let currentIndex = sortedIndices[i]
            
            let bestPosition = findBestPosition(for: currentIndex, existingBubbles: Array(sortedIndices.prefix(i)))
            interests[currentIndex].offset = bestPosition
        }
        
        for iteration in 0..<500 {
            for i in 0..<interests.count {
                var forceX: CGFloat = 0
                var forceY: CGFloat = 0
                
                for j in 0..<interests.count {
                    if i != j {
                        let dx = interests[j].offset.width - interests[i].offset.width
                        let dy = interests[j].offset.height - interests[i].offset.height
                        let distance = sqrt(dx * dx + dy * dy)
                        
                        if distance > 0 {
                            let iSize = interests[i].isMultiSelected ? interests[i].size * 1.2 : interests[i].size
                            let jSize = interests[j].isMultiSelected ? interests[j].size * 1.2 : interests[j].size
                            let minDistance = (iSize + jSize) / 2
                            let overlap = minDistance - distance
                            
                            if overlap > 0 {
                                let force = overlap / distance
                                forceX -= dx * force * 0.8
                                forceY -= dy * force * 0.8
                            } else {
                                let gap = distance - minDistance
                                if gap > 5 && gap < 25 {
                                    let attractionForce = (gap - 5) / 20 * 0.04
                                    forceX += dx * attractionForce
                                    forceY += dy * attractionForce
                                }
                            }
                        }
                    }
                }
                
                let centerDistance = sqrt(interests[i].offset.width * interests[i].offset.width + 
                                        interests[i].offset.height * interests[i].offset.height)
                if centerDistance > 120 {
                    let centerForce = 0.02
                    forceX -= interests[i].offset.width * centerForce
                    forceY -= interests[i].offset.height * centerForce
                }
                
                applyBoundaryConstraints(for: i, forceX: &forceX, forceY: &forceY)
                
                let stepSize = 0.3 * (1.0 - Double(iteration) / 500.0)
                interests[i].offset.width += forceX * stepSize
                interests[i].offset.height += forceY * stepSize
            }
        }
        
        fixOverlaps()
        centerLayout()
    }
    
    // 修复重叠的气泡
    private func fixOverlaps() {
        var hasOverlap = true
        var maxIterations = 100
        
        while hasOverlap && maxIterations > 0 {
            hasOverlap = false
            maxIterations -= 1
            
            for i in 0..<interests.count {
                for j in (i+1)..<interests.count {
                    let dx = interests[j].offset.width - interests[i].offset.width
                    let dy = interests[j].offset.height - interests[i].offset.height
                    let distance = sqrt(dx * dx + dy * dy)
                    
                    let iSize = interests[i].isMultiSelected ? interests[i].size * 1.2 : interests[i].size
                    let jSize = interests[j].isMultiSelected ? interests[j].size * 1.2 : interests[j].size
                    let minDistance = (iSize + jSize) / 2
                    
                    if distance < minDistance {
                        hasOverlap = true
                        
                        let overlap = minDistance - distance
                        let moveDistance = overlap / 2
                        
                        if distance > 0 {
                            let moveX = (dx / distance) * moveDistance
                            let moveY = (dy / distance) * moveDistance
                            
                            interests[i].offset.width -= moveX
                            interests[i].offset.height -= moveY
                            interests[j].offset.width += moveX
                            interests[j].offset.height += moveY
                        } else {
                            let randomAngle = Double.random(in: 0..<2 * Double.pi)
                            let moveX = cos(randomAngle) * moveDistance
                            let moveY = sin(randomAngle) * moveDistance
                            
                            interests[i].offset.width -= moveX
                            interests[i].offset.height -= moveY
                            interests[j].offset.width += moveX
                            interests[j].offset.height += moveY
                        }
                    }
                }
            }
        }
    }
    
    // 为新的气泡找到最佳位置
    private func findBestPosition(for bubbleIndex: Int, existingBubbles: [Int]) -> CGSize {
        let newBubbleSize = interests[bubbleIndex].size
        var bestPosition = CGSize.zero
        var minTotalDistance: CGFloat = .infinity
        
        for angle in stride(from: 0.0, to: 2.0 * Double.pi, by: Double.pi / 16.0) {
            for distance in stride(from: 30, to: 250, by: 15) {
                let candidatePosition = CGSize(
                    width: cos(angle) * CGFloat(distance),
                    height: sin(angle) * CGFloat(distance)
                )
                
                var totalDistance: CGFloat = 0
                var isValid = true
                
                for existingIndex in existingBubbles {
                    let existingPosition = interests[existingIndex].offset
                    let dx = candidatePosition.width - existingPosition.width
                    let dy = candidatePosition.height - existingPosition.height
                    let distance = sqrt(dx * dx + dy * dy)
                    let minRequiredDistance = (newBubbleSize + interests[existingIndex].size) / 2 + 5
                    
                    if distance < minRequiredDistance {
                        isValid = false
                        break
                    }
                    
                    totalDistance += distance
                }
                
                if isValid && totalDistance < minTotalDistance {
                    minTotalDistance = totalDistance
                    bestPosition = candidatePosition
                }
            }
        }
        
        return bestPosition
    }
    
    // 应用边界约束
    private func applyBoundaryConstraints(for index: Int, forceX: inout CGFloat, forceY: inout CGFloat) {
        let itemSize = interests[index].isMultiSelected ? interests[index].size * 1.2 : interests[index].size
        let halfSize = itemSize / 2
        
        var minY: CGFloat = .infinity
        var maxY: CGFloat = -.infinity
        var minX: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        
        for item in interests {
            let itemY = item.offset.height
            let itemX = item.offset.width
            let itemHalfSize = (item.isMultiSelected ? item.size * 1.2 : item.size) / 2
            minY = min(minY, itemY - itemHalfSize)
            maxY = max(maxY, itemY + itemHalfSize)
            minX = min(minX, itemX - itemHalfSize)
            maxX = max(maxX, itemX + itemHalfSize)
        }
        
        let layoutHeight = maxY - minY
        let layoutWidth = maxX - minX
        let targetHeight: CGFloat = 380
        let targetWidth: CGFloat = 450
        
        if layoutHeight > targetHeight {
            let compressionForce = 0.008
            if interests[index].offset.height > 0 {
                forceY -= compressionForce
            } else {
                forceY += compressionForce
            }
        }
        
        if layoutWidth > targetWidth {
            let compressionForce = 0.008
            if interests[index].offset.width > 0 {
                forceX -= compressionForce
            } else {
                forceX += compressionForce
            }
        }
        
        let topThreshold = minY + 60
        let bottomThreshold = maxY - 60
        let currentY = interests[index].offset.height
        
        if currentY - halfSize < topThreshold {
            let alignmentForce = 0.025
            forceY -= alignmentForce
            
            let topRowY = minY + halfSize
            let yDiff = topRowY - currentY
            if abs(yDiff) < 30 {
                forceY += yDiff * 0.01
            }
        } else if currentY + halfSize > bottomThreshold {
            let alignmentForce = 0.025
            forceY += alignmentForce
            
            let bottomRowY = maxY - halfSize
            let yDiff = bottomRowY - currentY
            if abs(yDiff) < 30 {
                forceY += yDiff * 0.01
            }
        }
        
        let leftThreshold = minX + 60
        let rightThreshold = maxX - 60
        let currentX = interests[index].offset.width
        
        if currentX - halfSize < leftThreshold {
            let alignmentForce = 0.025
            forceX -= alignmentForce
        } else if currentX + halfSize > rightThreshold {
            let alignmentForce = 0.025
            forceX += alignmentForce
        }
        
        let maxRange: CGFloat = 250
        if abs(currentX) > maxRange {
            let boundaryForce = 0.04
            if currentX > 0 {
                forceX -= boundaryForce
            } else {
                forceX += boundaryForce
            }
        }
        
        if abs(currentY) > maxRange {
            let boundaryForce = 0.04
            if currentY > 0 {
                forceY -= boundaryForce
            } else {
                forceY += boundaryForce
            }
        }
    }
    
    // 将整个布局居中
    private func centerLayout() {
        var minX: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        var minY: CGFloat = .infinity
        var maxY: CGFloat = -.infinity
        
        for item in interests {
            let itemSize = item.isMultiSelected ? item.size * 1.2 : item.size
            let left = item.offset.width - itemSize / 2
            let right = item.offset.width + itemSize / 2
            let top = item.offset.height - itemSize / 2
            let bottom = item.offset.height + itemSize / 2
            
            minX = min(minX, left)
            maxX = max(maxX, right)
            minY = min(minY, top)
            maxY = max(maxY, bottom)
        }
        
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        
        for i in 0..<interests.count {
            interests[i].offset.width -= centerX
            interests[i].offset.height -= centerY
        }
    }
    
    // 额外的紧凑化布局
    private func compactLayout() {
        for iteration in 0..<30 {
            for i in 0..<interests.count {
                var forceX: CGFloat = 0
                var forceY: CGFloat = 0
                
                for j in 0..<interests.count {
                    if i != j {
                        let dx = interests[j].offset.width - interests[i].offset.width
                        let dy = interests[j].offset.height - interests[i].offset.height
                        let distance = sqrt(dx * dx + dy * dy)
                        
                        if distance > 0 {
                            let iSize = interests[i].isMultiSelected ? interests[i].size * 1.2 : interests[i].size
                            let jSize = interests[j].isMultiSelected ? interests[j].size * 1.2 : interests[j].size
                            let minDistance = (iSize + jSize) / 2
                            let gap = distance - minDistance
                            
                            if gap > 8 && gap < 40 {
                                let compactForce = (gap - 8) / 32 * 0.02
                                forceX += dx * compactForce
                                forceY += dy * compactForce
                            }
                        }
                    }
                }
                
                let stepSize = 0.06 * (1.0 - Double(iteration) / 30.0)
                interests[i].offset.width += forceX * stepSize
                interests[i].offset.height += forceY * stepSize
            }
        }
    }
}

#Preview {
    ChooseInterestsView()
} 
