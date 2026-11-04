import SwiftUI
import Combine
import CoreFlow

struct NewInsightView: View {
    @Binding var isPresented: Bool
    @State private var tags: [String] = []
    @State private var newTagText = ""
    @State private var showAddTag = false
    @State private var contentText = ""
    @State private var titleText = "New Insight"
    @StateObject private var publishManager = PublishNoteManager.shared
    @StateObject private var networkManager = NetworkManager.shared
    @StateObject private var authManager = AuthManager.shared
    @State private var isConfirming = false
    @State private var confirmError: String? = nil
    @State private var cancellables = Set<AnyCancellable>()
    @State private var isAlwaysOnTop = false
    
    let mergeResult: MergeCardsData?
    let previewData: MergePreviewResponse?
    let selectedCards: [SelectedCard]?
    
    // MARK: 计算属性
    private var currentRate: Int {
        if let previewData = previewData {
            return previewData.data.newCard.rate
        } else if let mergeResult = mergeResult {
            return mergeResult.newCard.rate
        } else {
            return 0 // 默认值
        }
    }

    private var levelStyle: CardLevelStyle {
        CardLevelStyle(rate: currentRate)
    }
    
    init(isPresented: Binding<Bool>, mergeResult: MergeCardsData? = nil, previewData: MergePreviewResponse? = nil, selectedCards: [SelectedCard]? = nil) {
        self._isPresented = isPresented
        self.mergeResult = mergeResult
        self.previewData = previewData
        self.selectedCards = selectedCards
    }
    
