import SwiftUI
import UIKit

enum PhotoJournalPhase: Equatable, Sendable {
    case ready
    case camera
    case saving
    case saved
    case denied
    case unavailable
    case failed
}

struct PhotoJournalView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var phase: PhotoJournalPhase = .ready
    @State private var preview: UIImage?
    @State private var savedEntry: JournalEntry?
    @State private var pendingSend: PendingAISend?
    @State private var sendTask: Task<Void, Never>?
    @State private var extractionError: String?
    @State private var loadedScreenshotScenario = false

    private var extracted: (artifact: AIArtifact, result: VisionReadResult)? {
        guard let savedEntry else { return nil }
        return JournalArtifactReader.decode(
            VisionReadResult.self,
            kind: .photoText,
            journal: savedEntry,
            artifacts: state.artifacts
        )
    }

    var body: some View {
        V2Screen(
            title: phase == .saved ? "Photo saved" : "Photograph a journal page",
            subtitle: "The original image stays on this device.",
            backAction: navigation.backAction(for: .journalPhoto),
            backLabel: "Close",
            backIcon: .close,
            bottomInset: DesignTokens.Spacing.section
        ) {
            content
        }
        .fullScreenCover(isPresented: cameraPresented) {
            CameraPicker(onImage: save, onCancel: { phase = .ready })
                .ignoresSafeArea()
        }
        .sheet(item: $pendingSend, onDismiss: cancelSend) { pending in
            WhatLeavesDeviceSheet(
                pending: pending,
                processingState: state.aiProcessingState(for: pending.action),
                onSend: { send(pending) },
                onCancel: cancelSend
            )
        }
        .task { await loadScreenshotScenarioIfNeeded() }
        .onDisappear(perform: cancelSend)
    }

    @ViewBuilder private var content: some View {
        photoPreview
        switch phase {
        case .ready:
            Button("Take photo", action: beginCapture)
                .buttonStyle(PrimaryButtonStyle())
        case .saving:
            Button("Saving") {}
                .buttonStyle(PrimaryButtonStyle())
                .disabled(true)
        case .saved:
            savedContent
        case .denied:
            StatusNotice(
                title: "Camera access is off",
                detail: "Enable camera access in Settings, then try again. Your existing journals are unchanged.",
                kind: .warning
            )
            Button("Try again", action: beginCapture).buttonStyle(SecondaryButtonStyle())
        case .unavailable:
            StatusNotice(
                title: "Camera unavailable",
                detail: "Use an iPhone with a camera to photograph a journal page.",
                kind: .warning
            )
        case .failed:
            StatusNotice(
                title: "Photo could not be saved",
                detail: "Your existing journals are unchanged. Try again.",
                kind: .warning
            )
            Button("Try again", action: beginCapture).buttonStyle(SecondaryButtonStyle())
        case .camera:
            EmptyView()
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let preview {
            Image(uiImage: preview)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.v2CardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.v2CardRadius, style: .continuous).stroke(DesignTokens.hairline, lineWidth: 1))
                .accessibilityLabel("Original journal photo")
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.v2CardRadius, style: .continuous)
                    .fill(DesignTokens.surfaceWarm)
                VStack(spacing: DesignTokens.Spacing.compact) {
                    IconTile(icon: .camera, size: 56, dark: true)
                    Text(phase == .saved ? "Original photo saved" : "Keep the full page inside the frame")
                        .font(TypeScale.rowTitleCompact)
                        .foregroundStyle(DesignTokens.cocoa)
                }
            }
            .frame(height: 320)
            .accessibilityLabel(phase == .saved ? "Original journal photo saved" : "Camera frame for a journal page")
        }
    }

    @ViewBuilder
    private var savedContent: some View {
        StatusNotice(
            title: "Saved on this device",
            detail: "The photo is the unchanged original source.",
            kind: .saved
        )
        if let extracted, !extracted.result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            extractedRegion(extracted)
            Button("Open journal to organize") { openJournal() }
                .buttonStyle(PrimaryButtonStyle())
        } else {
            extractionControls
            if savedEntry != nil {
                Button("View journal without extracting") { openJournal() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        if let extractionError {
            StatusNotice(
                title: "Text extraction did not finish",
                detail: "\(extractionError) The saved photo is unchanged.",
                kind: .warning
            )
        }
    }

    private func extractedRegion(
        _ extracted: (artifact: AIArtifact, result: VisionReadResult)
    ) -> some View {
        V2Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                HStack(spacing: DesignTokens.Spacing.compact) {
                    IconTile(icon: .sparkles, size: 34)
                    Text("Extracted text")
                        .font(TypeScale.cardTitle)
                        .foregroundStyle(DesignTokens.cocoa)
                }
                Text(extracted.result.text)
                    .font(TypeScale.body)
                    .foregroundStyle(DesignTokens.cocoa)
                    .fixedSize(horizontal: false, vertical: true)
                if !extracted.result.uncertainSpans.isEmpty {
                    Text("Check uncertain text: \(extracted.result.uncertainSpans.prefix(8).joined(separator: ", "))")
                        .font(TypeScale.meta)
                        .foregroundStyle(DesignTokens.yellowText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ProvenanceStack(provenance: Provenance(
                    voice: .candyCorn,
                    label: "Candy Corn extracted this",
                    detail: "\(extracted.artifact.provider), \(extracted.artifact.model)",
                    occurredAt: extracted.artifact.createdAt,
                    sourceRoute: .journalDetail
                ))
            }
        }
    }

    @ViewBuilder
    private var extractionControls: some View {
        if canExtract, let entry = savedEntry, let attachmentID = entry.originalAttachmentID {
            let processing = state.aiProcessingState(for: .readPhoto(journalID: entry.id, attachmentID: attachmentID)) == .processing
            V2GroupCard(title: "Organize") {
                V2ListRow(
                    icon: .sparkles,
                    title: processing ? "Working" : "Extract text",
                    detail: "Read the page into editable text. The photo stays.",
                    disabled: processing
                ) { prepareExtraction(journalID: entry.id, attachmentID: attachmentID) }
            }
        } else if state.aiMode == .off {
            StatusNotice(
                title: "Organizing is off",
                detail: "The photo is saved. You can use the journal manually or turn on Organizer later.",
                kind: .information
            )
        } else if !state.hasOpenRouterKey || !state.routerAvailable {
            StatusNotice(
                title: "Router key needed",
                detail: "The photo is saved. Add a key in AI settings before extracting text.",
                kind: .information
            )
        } else if savedEntry?.originalAttachmentID == nil {
            StatusNotice(
                title: "Photo unavailable",
                detail: "The journal row is saved, but no image is available to send.",
                kind: .warning
            )
        }
    }

    private var cameraPresented: Binding<Bool> {
        Binding(
            get: { phase == .camera },
            set: { if !$0 && phase == .camera { phase = .ready } }
        )
    }

    private var canExtract: Bool {
        state.aiMode != .off && state.aiProvider == .router && state.hasOpenRouterKey && state.routerAvailable
    }

    private func beginCapture() {
        guard phase != .saving else { return }
        Task {
            let status = await state.dependencies.photos.authorizationStatus()
            let permitted: Bool
            if status == .authorized {
                permitted = true
            } else if status == .notDetermined {
                permitted = await state.dependencies.photos.requestPermission()
            } else {
                permitted = false
            }
            guard permitted else {
                phase = .denied
                return
            }
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                phase = .unavailable
                return
            }
            phase = .camera
        }
    }

    private func save(_ image: UIImage) {
        phase = .saving
        preview = image
        extractionError = nil
        Task {
            guard let data = image.jpegData(compressionQuality: 0.92), !data.isEmpty else {
                phase = .failed
                return
            }
            let width = image.cgImage?.width ?? Int(image.size.width * image.scale)
            let height = image.cgImage?.height ?? Int(image.size.height * image.scale)
            guard let attachment = await state.savePhotoJPEG(data, pixelWidth: width, pixelHeight: height),
                  let entry = await state.createJournal(rawText: "", inputType: .photo, attachmentID: attachment.id) else {
                phase = .failed
                return
            }
            savedEntry = entry
            state.selectJournal(id: entry.id)
            phase = .saved
        }
    }

    private func prepareExtraction(journalID: UUID, attachmentID: UUID) {
        guard pendingSend == nil else { return }
        extractionError = nil
        do {
            pendingSend = try state.prepareAISend(.readPhoto(journalID: journalID, attachmentID: attachmentID))
        } catch let error as UserFacingError {
            extractionError = error.message
        } catch {
            extractionError = "This photo is not ready to send."
        }
    }

    private func send(_ pending: PendingAISend) {
        guard sendTask == nil else { return }
        if case .failed = state.aiProcessingState(for: pending.action) {
            pendingSend = nil
            if case let .readPhoto(journalID, attachmentID) = pending.action {
                prepareExtraction(journalID: journalID, attachmentID: attachmentID)
            }
            return
        }
        sendTask = Task {
            let succeeded = await state.performAISend(pending)
            guard !Task.isCancelled, pendingSend?.id == pending.id else {
                sendTask = nil
                return
            }
            sendTask = nil
            if succeeded {
                pendingSend = nil
                guard let extracted,
                      !extracted.result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    extractionError = "Candy Corn did not find usable text."
                    return
                }
            } else if case let .failed(message) = state.aiProcessingState(for: pending.action) {
                extractionError = message
            }
        }
    }

    private func cancelSend() {
        sendTask?.cancel()
        sendTask = nil
        pendingSend = nil
    }

    private func openJournal() {
        guard let savedEntry, state.journals.contains(where: { $0.id == savedEntry.id }) else {
            extractionError = "This journal is no longer available."
            return
        }
        state.selectJournal(id: savedEntry.id)
        navigation.goBack(from: .journalPhoto)
        navigation.navigate(to: .journalDetail)
    }

    private func loadScreenshotScenarioIfNeeded() async {
        guard !loadedScreenshotScenario,
              state.dependencies.screenshotScenario == .photoSend,
              let entry = state.journals.first(where: { $0.id == ScreenshotScenario.photoJournalID }) else {
            return
        }
        loadedScreenshotScenario = true
        savedEntry = entry
        state.selectJournal(id: entry.id)
        phase = .saved
        state.setAIMode(.organizer)
        state.setAIProvider(.router)
        if let attachment = state.attachments.first(where: { $0.id == entry.originalAttachmentID }),
           let url = try? await state.dependencies.attachments.url(for: attachment) {
            preview = UIImage(contentsOfFile: url.path)
        }
        if let attachmentID = entry.originalAttachmentID {
            prepareExtraction(journalID: entry.id, attachmentID: attachmentID)
        }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true, completion: onCancel)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                picker.dismiss(animated: true, completion: onCancel)
                return
            }
            picker.dismiss(animated: true) { self.onImage(image) }
        }
    }
}
