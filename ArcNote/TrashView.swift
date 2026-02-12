import SwiftUI

struct TrashView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var trashManager = TrashManager.shared
    @State private var showDeleteConfirmation = false
    @State private var cardToDelete: TrashCard?
    @State private var animateDeleteConfirmation = false
    
    var body: some View {
        ZStack {
            // 背景图片
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 顶部导航栏
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text("Trash Can")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // 占位符，保持标题居中
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.clear)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 20)
                
                // 信息栏
                HStack(spacing: 5) {
                    Image("trash_tip")
                        .resizable()
                        .frame(width: 18, height: 18)
                    
                    Text("The deleted notes will be automatically cleared after 30 days.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .background(.ultraThinMaterial).cornerRadius(20)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                
                // 删除的笔记列表
                if trashManager.isLoading && trashManager.trashCards.isEmpty {
                    // 加载状态
                    VStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("Loading trash...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.top, 16)
                        Spacer()
                    }
                } else if trashManager.trashCards.isEmpty {
                    // 空状态
                    VStack {
                        Spacer()
                        Image("trash")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .foregroundColor(.white.opacity(0.5))
                        
                        Text("Trash is empty")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.top, 16)
                        
                        Text("Deleted notes will appear here")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.top, 8)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(trashManager.trashCards) { card in
                                TrashCardView(
                                    card: card,
                                    onRestore: {
                                        trashManager.restoreCard(cardId: card.id) { result in
                                            switch result {
                                            case .success:
                                                print("卡片恢复成功")
                                            case .failure(let error):
                                                print("卡片恢复失败: \(error.localizedDescription)")
                                            }
                                        }
                                    },
                                    onPermanentlyDelete: {
                                        cardToDelete = card
                                        showDeleteConfirmation = true
                                    }
                                )
                            }
                            
                            // 加载更多按钮
                            if trashManager.hasMoreData && !trashManager.isLoading {
                                Button(action: {
                                    trashManager.loadMoreTrashCards()
                                }) {
                                    Text("Load More")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(Color.white.opacity(0.1))
                                        )
                                }
                                .padding(.top, 20)
                            }
                            
                            if trashManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.0)
                                    .padding(.top, 20)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                    }
                    .refreshable {
                        trashManager.refreshTrashCards()
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            trashManager.loadTrashCards(refresh: true)
        }
        .overlay(
            // 确认删除对话框
            Group {
                if showDeleteConfirmation {
                    ZStack {
                        // 背景遮罩 带渐变动画
                        Color.black
                            .opacity(animateDeleteConfirmation ? 0.5 : 0)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    animateDeleteConfirmation = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        showDeleteConfirmation = false
                                        cardToDelete = nil
                                    }
                                }
                            }
                        
                        // 对话框 带渐变动画
                        VStack(spacing: 20) {
                            // 关闭按钮
                            HStack {
                                Spacer()
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        animateDeleteConfirmation = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            showDeleteConfirmation = false
                                            cardToDelete = nil
                                        }
                                    }
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                }
                            }
                            
                            // 确认文本
                            Text("Confirm delete this note?")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            // 按钮
                            HStack(spacing: 16) {
                                // 取消按钮
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        animateDeleteConfirmation = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            showDeleteConfirmation = false
                                            cardToDelete = nil
                                        }
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 16, weight: .medium))
                                        Text("Cancel")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(Color.gray.opacity(0.3))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                                }
                                
                                // 确认删除按钮
                                Button(action: {
                                    if let card = cardToDelete {
                                        trashManager.permanentlyDeleteCard(cardId: card.id) { result in
                                            switch result {
                                            case .success:
                                                print("卡片永久删除成功")
                                            case .failure(let error):
                                                print("卡片永久删除失败: \(error.localizedDescription)")
                                            }
                                        }
                                    }
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        animateDeleteConfirmation = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            showDeleteConfirmation = false
                                            cardToDelete = nil
                                        }
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .medium))
                                        Text("Yes")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(Color.red)
                                    )
                                }
                            }
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 20)
                        .opacity(animateDeleteConfirmation ? 1 : 0)
                        .scaleEffect(animateDeleteConfirmation ? 1 : 0.8)
                    }
                    .onAppear {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            animateDeleteConfirmation = true
                        }
                    }
                }
            }
        )
    }
    
    // MARK: 格式化删除日期
    private func formatTrashDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMM dd, yyyy"
            return displayFormatter.string(from: date)
        }
        
        return "Unknown date"
    }
}

// 垃圾桶卡片视图
struct TrashCardView: View {
    let card: TrashCard
    let onRestore: () -> Void
    let onPermanentlyDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 删除日期
            Text("Deleted on: \(formatTrashDate(card.deletedAt))")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.6))
            
            // 笔记内容
            HTMLTextRenderer(htmlContent: card.content, maxLines: 3)
            
            // 标签
            HStack(spacing: 8) {
                ForEach(card.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.07))
                        )
                }
                
                Spacer()
            }
            
            // 自动删除信息
            Text("Automatically delete after \(card.daysRemaining) days.")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.orange)
            
            // 操作按钮
            HStack(spacing: 12) {
                Button(action: onRestore) {
                    Text("Restore")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.clear)
                                .overlay(restoreButtonTopLeftHighlight)
                                .overlay(restoreButtonBottomRightHighlight)
                                .overlay(restoreButtonTopEdgeHighlight)
                                .overlay(restoreButtonBottomEdgeHighlight)
                        )
                }
                
                Button(action: onPermanentlyDelete) {
                    Text("Permanently Delete")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 210/255, green: 102/255, blue: 39/255))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(red: 248/255, green: 128/255, blue: 42/255).opacity(0.07))
                                .overlay(deleteButtonTopLeftHighlight)
                                .overlay(deleteButtonBottomRightHighlight)
                                .overlay(deleteButtonTopEdgeHighlight)
                                .overlay(deleteButtonBottomEdgeHighlight)
                        )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.2))
                .overlay(cardTopLeftHighlight)
                .overlay(cardBottomRightHighlight)
                .overlay(cardTopEdgeHighlight)
                .overlay(cardBottomEdgeHighlight)
        )
    }
    
    // MARK: 卡片高光效果
    private var cardTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var cardBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var cardTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var cardBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
    
    // MARK: Restore 按钮高光效果
    private var restoreButtonTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 5,
                            endRadius: 20
                        )
                    )
            )
    }
    
    private var restoreButtonBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 5,
                            endRadius: 20
                        )
                    )
            )
    }
    
    private var restoreButtonTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var restoreButtonBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
    
    // MARK: Delete 按钮高光效果
    private var deleteButtonTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 5,
                            endRadius: 20
                        )
                    )
            )
    }
    
    private var deleteButtonBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 5,
                            endRadius: 20
                        )
                    )
            )
    }
    
    private var deleteButtonTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var deleteButtonBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
    
    // MARK: 格式化删除日期
    private func formatTrashDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMM dd, yyyy"
            return displayFormatter.string(from: date)
        }
        
        return "Unknown date"
    }
}

#Preview {
    TrashView()
} 