    var body: some View {
        ZStack {
            // 背景模糊效果
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            // 主要内容
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                // 标题和徽章
                VStack(spacing: 12) {
                    Text(titleText)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(ChoraiTheme.ink)
                    
                    Text(levelStyle.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(
                            levelStyle.materialAccentColor ?? ChoraiTheme.ink
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            CardLevelMaterial(
                                style: levelStyle,
                                shape: RoundedRectangle(cornerRadius: 12)
                            )
                        )
                        .accessibilityLabel(levelStyle.label)
                }
                
                // 主要内容区域
                VStack(alignment: .leading, spacing: 16) {
                    TextEditor(text: $contentText)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(ChoraiTheme.ink)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(height: 230)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(ChoraiTheme.ink.opacity(0.3), lineWidth: 1)
                        )
                )
                
                // 标签区域
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 80, maximum: .infinity), spacing: 8)
                    ], spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 6) {
                                Text(tag)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(ChoraiTheme.ink)
                                    .lineLimit(1)
                                
                                Button(action: {
                                    if let index = tags.firstIndex(of: tag) {
                                        tags.remove(at: index)
                                    }
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(ChoraiTheme.secondaryInk)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(ChoraiTheme.ink.opacity(0.2))
                            )
                        }
                        
                        if showAddTag {
                            HStack(spacing: 6) {
                                TextField("", text: $newTagText)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(ChoraiTheme.ink)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .frame(width: 80)
                                
                                Button(action: {
                                    if !newTagText.isEmpty {
                                        tags.append(newTagText)
                                        newTagText = ""
                                        showAddTag = false
                                    }
                                }) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(ChoraiTheme.ink)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(ChoraiTheme.ink.opacity(0.2))
                            )
                        } else {
                            Button(action: {
                                showAddTag = true
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(ChoraiTheme.ink)
                                    .frame(width: 24, height: 24)
                                    .background(
                                        Capsule()
                                            .fill(ChoraiTheme.ink.opacity(0.2))
                                    )
                                Spacer()
                            }
                        }
                    }
                    }
                    .frame(height: 70) // 固定高度为两行（约30*2 + 间距8）
                }
                
                // 操作按钮
                HStack(spacing: 16) {
                    Button(action: {
                        isPresented = false
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Discard")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(ChoraiTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(Color.clear)
                                .overlay(discardButtonTopLeftHighlight)
                                .overlay(discardButtonBottomRightHighlight)
                                .overlay(discardButtonTopEdgeHighlight)
                                .overlay(discardButtonBottomEdgeHighlight)
                        )
                    }
                    .accessibilityIdentifier("new-insight.discard")
                    
                    Button(action: {
                        confirmMerge()
                    }) {
                        HStack(spacing: 8) {
                            if isConfirming {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: ChoraiTheme.accent))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            Text(isConfirming ? "Confirming..." : "Accept")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(ChoraiTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(ChoraiTheme.ink.opacity(0.2))
                                .overlay(acceptButtonTopLeftHighlight)
                                .overlay(acceptButtonBottomRightHighlight)
                                .overlay(acceptButtonTopEdgeHighlight)
                                .overlay(acceptButtonBottomEdgeHighlight)
                        )
                        .disabled(isConfirming)
                    }
                    .accessibilityIdentifier("new-insight.accept")
                }
            }
                .padding(24)
                .background(
                    CardLevelMaterial(
                        style: levelStyle,
                        shape: RoundedRectangle(
                            cornerRadius: 20,
                            style: .continuous
                        )
                    )
                )
                .adaptiveContentGutter()
                .padding(.vertical, 12)
                .frame(minHeight: geometry.size.height, alignment: .center)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .transition(.opacity.combined(with: .scale))
        .onAppear {
            loadMergeResult()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notePublished)) { _ in
            // 发布成功后关闭弹窗
            isPresented = false
        }
        .overlay(alignment: .topLeading) {
            #if DEBUG
            VStack(spacing: 1) {
                Text("loaded")
                    .font(.system(size: 1))
                    .foregroundColor(ChoraiTheme.ink.opacity(0.01))
                    .accessibilityIdentifier("screen.new-insight.loaded")
                if let jobId = previewData?.data.jobId, !jobId.isEmpty {
                    Text(jobId)
                        .font(.system(size: 1))
                        .foregroundColor(ChoraiTheme.ink.opacity(0.01))
                        .accessibilityIdentifier("new-insight.job-id")
                }
            }
            .frame(width: 1, height: 1)
            #endif
        }
        .alert("Publish Failed", isPresented: .constant(publishManager.publishError != nil)) {
            Button("OK") {
                publishManager.publishError = nil
            }
        } message: {
            Text(publishManager.publishError ?? "")
        }
        .alert("Confirm Merge Failed", isPresented: .constant(confirmError != nil)) {
            Button("OK") {
                confirmError = nil
            }
        } message: {
            Text(confirmError ?? "")
        }
    }
    
    // MARK: 确认合并
    private func confirmMerge() {
        guard authManager.currentUser?.id != nil else {
            confirmError = "User not logged in"
            return
        }
        
        guard let jobId = previewData?.data.jobId, !jobId.isEmpty else {
            confirmError = "Merge job is missing"
            return
        }
        
        isConfirming = true
        confirmError = nil
        
        print("开始提交合并 job: \(jobId)")

        networkManager.commitMergeJob(jobId: jobId, titleOverride: titleText)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isConfirming = false
                    switch completion {
                    case .finished:
                        print("确认合并完成")
                    case .failure(let error):
                        self.confirmError = error.localizedDescription
                    }
                },
                receiveValue: { _ in
                    NotificationCenter.default.post(name: .exitMergePage, object: nil)
                    self.isPresented = false
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: 加载合并结果
    private func loadMergeResult() {
        if let previewData = previewData {
            // 使用预览数据
            titleText = "New Insight"
            contentText = previewData.data.newCard.content
            tags = previewData.data.newCard.tags
        } else if let mergeResult = mergeResult {
            // 使用合并结果的数据，但保持标题为"New Insight"
            titleText = "New Insight"
            contentText = mergeResult.newCard.content
            tags = mergeResult.newCard.tags
        } else {
            // 使用默认数据
            titleText = "New Insight"
            contentText = "By analyzing the content of multiple cards, we have integrated modern UI design trends and user experience improvement strategies:\n\n1. **Design Trends**\nDark mode becomes standard micro interaction to enhance user experience\nIntegration of 3D elements\nThe Return of Gradient Colors"
            tags = ["Design", "Inspiration", "Nature"]
        }
    }
    
    // MARK: 取消按钮高光效果
    private var discardButtonTopLeftHighlight: some View {
        Capsule()
            .stroke(ChoraiTheme.ink, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                Capsule()
                    .fill(
                        RadialGradient(
                            colors: [ChoraiTheme.ink, Color.clear],
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var discardButtonBottomRightHighlight: some View {
        Capsule()
            .stroke(ChoraiTheme.ink, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                Capsule()
                    .fill(
                        RadialGradient(
                            colors: [ChoraiTheme.ink, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var discardButtonTopEdgeHighlight: some View {
        Capsule()
            .stroke(ChoraiTheme.ink, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [ChoraiTheme.ink, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var discardButtonBottomEdgeHighlight: some View {
        Capsule()
            .stroke(ChoraiTheme.ink, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [ChoraiTheme.ink, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
    
    // MARK: 确认按钮高光效果
    private var acceptButtonTopLeftHighlight: some View {
        Capsule()
            .stroke(ChoraiTheme.ink, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                Capsule()
                    .fill(
                        RadialGradient(
                            colors: [ChoraiTheme.ink, Color.clear],
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var acceptButtonBottomRightHighlight: some View {
        Capsule()
            .stroke(ChoraiTheme.ink, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                Capsule()
                    .fill(
                        RadialGradient(
                            colors: [ChoraiTheme.ink, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var acceptButtonTopEdgeHighlight: some View {
        Capsule()
            .stroke(ChoraiTheme.ink, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [ChoraiTheme.ink, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var acceptButtonBottomEdgeHighlight: some View {
        Capsule()
            .stroke(ChoraiTheme.ink, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [ChoraiTheme.ink, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
    
}

#Preview {
    NewInsightView(isPresented: .constant(true))
} 
